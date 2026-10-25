import Cocoa

// Dados do ClaudeBar: uso do plano, sessões (gravadas por session.sh), histórico, agentes e ajustes.

let home = FileManager.default.homeDirectoryForCurrentUser
let baseDir = home.appendingPathComponent(".claude/menubar")
let sessionsDir = baseDir.appendingPathComponent("sessions")
let historyFile = baseDir.appendingPathComponent("history.jsonl")
let agentsFile = baseDir.appendingPathComponent("agents.json")
let deliveredDir = baseDir.appendingPathComponent("delivered")
let launchLabel = "com.\(NSUserName()).claudebar"

// MARK: - Ajustes

enum BarStyle: String, CaseIterable { case both, session, icon }

enum Prefs {
    static let d = UserDefaults.standard
    static func register() {
        d.register(defaults: ["orangeAt": 50.0, "redAt": 80.0, "notifyDone": true, "notifyPermission": true,
                              "barStyle": BarStyle.both.rawValue, "widget": true])
    }
    static var orangeAt: Double { d.double(forKey: "orangeAt") }
    static var redAt: Double { d.double(forKey: "redAt") }
    static var notifyDone: Bool { d.bool(forKey: "notifyDone") }
    static var notifyPermission: Bool { d.bool(forKey: "notifyPermission") }
    static var widget: Bool { d.bool(forKey: "widget") }
    static var barStyle: BarStyle { BarStyle(rawValue: d.string(forKey: "barStyle") ?? "") ?? .both }
}

func levelColor(_ pct: Double) -> NSColor { pct >= Prefs.redAt ? .systemRed : pct >= Prefs.orangeAt ? .systemOrange : .systemGreen }

// abrir ao iniciar o Mac = LaunchAgent habilitado no launchd
enum Login {
    static func run(_ args: [String]) -> String {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = args
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }
    static var target: String { "gui/\(getuid())/\(launchLabel)" }
    static var enabled: Bool {
        let line = run(["print-disabled", "gui/\(getuid())"]).split(separator: "\n").first { $0.contains("\"\(launchLabel)\"") }
        guard let l = line else { return true }
        return !(l.contains("disabled") || l.contains("true"))
    }
    static func set(_ on: Bool) { _ = run([on ? "enable" : "disable", target]) }
}

// MARK: - Uso do plano

struct Limit { let pct: Double; let reset: Date? }

// percentuais oficiais do plano (os mesmos de "Seu uso" no app), com o token OAuth do Claude Code
enum FetchResult { case ok(Limit?, Limit?), rateLimited, failed }

// último valor conhecido, para reiniciar sem mostrar "–"
let usageCache = baseDir.appendingPathComponent("last-usage.json")
func saveUsageCache(_ s: Limit?, _ w: Limit?) {
    func o(_ l: Limit?) -> Any { l.map { ["pct": $0.pct, "reset": $0.reset?.timeIntervalSince1970 ?? 0] as [String: Any] } ?? NSNull() }
    if let d = try? JSONSerialization.data(withJSONObject: ["t": Date().timeIntervalSince1970, "session": o(s), "week": o(w)]) {
        try? d.write(to: usageCache, options: .atomic)
    }
}
func loadUsageCache() -> (Limit?, Limit?, Date?) {
    guard let d = try? Data(contentsOf: usageCache), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return (nil, nil, nil) }
    func l(_ k: String) -> Limit? {
        guard let x = o[k] as? [String: Any], let p = x["pct"] as? Double else { return nil }
        let r = x["reset"] as? Double ?? 0
        return Limit(pct: p, reset: r > 0 ? Date(timeIntervalSince1970: r) : nil)
    }
    return (l("session"), l("week"), (o["t"] as? Double).map { Date(timeIntervalSince1970: $0) })
}

