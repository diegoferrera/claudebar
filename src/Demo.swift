import Cocoa

// Modo demonstração (CLAUDEBAR_DEMO=1): dados de exemplo para os prints do README.
// Não lê nem grava nada em ~/.claude, não consulta a API e não envia notificações.
//   CLAUDEBAR_PANE=overview|sessions|agents|settings  abre o painel nesse ponto
//   CLAUDEBAR_MENU=1                                   abre o menu da barra
//   CLAUDEBAR_SHOT=<arquivo>                           grava ali o número da janela, para o screencapture -l

let demo = ProcessInfo.processInfo.environment["CLAUDEBAR_DEMO"] != nil

enum Demo {
    static let root = "/Users/voce/projetos"

    static func fill(_ store: Store) {
        let now = Date()
        store.session = Limit(pct: 42, reset: now.addingTimeInterval(2 * 3600 + 10 * 60))
        store.week = Limit(pct: 63, reset: now.addingTimeInterval(3 * 86400 + 5 * 3600))
        store.updated = now
        func s(_ id: String, _ dir: String, _ state: SessState, _ prompt: String, _ msg: String = "", _ min: Double) -> Sess {
            Sess(id: id, file: URL(fileURLWithPath: "/dev/null"), cwd: "\(root)/\(dir)", terminal: id, state: state,
                 message: msg, prompt: prompt, since: now.addingTimeInterval(-min * 60))
        }
        store.sessions = [
            s("t1", "loja", .waiting, "Rodar os testes de checkout", "Claude needs your permission to use Bash", 2),
            s("t2", "loja", .working, "Ajustar o layout da página de preços", "", 6),
            s("t3", "api", .working, "Criar a rota de cupons com validação", "", 14),
            s("t4", "docs", .idle, "Revisar o guia de instalação", "", 25),
            s("t5", "app-ios", .idle, "Corrigir o crash ao abrir a câmera", "", 70),
        ]
        store.agents = [
            Agent(id: "a1", name: "Front-end", terminal: "t2", cwd: "\(root)/loja",
                  blocked: ["\(root)/loja/pagamentos"], note: "Use as cores do guia de marca novo."),
            Agent(id: "a2", name: "Testes", terminal: "t1", cwd: "\(root)/loja"),
            Agent(id: "a3", name: "Back-end", terminal: "t3", cwd: "\(root)/api", blocked: ["\(root)/api/producao"]),
            Agent(id: "a4", name: "Documentação", terminal: "t4", cwd: "\(root)/docs"),
        ]
        // dois dias de uso: a sessão sobe em janelas de 5 h e zera no reset; a semana sobe devagar
        var h: [Sample] = []
        let reset = store.session!.reset!.timeIntervalSince1970
        for i in stride(from: 2 * 24 * 6, through: 1, by: -1) {
            let t = now.timeIntervalSince1970 - Double(i) * 600
            let hour = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: t))
            let phase = 1 - ((reset - t) / (5 * 3600)).truncatingRemainder(dividingBy: 1)
            let busy = (8...23).contains(hour) ? 74.0 : 8.0
            h.append(Sample(t: t, s: (phase * busy).rounded(), w: (63 - Double(i) / 288 * 9).rounded()))
        }
        h.append(Sample(t: now.timeIntervalSince1970, s: 42, w: 63))
        store.history = h
    }

    static func shoot(_ app: App) {
        let env = ProcessInfo.processInfo.environment
        if let p = env["CLAUDEBAR_PANE"] {
            app.nav.pane = Pane.allCases.first { "\($0)" == p } ?? .overview
            if app.nav.pane == .agents { app.nav.agentId = "a1" }
            app.openPanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { record(app.window?.windowNumber) }
        } else if env["CLAUDEBAR_MENU"] != nil {
            // o menu prende o run loop em modo de rastreamento: o timer precisa rodar em .common
            let t = Timer(timeInterval: 1.5, repeats: false) { _ in
                record(NSApp.windows.filter { $0.isVisible && $0.frame.height > 200 }.map(\.windowNumber).first)
            }
            RunLoop.main.add(t, forMode: .common)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { app.item.button?.performClick(nil) }
        }
    }

    static func record(_ n: Int?) {
        guard let f = ProcessInfo.processInfo.environment["CLAUDEBAR_SHOT"], let n = n else { return }
        try? "\(n)".write(toFile: f, atomically: true, encoding: .utf8)
    }
}
