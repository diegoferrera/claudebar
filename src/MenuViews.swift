import SwiftUI

// Menu do ✳ no estilo dos menus de Bateria / Wi-Fi: título, seções com cabeçalho cinza, linhas com ícone em círculo
let menuWidth: CGFloat = 300

struct Section<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ c: () -> Content) { content = c() }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .frame(width: menuWidth, alignment: .leading)
    }
}

struct SectionTitle: View {
    let text: String; var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            if let t = trailing { Text(t).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(.bottom, 6)
    }
}

// círculo como o dos itens de Wi-Fi; com `progress` vira um anel de uso
struct Badge: View {
    let symbol: String; var progress: Double? = nil; var color: Color = .secondary
    var body: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.1))
            if let p = progress {
                Circle().trim(from: 0, to: max(0.02, min(p, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.25)
            }
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(progress == nil ? Color.primary.opacity(0.8) : color)
        }
        .frame(width: 28, height: 28)
    }
}

struct Row: View {
    let badge: Badge; let title: String; var subtitle: String? = nil
    let value: String; var valueColor: Color = .secondary
    var body: some View {
        HStack(spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13)).lineLimit(1)
                if let s = subtitle { Text(s).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13, weight: valueColor == .secondary ? .regular : .semibold).monospacedDigit())
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, 4)
    }
}

func limitRow(_ title: String, _ symbol: String, _ l: Limit?, _ sub: String) -> Row {
    let c = Color(nsColor: l == nil ? .tertiaryLabelColor : levelColor(l!.pct))
    return Row(badge: Badge(symbol: symbol, progress: (l?.pct ?? 0) / 100, color: c), title: title, subtitle: sub,
               value: l.map { "\(Int($0.pct.rounded()))%" } ?? "–", valueColor: c)
}

// aparência de cada estado de sessão (usada no menu e no painel)
func stateLook(_ s: Sess) -> (symbol: String, color: Color, text: String) {
    switch s.state {
    case .waiting: return ("hand.raised.fill", .orange, "Pede permissão \(ago(s.since))")
    case .working: return ("ellipsis", .blue, "Trabalhando \(ago(s.since).replacingOccurrences(of: "há ", with: ""))")
    case .idle:    return ("checkmark", .green, "Terminou \(ago(s.since))")
    }
}

struct StateDot: View {
    let s: Sess; var size: CGFloat = 28
    var body: some View {
        let l = stateLook(s)
        ZStack {
            Circle().fill(s.state == .idle ? Color.primary.opacity(0.1) : l.color.opacity(0.9))
            Image(systemName: l.symbol).font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(s.state == .idle ? l.color : .white)
        }
        .frame(width: size, height: size)
    }
}

struct SessionRow: View {
    let s: Sess; let name: String; let open: () -> Void
    @State private var hover = false
    var body: some View {
        let l = stateLook(s)
        HStack(spacing: 10) {
            StateDot(s: s)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13)).lineLimit(1)
                Text(l.text + (s.state == .working && !s.prompt.isEmpty ? ": \(s.prompt)" : ""))
                    .font(.system(size: 11)).foregroundStyle(s.state == .waiting ? Color.orange : .secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3).padding(.horizontal, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.08) : .clear))
        .padding(.horizontal, -5)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: open)
        .help(s.prompt.isEmpty ? "Abrir o Maestri" : s.prompt)
    }
}

func hosted<V: View>(_ v: V) -> NSMenuItem {
    let h = NSHostingView(rootView: v); h.frame = NSRect(origin: .zero, size: h.fittingSize)
    let i = NSMenuItem(); i.view = h; return i
}
