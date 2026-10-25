import SwiftUI
import Charts

// Janela do ClaudeBar, no estilo do app Ajustes do Sistema: barra lateral + painéis.

final class Store: ObservableObject {
    @Published var session: Limit?
    @Published var week: Limit?
    @Published var updated: Date?
    @Published var sessions: [Sess] = []
    @Published var history: [Sample] = []
    @Published var agents: [Agent] = [] { didSet { if !demo { Agents.save(agents) } } }

    func name(_ s: Sess) -> String { Agents.match(agents, s)?.name ?? s.project }

    // cria (ou devolve) o agente ligado a este terminal
    func agentFor(_ s: Sess) -> String {
        if let a = Agents.match(agents, s) { return a.id }
        let a = Agent(name: s.project, terminal: s.terminal, cwd: s.cwd)
        agents.append(a); return a.id
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Visão geral", sessions = "Sessões", agents = "Agentes", settings = "Ajustes"
    var id: Self { self }
    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .sessions: return "terminal"
        case .agents: return "person.2"
        case .settings: return "gearshape"
        }
    }
    var tint: Color {
        switch self {
        case .overview: return .green
        case .sessions: return .blue
        case .agents: return .purple
        case .settings: return .gray
        }
    }
}

final class Nav: ObservableObject {
    @Published var pane: Pane? = .overview
    @Published var agentId: String?
}

struct PanelView: View {
    @ObservedObject var store: Store
    @ObservedObject var nav: Nav
    let openMaestri: () -> Void

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $nav.pane) { p in
                HStack(spacing: 8) {
                    Image(systemName: p.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(p.tint.gradient))
                    Text(p.rawValue)
                    if p == .sessions, store.sessions.contains(where: { $0.state == .waiting }) {
                        Spacer(); Circle().fill(.orange).frame(width: 7, height: 7)
                    }
                }
                .tag(p)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            switch nav.pane ?? .overview {
            case .overview: OverviewPane(store: store)
            case .sessions: SessionsPane(store: store, nav: nav, openMaestri: openMaestri)
            case .agents: AgentsPane(store: store, nav: nav)
            case .settings: SettingsPane()
            }
        }
        .frame(minWidth: 780, minHeight: 540)
    }
}

// vazio com direção (o ContentUnavailableView só existe a partir do macOS 14)
struct EmptyState: View {
    let title: String; let systemImage: String; let description: Text
    init(_ title: String, systemImage: String, description: Text) { self.title = title; self.systemImage = systemImage; self.description = description }
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            description.foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Visão geral

struct BigRing: View {
    let title: String; let limit: Limit?; let sub: String; let forecast: String?
    var body: some View {
        let pct = limit?.pct ?? 0
        let c = Color(nsColor: limit == nil ? .tertiaryLabelColor : levelColor(pct))
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 12)
                Circle().trim(from: 0, to: max(0.005, min(pct / 100, 1)))
                    .stroke(c, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(limit.map { "\(Int($0.pct.rounded()))" } ?? "–").font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit().foregroundStyle(c)
                    Text("%").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title3.weight(.semibold))
                Text(sub).font(.callout).foregroundStyle(.secondary)
                if let f = forecast { Text(f).font(.callout).foregroundStyle(.primary.opacity(0.8)).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06)))
    }
}

struct OverviewPane: View {
    @ObservedObject var store: Store
    @State private var range = 0  // 0 = hoje, 1 = 7 dias

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    BigRing(title: "Sessão atual", limit: store.session, sub: sessionReset(store.session),
                            forecast: forecast(store.history, { $0.s }, store.session, window: 3600))
                    BigRing(title: "Esta semana", limit: store.week, sub: weekReset(store.week),
                            forecast: forecast(store.history, { $0.w }, store.week, window: 86400))
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Histórico").font(.headline)
                        Spacer()
                        Picker("", selection: $range) { Text("Hoje").tag(0); Text("7 dias").tag(1) }
                            .pickerStyle(.segmented).frame(width: 160).labelsHidden()
                    }
                    let from = range == 0 ? Calendar.current.startOfDay(for: Date()) : Date().addingTimeInterval(-7 * 86400)
                    let pts = store.history.filter { $0.t >= from.timeIntervalSince1970 }
                    if pts.count < 2 {
                        Text("O gráfico se forma a partir de agora: o ClaudeBar guarda um ponto sempre que o uso muda.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        Chart {
                            RuleMark(y: .value("Laranja", Prefs.orangeAt)).foregroundStyle(.orange.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            RuleMark(y: .value("Vermelho", Prefs.redAt)).foregroundStyle(.red.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            ForEach(pts.indices, id: \.self) { i in
                                if let s = pts[i].s {
                                    LineMark(x: .value("Hora", Date(timeIntervalSince1970: pts[i].t)), y: .value("%", s),
                                             series: .value("Limite", "Sessão"))
                                        .foregroundStyle(by: .value("Limite", "Sessão")).interpolationMethod(.stepEnd)
                                }
                                if let w = pts[i].w {
                                    LineMark(x: .value("Hora", Date(timeIntervalSince1970: pts[i].t)), y: .value("%", w),
                                             series: .value("Limite", "Semana"))
                                        .foregroundStyle(by: .value("Limite", "Semana")).interpolationMethod(.stepEnd)
                                }
                            }
                        }
                        .chartForegroundStyleScale(["Sessão": Color.teal, "Semana": Color.indigo])
                        .chartYScale(domain: 0...100)
                        .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                            AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") } } }
                        .frame(height: 220)
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06)))

                if let u = store.updated {
                    Text("Atualizado às \(hm.string(from: u)). O limite é o mesmo do Claude no celular e no site.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(20)
        }
        .navigationTitle("Visão geral")
    }
}

