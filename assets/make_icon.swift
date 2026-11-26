import AppKit
let s: CGFloat = 1024
let img = NSImage(size: NSSize(width: s, height: s))
img.lockFocus()
let r = NSRect(x: 100, y: 100, width: 824, height: 824)
NSColor(srgbRed: 0x14/255, green: 0x9f/255, blue: 0x8a/255, alpha: 1).setFill()
NSBezierPath(roundedRect: r, xRadius: 185, yRadius: 185).fill()
let p = NSBezierPath(); p.lineWidth = 62; p.lineCapStyle = .round; p.lineJoinStyle = .round
p.move(to: NSPoint(x: 512, y: 700)); p.line(to: NSPoint(x: 512, y: 380))
p.move(to: NSPoint(x: 370, y: 515)); p.line(to: NSPoint(x: 512, y: 372)); p.line(to: NSPoint(x: 654, y: 515))
p.move(to: NSPoint(x: 352, y: 300)); p.line(to: NSPoint(x: 672, y: 300))
NSColor.white.setStroke(); p.stroke()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
