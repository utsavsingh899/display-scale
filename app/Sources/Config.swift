// The files that Display Scale and the 'res' command share, in ~/.config/res
// (or in $RES_CONFIG_DIR, for tests):
//   stock     the HiDPI sizes that macOS had before any override, one size for each line
//   presets   the slider stops, one for each line: name, size, note

import Foundation

struct Preset {
    let name: String
    let size: Size
    let note: String

    var label: String { note.isEmpty ? size.display : "\(note)  ·  \(size.display)" }
}

enum Config {
    /// The HiDPI pixel width limit of base Apple silicon chips (M1 to M5).
    static let maxPixelWidth = 6144

    static var folder: URL {
        if let custom = ProcessInfo.processInfo.environment["RES_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/res", isDirectory: true)
    }

    static var stockFile: URL { folder.appendingPathComponent("stock") }
    static var presetsFile: URL { folder.appendingPathComponent("presets") }

    // MARK: Files

    static func readStock() -> [Size]? {
        guard let text = try? String(contentsOf: stockFile, encoding: .utf8) else { return nil }
        let sizes = text.split(whereSeparator: \.isNewline).compactMap { Size(text: $0.trimmingCharacters(in: .whitespaces)) }
        return sizes.isEmpty ? nil : sizes
    }

    static func writeStock(_ sizes: [Size]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try (sizes.map(\.description).joined(separator: "\n") + "\n").write(to: stockFile, atomically: true, encoding: .utf8)
    }

    static func readPresets() -> [Preset]? {
        guard let text = try? String(contentsOf: presetsFile, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, let size = Size(text: fields[1]) else { return nil }
            return Preset(name: String(fields[0]), size: size, note: fields.dropFirst(2).joined(separator: " "))
        }
    }

    /// The presets file text, in the same columns that 'res setup' writes.
    static func presetsText(_ presets: [Preset]) -> String {
        func pad(_ text: String, _ width: Int) -> String { text.padding(toLength: max(width, text.count), withPad: " ", startingAt: 0) }
        var text = "# name   size       note   (edit this file to rename or remove presets)\n"
        for preset in presets {
            text += pad(preset.name, 8) + " " + pad(preset.size.description, 10) + " " + preset.note + "\n"
        }
        return text
    }

    static func writePresets(_ presets: [Preset]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try presetsText(presets).write(to: presetsFile, atomically: true, encoding: .utf8)
    }

    // MARK: Sizes

    /// The stock sizes with the same shape as the native pixels, small to large.
    /// This leaves out the sizes that fit below the notch.
    static func fullShape(_ sizes: [Size], native: Size) -> [Size] {
        sizes.filter { abs($0.width * native.height - $0.height * native.width) * 100 < $0.height * native.height }.sorted()
    }

    /// The largest standard size, which macOS calls "More Space".
    static func moreSpace(_ stock: [Size], native: Size) -> Size? { fullShape(stock, native: native).last }

    /// The size for a custom width, with the same shape as the screen.
    static func customSize(width: Int, native: Size) -> Size { Size(width, width * native.height / native.width) }

    /// The text size at this size, compared with More Space, in percent.
    static func percent(_ size: Size, moreSpace: Size) -> Int { (moreSpace.width * 100 + size.width / 2) / size.width }

    /// Two widths that give text at about 88% and 82% of More Space.
    static func suggestedWidths(moreSpace: Size) -> [Int] {
        [88, 82].map { (moreSpace.width * 100 / $0 + 4) / 8 * 8 }
    }

    /// The problem with a custom width, or nil when the width is valid.
    static func problem(width: Int, moreSpace: Size) -> String? {
        if width <= moreSpace.width { return "Use a width above \(moreSpace.width)." }
        if width * 2 > maxPixelWidth { return "Use a width of \(maxPixelWidth / 2) or less." }
        return nil
    }

    /// The presets: the standard sizes with the full screen shape, then the custom sizes.
    static func makePresets(stock: [Size], native: Size, defaultSize: Size?, custom: [Size]) -> [Preset] {
        let full = fullShape(stock, native: native)
        guard let more = full.last else { return [] }
        let standard = full.enumerated().map { index, size -> Preset in
            if index == full.count - 1 { return Preset(name: "more", size: size, note: "More Space") }
            if size == defaultSize { return Preset(name: "default", size: size, note: "Default") }
            if index == 0 { return Preset(name: "larger", size: size, note: "Larger Text") }
            return Preset(name: "\(size.width)", size: size, note: "")
        }
        let added = custom.map {
            Preset(name: "\($0.width)", size: $0, note: "\(percent($0, moreSpace: more))% of More Space")
        }
        return standard + added
    }

    /// The preset sizes that are not stock sizes.
    static func customSizes(_ presets: [Preset], stock: [Size]) -> [Size] {
        let standard = Set(stock)
        return presets.map(\.size).filter { !standard.contains($0) }
    }
}