func loadLimits() -> FetchResult {
    let sec = Process(); let pipe = Pipe()
    sec.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    sec.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    sec.standardOutput = pipe; sec.standardError = FileHandle.nullDevice
    guard (try? sec.run()) != nil else { return .failed }
    let raw = pipe.fileHandleForReading.readDataToEndOfFile(); sec.waitUntilExit()
    guard let cred = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
          let oauth = cred["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String else { return .failed }
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    var body: Data? = nil; var code = 0; let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { d, r, _ in body = d; code = (r as? HTTPURLResponse)?.statusCode ?? 0; sem.signal() }.resume(); sem.wait()
    if code == 429 { return .rateLimited }
    guard code == 200, let b = body, let obj = try? JSONSerialization.jsonObject(with: b) as? [String: Any] else { return .failed }
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    func lim(_ k: String) -> Limit? {
        guard let o = obj[k] as? [String: Any], let u = o["utilization"] as? Double else { return nil }
        return Limit(pct: u, reset: (o["resets_at"] as? String).flatMap { iso.date(from: $0) })
    }
    return .ok(lim("five_hour"), lim("seven_day"))
}

// MARK: - Histórico (um ponto sempre que o uso muda, ou a cada 10 min; guarda 14 dias)

struct Sample: Codable { let t: Double; let s: Double?; let w: Double? }

enum History {
    static var last: Sample? = nil
    static var lastPrune = Date.distantPast

    static func load(days: Double = 14) -> [Sample] {
        guard let txt = try? String(contentsOf: historyFile, encoding: .utf8) else { return [] }
        let from = Date().timeIntervalSince1970 - days * 86400
        let out = txt.split(separator: "\n").compactMap { try? JSONDecoder().decode(Sample.self, from: Data($0.utf8)) }.filter { $0.t >= from }
        last = out.last
        return out
    }

    // devolve o ponto gravado, ou nil se nada mudou
    static func append(_ s: Limit?, _ w: Limit?) -> Sample? {
        guard s != nil || w != nil else { return nil }
        let now = Date().timeIntervalSince1970
        let smp = Sample(t: now, s: s?.pct, w: w?.pct)
        if let l = last, l.s == smp.s, l.w == smp.w, now - l.t < 600 { return nil }
        guard var line = try? JSONEncoder().encode(smp) else { return nil }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: historyFile) { h.seekToEndOfFile(); h.write(line); try? h.close() }
        else { try? line.write(to: historyFile) }
        last = smp
        if Date().timeIntervalSince(lastPrune) > 86400 { lastPrune = Date(); prune() }
        return smp
    }

    static func prune() {
        let keep = load()
        let data = keep.compactMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n"
        try? data.write(to: historyFile, atomically: true, encoding: .utf8)
    }
}

// "no ritmo atual…": ritmo dos últimos `window` segundos, desde o último reset
func forecast(_ samples: [Sample], _ value: (Sample) -> Double?, _ limit: Limit?, window: TimeInterval) -> String? {
    guard let l = limit else { return nil }
    let now = Date().timeIntervalSince1970
    var pts = samples.filter { now - $0.t <= window }.compactMap { s in value(s).map { (s.t, $0) } }
    if let drop = pts.indices.dropFirst().last(where: { pts[$0].1 < pts[$0 - 1].1 }) { pts = Array(pts[drop...]) }
    guard let first = pts.first, now - first.0 >= 15 * 60 else { return "A previsão aparece depois de uns 15 minutos de histórico." }
    let rate = (l.pct - first.1) / (now - first.0)  // % por segundo
    if rate <= 0.000_01 { return "Ritmo parado agora." }
    let end = now + (100 - l.pct) / rate
    if let r = l.reset?.timeIntervalSince1970, end > r {
        let atReset = min(100, l.pct + rate * (r - now))
        return "No ritmo atual, chega ao reset com uns \(Int(atReset.rounded()))% usados."
    }
    let df = DateFormatter(); df.locale = Locale(identifier: "pt_BR")
    df.dateFormat = end - now < 86400 ? "HH:mm" : "EEEE, HH:mm"
    return "No ritmo atual, o limite acaba \(end - now < 86400 ? "às" : "na") \(df.string(from: Date(timeIntervalSince1970: end)))."
}

// MARK: - Sessões

enum SessState: String { case waiting, working, idle }
struct Sess: Identifiable {
    let id: String; let file: URL; let cwd: String; let terminal: String
    let state: SessState; let message: String; let prompt: String; let since: Date
    var project: String { cwd.isEmpty ? "sessão" : (cwd as NSString).lastPathComponent }
}

func dirMod(_ u: URL) -> Date? { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }

// lê as sessões; apaga as de terminais já fechados (processo do claude morto)
func loadSessions() -> [Sess] {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) else { return [] }
    return files.filter { $0.pathExtension == "json" }.compactMap { f in
        guard let d = try? Data(contentsOf: f), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let pid = (o["pid"] as? NSNumber)?.int32Value ?? 0
        let updated = Date(timeIntervalSince1970: o["updated"] as? Double ?? 0)
        if (pid > 0 && kill(pid, 0) != 0) || (pid == 0 && Date().timeIntervalSince(updated) > 6 * 3600) {
            try? fm.removeItem(at: f); return nil
        }
        return Sess(id: o["session_id"] as? String ?? f.lastPathComponent, file: f,
                    cwd: o["cwd"] as? String ?? "", terminal: o["terminal"] as? String ?? "",
                    state: SessState(rawValue: o["state"] as? String ?? "") ?? .idle,
                    message: o["message"] as? String ?? "", prompt: o["prompt"] as? String ?? "",
                    since: Date(timeIntervalSince1970: o["since"] as? Double ?? updated.timeIntervalSince1970))
    }
}

