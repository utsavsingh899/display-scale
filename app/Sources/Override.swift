// The display override file that adds the custom sizes to macOS. macOS reads it at startup.
//   /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<hex>/DisplayProductID-<hex>
// Each size gets two "scale-resolutions" entries at 2x pixels: one plain, and one with the HiDPI flags.
// The 'displaymode override' command makes the same file.

import AppKit

enum Override {
    struct Cancelled: Error {}

    struct Failed: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func path(for display: CGDirectDisplayID) -> String {
        let vendor = String(Display.vendorID(display), radix: 16)
        let product = String(Display.productID(display), radix: 16)
        return "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-\(vendor)/DisplayProductID-\(product)"
    }

    static func exists(for display: CGDirectDisplayID) -> Bool {
        FileManager.default.fileExists(atPath: path(for: display))
    }

    static func plist(sizes: [Size], display: CGDirectDisplayID) throws -> Data {
        func bigEndian(_ values: [UInt32]) -> Data {
            values.reduce(into: Data()) { data, value in withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        }
        var entries: [Data] = []
        for size in sizes {
            let doubled = [UInt32(size.width * 2), UInt32(size.height * 2)]
            entries.append(bigEndian(doubled))
            entries.append(bigEndian(doubled + [0x0000_0009, 0x0020_0000]))
        }
        let plist: [String: Any] = [
            "DisplayProductID": Int(Display.productID(display)),
            "DisplayVendorID": Int(Display.vendorID(display)),
            "scale-resolutions": entries,
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Write the override with these sizes. Any old override goes to the Trash.
    /// macOS asks for an administrator password.
    static func install(sizes: [Size], display: CGDirectDisplayID) throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("display-scale-override.plist")
        try plist(sizes: sizes, display: display).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let file = path(for: display)
        let folder = (file as NSString).deletingLastPathComponent
        try runAsAdmin("mkdir -p \(quote(folder)) && \(moveToTrash(file, reason: "old override"))"
            + " && install -o root -g wheel -m 0644 \(quote(temp.path)) \(quote(file))")
    }

    /// Move the override to the Trash. macOS asks for an administrator password.
    static func remove(for display: CGDirectDisplayID) throws {
        try runAsAdmin(moveToTrash(path(for: display), reason: "removed"))
    }

    private static func moveToTrash(_ file: String, reason: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd h.mm.ss a"
        let name = "\((file as NSString).lastPathComponent) (\(reason) \(formatter.string(from: Date())))"
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/\(name)").path
        return "if [ -e \(quote(file)) ]; then mv \(quote(file)) \(quote(trash)); fi"
    }

    private static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func runAsAdmin(_ command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        guard let error else { return }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { throw Cancelled() }
        throw Failed(message: error[NSAppleScript.errorMessage] as? String ?? "macOS did not run the command.")
    }
}

enum Restart {
    /// Ask macOS to restart. macOS shows its own confirmation. The result is false if the request failed.
    static func request() -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"loginwindow\" to «event aevtrrst»")?.executeAndReturnError(&error)
        return error == nil
    }

    /// The time of the last startup.
    static var bootTime: Date {
        var time = timeval()
        var size = MemoryLayout<timeval>.stride
        sysctlbyname("kern.boottime", &time, &size, nil, 0)
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec))
    }
}
