// Dark Mode: read and change the system appearance, and the Dark Mode item in the menu.
// macOS has no public function that changes the appearance. Display Scale uses two private
// SkyLight functions. A future macOS can remove them. Then the menu shows no Dark Mode item.

import AppKit

enum Appearance {
    private typealias GetTheme = @convention(c) () -> Bool
    private typealias SetTheme = @convention(c) (Bool) -> Void

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let getTheme = skyLight.flatMap { dlsym($0, "SLSGetAppearanceThemeLegacy") }.map { unsafeBitCast($0, to: GetTheme.self) }
    private static let setTheme = skyLight.flatMap { dlsym($0, "SLSSetAppearanceThemeLegacy") }.map { unsafeBitCast($0, to: SetTheme.self) }

    /// True when this macOS has the two functions.
    static var isAvailable: Bool { getTheme != nil && setTheme != nil }

    /// True when the system appearance is Dark.
    static var isDark: Bool { getTheme?() ?? false }

    /// Change the system appearance for all apps. The change stays after a restart.
    static func setDark(_ dark: Bool) { setTheme?(dark) }
}

/// A circle that the accent color fills when it is on, and a light gray fills when it is off.
private final class CircleView: NSView {
    var isOn = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    // AppKit calls this again when the appearance changes, so the colors follow the menu.
    override func updateLayer() {
        layer?.cornerRadius = bounds.width / 2
        layer?.backgroundColor = (isOn ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.12)).cgColor
    }
}

/// The Dark Mode item: a round button and a title, as in the Display menu of Control Center.
/// A click anywhere on the item changes the mode. The menu stays open.
final class DarkModeView: NSView {
    private let circle = CircleView()
    private let icon = NSImageView()

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 40))

        circle.frame = NSRect(x: 14, y: 6, width: 28, height: 28)
        icon.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        icon.frame = circle.bounds
        circle.addSubview(icon)
        addSubview(circle)

        let title = NSTextField(labelWithString: "Dark Mode")
        title.frame = NSRect(x: 52, y: 12, width: width - 68, height: 16)
        addSubview(title)

        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel("Dark Mode")
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Show the mode that macOS has now.
    func refresh() { show(dark: Appearance.isDark) }

    func show(dark: Bool) {
        circle.isOn = dark
        icon.contentTintColor = dark ? .white : .labelColor
        setAccessibilityValue(dark)
    }

    func toggle() {
        Appearance.setDark(!Appearance.isDark)
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { toggle() }
    }

    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }

    // macOS can apply the change a short time after the call. Show it when the appearance changes.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }
}
