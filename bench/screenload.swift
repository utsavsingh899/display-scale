// screenload: cover the built-in screen with moving content for some seconds.
// It stands in for video playback or a scroll: the screen changes on every frame.
// The content is drawn at the backing (2x) scale, like a real app.
//
//   screenload <seconds>
//
// Build: swiftc -O screenload.swift -o screenload

import AppKit
import QuartzCore

let seconds = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 20

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let builtin = NSScreen.screens.first { screen in
    let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    return id.map { CGDisplayIsBuiltin($0) != 0 } ?? false
} ?? NSScreen.main!
let frame = builtin.frame
let scale = builtin.backingScaleFactor

// Content that is two screens high: colored blocks and lines of text.
let pixelWidth = Int(frame.width * scale), pixelHeight = Int(frame.height * 2 * scale)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: frame.width, height: frame.height * 2)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let block: CGFloat = 40
for row in 0..<Int(frame.height * 2 / block) {
    for column in 0..<Int(frame.width / block) {
        NSColor(hue: CGFloat((row * 7 + column * 3) % 36) / 36, saturation: 0.5, brightness: 0.9, alpha: 1).setFill()
        NSRect(x: CGFloat(column) * block, y: CGFloat(row) * block, width: block, height: block).fill()
    }
    let text = "Line \(row): The quick brown fox jumps over the lazy dog. 0123456789" as NSString
    text.draw(at: NSPoint(x: 8, y: CGFloat(row) * block + 12), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
}
NSGraphicsContext.restoreGraphicsState()

let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false, screen: builtin)
window.level = .screenSaver
window.isOpaque = true
let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
content.wantsLayer = true
window.contentView = content

let layer = CALayer()
layer.frame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height * 2)
layer.contents = bitmap.cgImage
layer.contentsScale = scale
content.layer!.addSublayer(layer)

// Move the content up by one screen height every 2 seconds, without end.
let move = CABasicAnimation(keyPath: "position.y")
move.fromValue = frame.height
move.toValue = 0
move.duration = 2
move.repeatCount = .infinity
layer.add(move, forKey: "move")

window.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
app.run()
