// Renders centred, multi-line headline text to a transparent PNG with Core Text,
// which shapes Thai marks correctly (Pillow here has no complex-text layout).
//   swift scripts/render-headline.swift <out.png> <width> <height> <font> <size> <line-gap> <text>
import AppKit

let a = CommandLine.arguments
guard a.count == 8, let w = Int(a[2]), let h = Int(a[3]), let size = Double(a[5]), let gap = Double(a[6]) else {
    FileHandle.standardError.write(Data("usage: out width height font size gap text\n".utf8)); exit(2)
}
let font = NSFont(name: a[4], size: size) ?? NSFont.boldSystemFont(ofSize: size)
let style = NSMutableParagraphStyle()
style.alignment = .center
style.lineSpacing = gap
let text = NSAttributedString(string: a[7], attributes: [
    .font: font,
    .foregroundColor: NSColor(srgbRed: 19 / 255, green: 19 / 255, blue: 23 / 255, alpha: 1),
    .paragraphStyle: style,
])
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let box = text.boundingRect(with: NSSize(width: Double(w), height: Double(h)), options: [.usesLineFragmentOrigin])
text.draw(with: NSRect(x: 0, y: Double(h) - box.height, width: Double(w), height: box.height), options: [.usesLineFragmentOrigin])
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[1]))
