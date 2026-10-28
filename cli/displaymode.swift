// displaymode: read and set the resolution of the built-in display (Apple silicon Macs).
// 'res' (~/.local/bin/res) is the command to use. 'res' calls this tool.
//
//   displaymode list              all modes, one for each line, with tab-separated fields:
//                                 current (* or -), size, HiDPI or LoDPI, pixels, refresh rate
//   displaymode current           show the current mode
//   displaymode info              vendor ID, product ID (hex), native pixels, default size
//   displaymode set 1800x1169     change to the HiDPI mode of that size (kept after a restart)
//   displaymode set 1800x1169 lo  change to the low-DPI mode of that size
//   displaymode override 2048x1330 ...
//                                 print a display override plist that adds these HiDPI sizes
//
// Build: swiftc -O -target arm64-apple-macos11 displaymode.swift -o displaymode

import CoreGraphics
import Foundation

let nativeFlag: UInt32 = 0x0200_0000   // kDisplayModeNativeFlag
let defaultFlag: UInt32 = 0x0000_0004  // kDisplayModeDefaultFlag

func builtinDisplay() -> CGDirectDisplayID {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return ids.first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
}

func allModes(_ display: CGDirectDisplayID) -> [CGDisplayMode] {
    let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
    return modes.filter { $0.isUsableForDesktopGUI() }
}

func isHiDPI(_ mode: CGDisplayMode) -> Bool { mode.pixelWidth > mode.width }
func dpi(_ mode: CGDisplayMode) -> String { isHiDPI(mode) ? "HiDPI" : "LoDPI" }
func size(_ mode: CGDisplayMode) -> String { "\(mode.width)x\(mode.height)" }
func pixels(_ mode: CGDisplayMode) -> String { "\(mode.pixelWidth)x\(mode.pixelHeight)" }
func rate(_ mode: CGDisplayMode) -> String { mode.refreshRate > 0 ? "\(Int(mode.refreshRate.rounded()))Hz" : "-" }

func describe(_ mode: CGDisplayMode) -> String {
    "\(size(mode)) \(dpi(mode)) (pixels \(pixels(mode))) @ \(rate(mode))"
}

func parseSize(_ text: String) -> [Int]? {
    let wh = text.lowercased().split(separator: "x").compactMap { Int($0) }
    return wh.count == 2 && wh.allSatisfy { $0 > 0 } ? wh : nil
}

func bigEndian(_ values: [UInt32]) -> Data {
    values.reduce(into: Data()) { data, value in withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let usage = "usage: displaymode list | current | info | set <width>x<height> [lo] | override <width>x<height> ..."
let display = builtinDisplay()
let current = CGDisplayCopyDisplayMode(display)
let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "list":
    // Sort by size, HiDPI before LoDPI, and the highest refresh rate first.
    let key = { (m: CGDisplayMode) in (m.width, m.height, isHiDPI(m) ? 0 : 1, -m.refreshRate) }
    var seen = Set<String>()
    for mode in allModes(display).sorted(by: { key($0) < key($1) })
    where seen.insert("\(size(mode)) \(dpi(mode))").inserted {
        let isCurrent = current.map { size($0) == size(mode) && isHiDPI($0) == isHiDPI(mode) } ?? false
        print([isCurrent ? "*" : "-", size(mode), dpi(mode), pixels(mode), rate(mode)].joined(separator: "\t"))
    }

case "current":
    guard let current else { fail("Cannot read the current display mode.") }
    print(describe(current))

case "info":
    let modes = allModes(display)
    let native = modes.first { $0.ioFlags & nativeFlag != 0 }
        ?? modes.filter { !isHiDPI($0) }.max { $0.pixelWidth < $1.pixelWidth }
    let standard = modes.first { $0.ioFlags & defaultFlag != 0 }
    print(String(CGDisplayVendorNumber(display), radix: 16), String(CGDisplayModelNumber(display), radix: 16),
          native.map(pixels) ?? "-", standard.map(size) ?? "-")

case "set":
    guard args.count >= 2, args.count <= 3, let wh = parseSize(args[1]) else { fail(usage) }
    let kind = args.count == 3 ? args[2].lowercased() : "hi"
    guard ["hi", "lo"].contains(kind) else { fail(usage) }
    let hidpi = kind == "hi"
    let matches = allModes(display).filter { $0.width == wh[0] && $0.height == wh[1] && isHiDPI($0) == hidpi }
    // Keep the current refresh rate when possible, else use the highest one.
    guard let mode = matches.first(where: { $0.refreshRate == current?.refreshRate })
        ?? matches.max(by: { $0.refreshRate < $1.refreshRate })
    else { fail("No \(hidpi ? "HiDPI" : "LoDPI") mode \(wh[0])x\(wh[1]) on this display. Run 'res list'.") }

    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { fail("Cannot start the display change.") }
    CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
    guard CGCompleteDisplayConfiguration(config, .permanently) == .success else {
        CGCancelDisplayConfiguration(config)
        fail("macOS did not accept \(describe(mode)).")
    }
    print("Display set to \(describe(mode))")

case "override":
    // Each size gets two entries at 2x pixels: one plain, and one with the HiDPI flags.
    var entries: [Data] = []
    for arg in args.dropFirst() {
        guard let wh = parseSize(arg) else { fail(usage) }
        let doubled = [UInt32(wh[0] * 2), UInt32(wh[1] * 2)]
        entries.append(bigEndian(doubled))
        entries.append(bigEndian(doubled + [0x0000_0009, 0x0020_0000]))
    }
    guard !entries.isEmpty else { fail(usage) }
    let plist: [String: Any] = [
        "DisplayProductID": Int(CGDisplayModelNumber(display)),
        "DisplayVendorID": Int(CGDisplayVendorNumber(display)),
        "scale-resolutions": entries,
    ]
    let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    FileHandle.standardOutput.write(data)

default:
    fail(usage)
}
