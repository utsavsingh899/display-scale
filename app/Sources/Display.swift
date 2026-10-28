// The built-in display: its modes, sizes, and IDs, and how to change the mode.

import CoreGraphics

/// A size in points ("looks like"), for example 1800 x 1169.
struct Size: Hashable, Comparable, CustomStringConvertible {
    let width: Int
    let height: Int

    init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
    }

    /// Read a size such as "1800x1169".
    init?<S: StringProtocol>(text: S) {
        let parts = text.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        self.init(parts[0], parts[1])
    }

    var description: String { "\(width)x\(height)" }
    var display: String { "\(width) × \(height)" }

    static func < (a: Size, b: Size) -> Bool { (a.width, a.height) < (b.width, b.height) }
}

enum Display {
    static let nativeFlag: UInt32 = 0x0200_0000   // kDisplayModeNativeFlag
    static let defaultFlag: UInt32 = 0x0000_0004  // kDisplayModeDefaultFlag

    /// The built-in display, or nil when it is off (for example, when the lid is closed).
    static var builtin: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func modes(_ display: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
        return modes.filter { $0.isUsableForDesktopGUI() }
    }

    static func isHiDPI(_ mode: CGDisplayMode) -> Bool { mode.pixelWidth > mode.width }

    /// All HiDPI sizes, small to large.
    static func hiDPISizes(_ display: CGDirectDisplayID) -> [Size] {
        Set(modes(display).filter(isHiDPI).map { Size($0.width, $0.height) }).sorted()
    }

    static func currentSize(_ display: CGDirectDisplayID) -> Size? {
        CGDisplayCopyDisplayMode(display).map { Size($0.width, $0.height) }
    }

    /// The pixel size of the panel, for example 3024 x 1964.
    static func nativePixels(_ display: CGDirectDisplayID) -> Size? {
        let all = modes(display)
        let native = all.first { $0.ioFlags & nativeFlag != 0 }
            ?? all.filter { !isHiDPI($0) }.max { $0.pixelWidth < $1.pixelWidth }
        return native.map { Size($0.pixelWidth, $0.pixelHeight) }
    }

    /// The size that macOS calls "Default".
    static func defaultSize(_ display: CGDirectDisplayID) -> Size? {
        modes(display).first { $0.ioFlags & defaultFlag != 0 }.map { Size($0.width, $0.height) }
    }

    static func vendorID(_ display: CGDirectDisplayID) -> UInt32 { CGDisplayVendorNumber(display) }
    static func productID(_ display: CGDirectDisplayID) -> UInt32 { CGDisplayModelNumber(display) }

    /// Change to the HiDPI mode of this size. Keep the current refresh rate when possible.
    /// The change stays after a restart.
    @discardableResult
    static func set(_ size: Size, on display: CGDirectDisplayID) -> Bool {
        let current = CGDisplayCopyDisplayMode(display)
        let matches = modes(display).filter { $0.width == size.width && $0.height == size.height && isHiDPI($0) }
        guard let mode = matches.first(where: { $0.refreshRate == current?.refreshRate })
            ?? matches.max(by: { $0.refreshRate < $1.refreshRate }) else { return false }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        guard CGCompleteDisplayConfiguration(config, .permanently) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return true
    }
}
