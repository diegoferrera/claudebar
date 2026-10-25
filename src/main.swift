import Cocoa
import SwiftUI
import UserNotifications

// ClaudeBar: barra de menus com o uso do plano Claude + sessões abertas; abrir o app mostra o painel.

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    static let work = DispatchQueue(label: "claudebar.load", qos: .utility)
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let store = Store()
    let nav = Nav()
    let menu = NSMenu()
    var window: NSWindow?
    var lastStates: [String: SessState] = [:]
    var lastDirMod: Date? = nil
    var lastPrune = Date.distantPast
    var blink = false

    func applicationDidFinishLaunching(_ n: Notification) {
        Prefs.register()
        try? FileManager.default.createDirectory(at: deliveredDir, withIntermediateDirectories: true)
        menu.delegate = self; item.menu = menu
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        store.history = History.load(); store.agents = Agents.load()
        (store.session, store.week, store.updated) = loadUsageCache()
        renderTitle()
        refreshUsage(); refreshSessions()
        // tolerância deixa o macOS agrupar os despertares (economia de energia)
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in self.refreshUsage() }.tolerance = 10
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.refreshSessions() }.tolerance = 0.4
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.renderTitle()
        }
        // aberto pelo Finder/Spotlight (e não pelo launchd no login): mostra o painel
        if ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] != launchLabel { openPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { openPanel(); return false }

    // MARK: dados

    var nextFetch = Date.distantPast
    var backoff: TimeInterval = 0

    // consulta a cada 2 min; se a Anthropic limitar (429), espera 5, 10, 20… até 30 min
    func refreshUsage(force: Bool = false) {
        guard force || Date() >= nextFetch else { return }
        nextFetch = Date().addingTimeInterval(110)
        App.work.async {
            let r = loadLimits()
            DispatchQueue.main.async {
                switch r {
                case .ok(let s, let w) where s != nil || w != nil:
                    self.backoff = 0
                    self.store.session = s; self.store.week = w; self.store.updated = Date()
                    saveUsageCache(s, w)
                    if let smp = History.append(s, w) { self.store.history.append(smp) }
                case .rateLimited:
                    self.backoff = min(max(self.backoff * 2, 300), 1800)
                    self.nextFetch = Date().addingTimeInterval(self.backoff)
                default: break
                }
                self.renderTitle()
                writeShare(self.store.session, self.store.week, self.store.sessions)
            }
        }
    }

    // 1 stat por segundo; só relê os arquivos quando a pasta muda (ou a cada 15s, para limpar sessões fechadas)
    func refreshSessions() {
        let mod = dirMod(sessionsDir)
        if mod != lastDirMod || Date().timeIntervalSince(lastPrune) > 15 {
            lastDirMod = mod; lastPrune = Date()
            store.sessions = loadSessions()
            notifyChanges()
        }
        if store.sessions.contains(where: { $0.state == .waiting }) { blink.toggle(); renderTitle() }
        else if blink { blink = false; renderTitle() }
    }

    // avisa quando uma sessão termina ou passa a pedir permissão
    func notifyChanges() {
        for s in store.sessions {
            let before = lastStates[s.id]
            if Prefs.notifyDone && before == .working && s.state == .idle { notify("\(store.name(s)) terminou", s.prompt) }
            if Prefs.notifyPermission && before != nil && before != .waiting && s.state == .waiting {
                notify("\(store.name(s)) pede permissão", s.message)
            }
        }
        lastStates = Dictionary(store.sessions.map { ($0.id, $0.state) }, uniquingKeysWith: { a, _ in a })
    }

    func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func openMaestri() {
        menu.cancelTracking()
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Maestri.app"), configuration: .init())
    }

    // MARK: janela

    @objc func openPanel() {
        menu.cancelTracking()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "ClaudeBar"
            w.contentViewController = NSHostingController(rootView: PanelView(store: store, nav: nav, openMaestri: { [weak self] in self?.openMaestri() }))
            w.toolbar = NSToolbar(); w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false; w.delegate = self
            w.setContentSize(NSSize(width: 860, height: 600)); w.center()
            w.setFrameAutosaveName("ClaudeBarPanel")
            window = w
        }
        store.sessions = loadSessions()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // fechou a janela: some do Dock e libera a memória da interface
    func windowWillClose(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async { self.window = nil }
    }

    // MARK: barra e menu

    func menuNeedsUpdate(_ m: NSMenu) { store.sessions = loadSessions(); buildMenu() }

    func renderTitle() {
        let waiting = store.sessions.contains { $0.state == .waiting }
        // cada número com a sua cor (limites em Ajustes)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        func pct(_ l: Limit?) -> NSAttributedString {
            guard let l = l else { return NSAttributedString(string: "–", attributes: [.font: font]) }
            return NSAttributedString(string: "\(Int(l.pct.rounded()))%", attributes: [.font: font, .foregroundColor: levelColor(l.pct)])
        }
        var star: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .baselineOffset: -1]
        if waiting { star[.foregroundColor] = blink ? NSColor.systemOrange : NSColor.systemRed }
        let style = Prefs.barStyle
        let t = NSMutableAttributedString(string: style == .icon ? "✳︎" : "✳︎ ", attributes: star)
        if style != .icon { t.append(pct(store.session)) }
        if style == .both { t.append(NSAttributedString(string: " · ", attributes: [.font: font])); t.append(pct(store.week)) }
        item.button?.attributedTitle = t
        item.button?.toolTip = waiting ? "Uma sessão pede permissão" : "Claude: sessão · semana"
    }

    func buildMenu() {
        menu.removeAllItems()
        let session = store.session, week = store.week

        // título, como "Bateria" / "Wi-Fi"
        let worst = max(session?.pct ?? 0, week?.pct ?? 0)
        let status = (session == nil && week == nil) ? "Não deu para ler o uso. Confira o login do Claude Code."
            : worst >= Prefs.redAt ? "Perto do limite" : worst >= Prefs.orangeAt ? "Uso moderado" : "Dentro do previsto"
        menu.addItem(hosted(Section {
            Text("Claude").font(.system(size: 13, weight: .bold))
            Text(status + (store.updated.map { ", atualizado às \(hm.string(from: $0))" } ?? ""))
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 2)
        }))
        menu.addItem(.separator())

        if session != nil || week != nil {
            menu.addItem(hosted(Section {
                SectionTitle(text: "Limites do plano")
                limitRow("Sessão atual", "clock", session, sessionReset(session))
                limitRow("Esta semana", "calendar", week, weekReset(week))
            }))
        }

        // sessões: quem pede permissão primeiro, depois quem trabalha, depois as paradas (mais recentes antes)
        let sessions = store.sessions
        let order: [SessState: Int] = [.waiting: 0, .working: 1, .idle: 2]
        let sorted = sessions.sorted { (order[$0.state]!, $1.since) < (order[$1.state]!, $0.since) }
        let shown = Array(sorted.filter { $0.state != .idle } + sorted.filter { $0.state == .idle }.prefix(6))
        let hidden = sorted.count - shown.count
        let working = sessions.filter { $0.state == .working }.count
        menu.addItem(.separator())
        menu.addItem(hosted(Section {
            SectionTitle(text: "Sessões", trailing: sessions.isEmpty ? nil : working > 0 ? "\(working) trabalhando" : "\(sessions.count) abertas")
            if sessions.isEmpty {
                Text("Nenhuma sessão registrada. Elas aparecem aqui a partir da próxima mensagem em cada terminal.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
            ForEach(shown) { s in SessionRow(s: s, name: self.store.name(s), open: { [weak self] in self?.openMaestri() }) }
            if hidden > 0 {
                Text("Mais \(hidden) paradas").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 2)
            }
        }))

        menu.addItem(.separator())
        let p = NSMenuItem(title: "Abrir painel…", action: #selector(openPanel), keyEquivalent: ","); p.target = self; menu.addItem(p)
        let r = NSMenuItem(title: "Atualizar", action: #selector(refreshNow), keyEquivalent: "r"); r.target = self; menu.addItem(r)
        let q = NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); menu.addItem(q)
    }

    @objc func refreshNow() { refreshUsage(force: backoff == 0); lastPrune = .distantPast; refreshSessions() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