func ago(_ d: Date) -> String {
    let m = max(0, Int(Date().timeIntervalSince(d) / 60))
    if m < 1 { return "agora" }
    if m < 60 { return "há \(m) min" }
    if m < 24 * 60 { return "há \(m / 60)h\(m % 60 > 0 ? String(format: "%02d", m % 60) : "")" }
    return "há \(m / 1440) d"
}

let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

func sessionReset(_ l: Limit?) -> String {
    guard let r = l?.reset else { return "Sem sessão ativa" }
    let m = max(0, Int(r.timeIntervalSinceNow / 60))
    return "Redefine às \(hm.string(from: r)), em " + (m >= 60 ? "\(m / 60)h\(String(format: "%02d", m % 60))" : "\(m) min")
}
func weekReset(_ l: Limit?) -> String {
    guard let r = l?.reset else { return "" }
    let df = DateFormatter(); df.locale = Locale(identifier: "pt_BR"); df.dateFormat = "EEEE, HH:mm"
    return "Reinicia " + df.string(from: r)
}

// MARK: - Agentes (nome por terminal, pastas proibidas, recados) — lidos também por session.sh

struct Agent: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var terminal: String
    var cwd: String
    var blocked: [String] = []
    var note = ""
    var noteId = ""
    var noteDelivered: Bool { !noteId.isEmpty && FileManager.default.fileExists(atPath: deliveredDir.appendingPathComponent(noteId).path) }
}

enum Agents {
    static func load() -> [Agent] {
        struct F: Codable { var agents: [Agent] }
        guard let d = try? Data(contentsOf: agentsFile), let f = try? JSONDecoder().decode(F.self, from: d) else { return [] }
        return f.agents
    }
    static func save(_ a: [Agent]) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(["agents": a]) { try? d.write(to: agentsFile, options: .atomic) }
    }
    // mesma regra do session.sh: id do terminal do Maestri primeiro, depois a pasta
    static func match(_ agents: [Agent], _ s: Sess) -> Agent? {
        if !s.terminal.isEmpty, let a = agents.first(where: { $0.terminal == s.terminal }) { return a }
        return agents.first { $0.cwd == s.cwd }
    }
}

// MARK: - iPhone: o widget do Scriptable lê este arquivo pelo iCloud Drive

let scriptableDir = home.appendingPathComponent("Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents")
let widgetSource = Bundle.main.url(forResource: "widget", withExtension: "js") ?? home.appendingPathComponent("claude-menubar/widget.js")
var lastShareKey = ""
var lastShareDate = Date.distantPast

func writeShare(_ session: Limit?, _ week: Limit?, _ sessions: [Sess]) {
    let fm = FileManager.default
    guard Prefs.widget, fm.fileExists(atPath: scriptableDir.path) else { return }  // desligado, ou iCloud/Scriptable ausentes
    guard session != nil || week != nil else { return }  // sem números (ex.: Anthropic limitou): mantém o último envio
    let script = scriptableDir.appendingPathComponent("Claude.js")
    if !fm.fileExists(atPath: script.path) || (dirMod(widgetSource) ?? .distantPast) > (dirMod(script) ?? .distantPast) {
        try? fm.removeItem(at: script); try? fm.copyItem(at: widgetSource, to: script)
    }
    // só envia ao iCloud quando algo muda (ou a cada 15 min, para o widget saber que o Mac está ligado)
    let key = "\(Int(session?.pct ?? -1))|\(Int(week?.pct ?? -1))|\(sessions.map { $0.state.rawValue }.sorted())|\(Prefs.orangeAt)|\(Prefs.redAt)"
    if key == lastShareKey && Date().timeIntervalSince(lastShareDate) < 15 * 60 { return }
    lastShareKey = key; lastShareDate = Date()
    func lim(_ l: Limit?) -> Any { l.map { ["pct": $0.pct, "reset": $0.reset?.timeIntervalSince1970 ?? 0] as [String: Any] } ?? NSNull() }
    let obj: [String: Any] = [
        "updated": Int(Date().timeIntervalSince1970), "session": lim(session), "week": lim(week),
        "orangeAt": Prefs.orangeAt, "redAt": Prefs.redAt,
        "sessions": ["waiting": sessions.filter { $0.state == .waiting }.count,
                     "working": sessions.filter { $0.state == .working }.count,
                     "idle": sessions.filter { $0.state == .idle }.count]]
    if let d = try? JSONSerialization.data(withJSONObject: obj) {
        try? d.write(to: scriptableDir.appendingPathComponent("claude-uso.json"), options: .atomic)
    }
}
