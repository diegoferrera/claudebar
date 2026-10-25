// Widget "Claude" para o Scriptable (iPhone).
// Lê claude-uso.json, que o ClaudeBar do Mac grava no iCloud a cada minuto.

const fm = FileManager.iCloud()
const path = fm.joinPath(fm.documentsDirectory(), "claude-uso.json")

async function load() {
  if (!fm.fileExists(path)) return null
  await fm.downloadFileFromiCloud(path)
  try { return JSON.parse(fm.readString(path)) } catch (e) { return null }
}

let orangeAt = 50, redAt = 80  // vêm dos Ajustes do ClaudeBar
const level = p => p >= redAt ? new Color("#FF453A") : p >= orangeAt ? new Color("#FF9F0A") : new Color("#30D158")
const hm = d => { const f = new DateFormatter(); f.dateFormat = "HH:mm"; return f.string(d) }
const weekday = d => { const f = new DateFormatter(); f.locale = "pt_BR"; f.dateFormat = "EEE HH:mm"; return f.string(d) }

// barra arredondada desenhada como imagem
function bar(pct, w, h) {
  const c = new DrawContext(); c.size = new Size(w, h); c.opaque = false; c.respectScreenScale = true
  const track = new Path(); track.addRoundedRect(new Rect(0, 0, w, h), h / 2, h / 2)
  c.addPath(track); c.setFillColor(new Color("#FFFFFF", 0.14)); c.fillPath()
  const fw = Math.max(h, w * Math.min(pct, 100) / 100)
  const fill = new Path(); fill.addRoundedRect(new Rect(0, 0, fw, h), h / 2, h / 2)
  c.addPath(fill); c.setFillColor(level(pct)); c.fillPath()
  return c.getImage()
}

function limitBlock(stack, title, l, sub, barW) {
  const top = stack.addStack(); top.centerAlignContent()
  const t = top.addText(title); t.font = Font.mediumSystemFont(12); t.textColor = new Color("#FFFFFF", 0.75)
  top.addSpacer()
  const v = top.addText(l ? `${Math.round(l.pct)}%` : "–")
  v.font = Font.boldRoundedSystemFont(17); v.textColor = l ? level(l.pct) : Color.gray()
  stack.addSpacer(4)
  stack.addImage(bar(l ? l.pct : 0, barW, 5)).imageSize = new Size(barW, 5)
  if (sub) {
    stack.addSpacer(3)
    const s = stack.addText(sub); s.font = Font.systemFont(10); s.textColor = new Color("#FFFFFF", 0.5)
  }
}

const data = await load()
if (data) { orangeAt = data.orangeAt ?? 50; redAt = data.redAt ?? 80 }
const family = config.widgetFamily || "medium"
const w = new ListWidget()
w.backgroundColor = new Color("#1C1C1E")
w.setPadding(14, 14, 14, 14)
w.refreshAfterDate = new Date(Date.now() + 5 * 60 * 1000)

const head = w.addStack(); head.centerAlignContent()
const star = head.addText("✳︎ Claude"); star.font = Font.semiboldSystemFont(13); star.textColor = new Color("#D97757")
head.addSpacer()
if (data) {
  const upd = head.addText(hm(new Date(data.updated * 1000)))
  upd.font = Font.systemFont(10); upd.textColor = new Color("#FFFFFF", 0.4)
}
w.addSpacer(10)

if (!data) {
  const m = w.addText("Abra o ClaudeBar no Mac com o iCloud Drive ligado.")
  m.font = Font.systemFont(12); m.textColor = new Color("#FFFFFF", 0.7)
} else {
  const s = data.session, k = data.week
  const barW = family === "small" ? 120 : 140
  const body = w.addStack()
  const left = body.addStack(); left.layoutVertically(); left.size = new Size(barW, 0)
  limitBlock(left, "Sessão", s, family === "small" ? null : (s && s.reset ? `Redefine ${hm(new Date(s.reset * 1000))}` : null), barW)
  left.addSpacer(10)
  limitBlock(left, "Semana", k, family === "small" ? null : (k && k.reset ? `Reinicia ${weekday(new Date(k.reset * 1000))}` : null), barW)

  if (family !== "small" && data.sessions) {
    body.addSpacer(16)
    const right = body.addStack(); right.layoutVertically()
    const st = right.addText("Sessões"); st.font = Font.mediumSystemFont(12); st.textColor = new Color("#FFFFFF", 0.75)
    right.addSpacer(6)
    const rows = [["hand.raised.fill", "#FF9F0A", data.sessions.waiting, "pedem permissão"],
                  ["ellipsis.circle.fill", "#0A84FF", data.sessions.working, "trabalhando"],
                  ["checkmark.circle.fill", "#30D158", data.sessions.idle, "paradas"]]
    for (const [sym, col, n, label] of rows) {
      const r = right.addStack(); r.centerAlignContent()
      const img = r.addImage(SFSymbol.named(sym).image); img.imageSize = new Size(12, 12); img.tintColor = new Color(col)
      r.addSpacer(5)
      const tx = r.addText(`${n} ${label}`); tx.font = Font.systemFont(11)
      tx.textColor = n > 0 ? Color.white() : new Color("#FFFFFF", 0.4)
      right.addSpacer(4)
    }
  }
}

if (config.runsInWidget) Script.setWidget(w)
else await w.presentMedium()
Script.complete()