// MARK: - Sessões

struct SessionsPane: View {
    @ObservedObject var store: Store
    @ObservedObject var nav: Nav
    let openMaestri: () -> Void

    var body: some View {
        let order: [SessState: Int] = [.waiting: 0, .working: 1, .idle: 2]
        let list = store.sessions.sorted { (order[$0.state]!, $1.since) < (order[$1.state]!, $0.since) }
        // pastas com mais de uma sessão aberta ao mesmo tempo
        let shared = Dictionary(grouping: store.sessions, by: \.cwd).filter { $0.value.count > 1 }
        Group {
            if list.isEmpty {
                EmptyState("Nenhuma sessão aberta", systemImage: "terminal",
                                       description: Text("Cada terminal do Claude aparece aqui a partir da próxima mensagem."))
            } else {
                List(list) { s in
                    HStack(alignment: .top, spacing: 12) {
                        StateDot(s: s, size: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(store.name(s)).font(.body.weight(.medium))
                                if store.name(s) != s.project { Text(s.project).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(stateLook(s).text + (s.state == .waiting && !s.message.isEmpty ? ": \(s.message)" : ""))
                                .font(.callout).foregroundStyle(s.state == .waiting ? Color.orange : .secondary)
                            if !s.prompt.isEmpty {
                                Text(s.prompt).font(.callout).foregroundStyle(.primary.opacity(0.8)).lineLimit(2)
                            }
                            if let others = shared[s.cwd] {
                                Label("Mesma pasta que \(others.filter { $0.id != s.id }.map { store.name($0) }.joined(separator: ", "))",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Menu {
                            Button("Configurar agente…") { nav.agentId = store.agentFor(s); nav.pane = .agents }
                            Button("Mostrar pasta no Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: s.cwd) }
                            Button("Abrir o Maestri") { openMaestri() }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Sessões")
    }
}

// MARK: - Agentes

struct AgentsPane: View {
    @ObservedObject var store: Store
    @ObservedObject var nav: Nav

    var body: some View {
        HSplitView {
            List(selection: $nav.agentId) {
                ForEach(store.agents) { a in
                    let open = store.sessions.contains { Agents.match(store.agents, $0)?.id == a.id }
                    HStack {
                        Circle().fill(open ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                        Text(a.name)
                        Spacer()
                        if !a.blocked.isEmpty { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                        if !a.note.isEmpty && !a.noteDelivered { Image(systemName: "envelope.fill").font(.caption).foregroundStyle(.blue) }
                    }
                    .tag(a.id)
                }
            }
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 260)

            Group {
                if let id = nav.agentId, let i = store.agents.firstIndex(where: { $0.id == id }) {
                    AgentDetail(store: store, index: i, onDelete: { nav.agentId = nil })
                        .id(id)
                } else {
                    EmptyState("Escolha um agente", systemImage: "person.2",
                                           description: Text(store.agents.isEmpty
                                                             ? "Em Sessões, clique em ⋯ › Configurar agente para dar nome a um terminal."
                                                             : "Dê nome aos terminais, proíba pastas e deixe recados."))
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Agentes")
    }
}

struct AgentDetail: View {
    @ObservedObject var store: Store
    let index: Int
    let onDelete: () -> Void
    @State private var draft = ""

    var body: some View {
        let a = store.agents[index]
        let live = store.sessions.first { Agents.match(store.agents, $0)?.id == a.id }
        Form {
            SwiftUI.Section {
                TextField("Nome", text: $store.agents[index].name)
                LabeledContent("Pasta") { Text(a.cwd).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                LabeledContent("Agora") {
                    if let s = live { Text(stateLook(s).text).foregroundStyle(.secondary) } else { Text("Terminal fechado").foregroundStyle(.tertiary) }
                }
            } footer: {
                Text("O nome aparece no menu do ✳ e nas notificações.").foregroundStyle(.secondary)
            }

            SwiftUI.Section {
                if a.blocked.isEmpty {
                    Text("Nenhuma pasta proibida").foregroundStyle(.secondary)
                }
                ForEach(a.blocked, id: \.self) { b in
                    HStack {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        Text(b.replacingOccurrences(of: home.path, with: "~")).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { store.agents[index].blocked.removeAll { $0 == b } } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.red)
                    }
                }
                Button("Proibir uma pasta…") { pickFolder() }
            } header: {
                Text("Pastas proibidas")
            } footer: {
                Text("O agente fica impedido de editar, criar, mover ou apagar arquivos nessas pastas. Ler continua permitido.")
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section {
                if !a.note.isEmpty {
                    LabeledContent("Recado atual") {
                        Text(a.noteDelivered ? "Entregue" : "Espera a próxima mensagem")
                            .foregroundStyle(a.noteDelivered ? Color.green : .blue)
                    }
                    Text(a.note).foregroundStyle(.secondary)
                }
                TextField("Escreva um recado para este agente", text: $draft, axis: .vertical).lineLimit(2...5)
                HStack {
                    Button("Enviar recado") {
                        store.agents[index].note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.agents[index].noteId = UUID().uuidString; draft = ""
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !a.note.isEmpty {
                        Button("Apagar recado") { store.agents[index].note = ""; store.agents[index].noteId = "" }
                    }
                }
            } header: {
                Text("Recado")
            } footer: {
                Text("O agente recebe o recado junto com a próxima mensagem que você mandar naquele terminal.").foregroundStyle(.secondary)
            }

            SwiftUI.Section {
                Button("Apagar agente", role: .destructive) {
                    let id = a.id; onDelete(); store.agents.removeAll { $0.id == id }
                }
            }
        }
        .formStyle(.grouped)
    }

    func pickFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        p.prompt = "Proibir"; p.directoryURL = URL(fileURLWithPath: store.agents[index].cwd)
        guard p.runModal() == .OK else { return }
        for u in p.urls where !store.agents[index].blocked.contains(u.path) { store.agents[index].blocked.append(u.path) }
    }
}

// MARK: - Ajustes

struct SettingsPane: View {
    @AppStorage("orangeAt") var orangeAt = 50.0
    @AppStorage("redAt") var redAt = 80.0
    @AppStorage("barStyle") var barStyle = BarStyle.both.rawValue
    @AppStorage("notifyDone") var notifyDone = true
    @AppStorage("notifyPermission") var notifyPermission = true
    @AppStorage("widget") var widget = true
    @State private var login = Login.enabled

    var body: some View {
        Form {
            SwiftUI.Section("Cores") {
                Stepper(value: $orangeAt, in: 10...(redAt - 5), step: 5) {
                    LabeledContent("Laranja a partir de") { Text("\(Int(orangeAt))%").monospacedDigit().foregroundStyle(.orange) }
                }
                Stepper(value: $redAt, in: (orangeAt + 5)...100, step: 5) {
                    LabeledContent("Vermelho a partir de") { Text("\(Int(redAt))%").monospacedDigit().foregroundStyle(.red) }
                }
            }
            SwiftUI.Section("Barra de menus") {
                Picker("Mostrar", selection: $barStyle) {
                    Text("Sessão e semana").tag(BarStyle.both.rawValue)
                    Text("Só a sessão").tag(BarStyle.session.rawValue)
                    Text("Só o ✳").tag(BarStyle.icon.rawValue)
                }
            }
            SwiftUI.Section("Notificações") {
                Toggle("Quando uma sessão termina", isOn: $notifyDone)
                Toggle("Quando uma sessão pede permissão", isOn: $notifyPermission)
            }
            SwiftUI.Section {
                Toggle("Abrir ao iniciar o Mac", isOn: $login).onChange(of: login) { v in Login.set(v) }
                Toggle("Widget do iPhone", isOn: $widget)
            } header: {
                Text("Geral")
            } footer: {
                Text("O widget lê os números pelo iCloud Drive, no app Scriptable.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
    }
}
