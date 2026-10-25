import Cocoa
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
// formato padrão de ícone do macOS: quadrado arredondado com margem
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.set()
NSColor.black.setFill(); path.fill()
NSGraphicsContext.restoreGraphicsState()
path.addClip()
NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.23, alpha: 1),
           ending: NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1))!.draw(in: body, angle: -90)
let c = CGPoint(x: S/2, y: S/2)
// trilho do anel
ctx.setLineCap(.round); ctx.setLineWidth(58)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
ctx.addArc(center: c, radius: 290, startAngle: 0, endAngle: .pi * 2, clockwise: false); ctx.strokePath()
// anel de uso (verde → laranja), começando no topo
let start = CGFloat.pi / 2, end = start - .pi * 2 * 0.68
ctx.saveGState()
ctx.addArc(center: c, radius: 290, startAngle: start, endAngle: end, clockwise: true)
ctx.replacePathWithStrokedPath(); ctx.clip()
let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: [NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1).cgColor,
                            NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.04, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: S/2, y: 820), end: CGPoint(x: S/2, y: 200), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()
// ✳ do Claude no centro: 6 raios arredondados
ctx.setStrokeColor(NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1).cgColor)
ctx.setLineWidth(46); ctx.setLineCap(.round)
for i in 0..<6 {
    let a = CGFloat(i) * .pi / 3 + .pi / 2
    ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x + cos(a) * 150, y: c.y + sin(a) * 150))
}
ctx.strokePath()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
