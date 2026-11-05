// The menu bar item: a slider with one stop for each preset, the Dark Mode item, and the setup commands.
// When you release the slider, the menu closes and the screen changes to that size.

import AppKit
import ServiceManagement
import SwiftUI

/// A slider cell that reports when the mouse button goes up.
final class ReleaseSliderCell: NSSliderCell {
    var onRelease: (() -> Void)?

    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
        if flag { onRelease?() }
    }
}

/// Larger, darker dots on top of the tick marks of a slider. The standard tick marks are small and very light.
/// This view goes above the slider and has the same frame. It does not get mouse events.
/// The new slider of macOS 26 and later does not call drawTickMarks, and rectOfTickMark gives the old positions.
/// Thus this view puts each dot below the center of the knob at that stop, where macOS draws its tick mark.
/// The positions were measured on macOS 27. Older macOS versions keep the standard tick marks.
final class TickDotsView: NSView {
    weak var slider: NSSlider?

    init(slider: NSSlider) {
        self.slider = slider
        super.init(frame: slider.frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let slider, let cell = slider.cell as? NSSliderCell, slider.numberOfTickMarks > 1 else { return }
        (slider.isEnabled ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setFill()
        let diameter: CGFloat = 4
        let gap: CGFloat = 4  // From the bottom of the track to the center of a dot.
        let bar = cell.barRect(flipped: slider.isFlipped)
        let knob = cell.knobRect(flipped: slider.isFlipped).width
        let step = (bar.width - knob) / CGFloat(slider.numberOfTickMarks - 1)
        let y = slider.isFlipped ? bar.maxY + gap : bar.minY - gap
        // The knob covers the dot at its stop, as with the standard tick marks.
        let knobStop = Int(slider.doubleValue.rounded())
        for index in 0..<slider.numberOfTickMarks where index != knobStop {
            let center = convert(NSPoint(x: bar.minX + knob / 2 + step * CGFloat(index), y: y), from: slider)
            NSBezierPath(ovalIn: NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)).fill()
        }
    }
}

/// The slider stops: the presets that macOS has now, or else the HiDPI sizes with the full screen shape.
func sliderPresets(_ display: CGDirectDisplayID) -> [Preset] {
    let available = Display.hiDPISizes(display)
    let presets = (Config.readPresets() ?? []).filter { available.contains($0.size) }
    if !presets.isEmpty { return presets.sorted { $0.size < $1.size } }
    guard let native = Display.nativePixels(display) else { return [] }
    return Config.fullShape(available, native: native).map { Preset(name: "\($0.width)", size: $0, note: "") }
}

/// The preset that matches the current size, or else the nearest one by width.
func currentIndex(_ presets: [Preset], _ display: CGDirectDisplayID) -> Int? {
    guard let current = Display.currentSize(display), !presets.isEmpty else { return nil }
    if let exact = presets.firstIndex(where: { $0.size == current }) { return exact }
    return presets.indices.min { abs(presets[$0].size.width - current.width) < abs(presets[$1].size.width - current.width) }
}

final class MenuController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let menuWidth: CGFloat = 300
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let sliderItem = NSMenuItem()
    let darkModeItem = NSMenuItem()
    let removeItem = NSMenuItem(title: "Remove Custom Sizes…", action: #selector(removeCustomSizes), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
    var slider = NSSlider()
    var tickDots: TickDotsView?
    var valueLabel = NSTextField(labelWithString: "")
    var presets: [Preset] = []
    var appliedIndex: Int?
    var pending: Preset?
    var setupWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Display Size")

        let setupItem = NSMenuItem(title: "Set Up Custom Sizes…", action: #selector(openSetup), keyEquivalent: "")
        for item in [setupItem, removeItem, loginItem] { item.target = self }
        menu.addItem(sliderItem)
        menu.addItem(.separator())
        if Appearance.isAvailable {
            menu.addItem(darkModeItem)
            menu.addItem(.separator())
        }
        menu.addItem(setupItem)
        menu.addItem(removeItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit Display Scale", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        if let step = SetupModel.launchStep() { showSetup(step) }
    }

    // MARK: Slider

    func makeSliderView() -> NSView {
        let width = Self.menuWidth
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 92))

        let title = NSTextField(labelWithString: "Display Size")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        title.frame = NSRect(x: 16, y: 66, width: width - 32, height: 18)
        view.addSubview(title)

        slider = NSSlider()
        let cell = ReleaseSliderCell()
        cell.onRelease = { [weak self] in self?.sliderReleased() }
        slider.cell = cell
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isContinuous = true
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.frame = NSRect(x: 14, y: 36, width: width - 28, height: 26)
        view.addSubview(slider)
        if #available(macOS 26, *) {
            let dots = TickDotsView(slider: slider)
            view.addSubview(dots)
            tickDots = dots
        }
        

        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let left = NSTextField(labelWithString: "Larger text")
        left.font = small
        left.textColor = .secondaryLabelColor
        left.frame = NSRect(x: 16, y: 20, width: 120, height: 14)
        view.addSubview(left)
        let right = NSTextField(labelWithString: "More space")
        right.font = small
        right.textColor = .secondaryLabelColor
        right.alignment = .right
        right.frame = NSRect(x: width - 136, y: 20, width: 120, height: 14)
        view.addSubview(right)

        valueLabel = NSTextField(labelWithString: "")
        valueLabel.alignment = .center
        valueLabel.frame = NSRect(x: 16, y: 2, width: width - 32, height: 16)
        view.addSubview(valueLabel)
        return view
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // A new slider each time, so no state from the last drag or display change stays.
        sliderItem.view = makeSliderView()
        darkModeItem.view = DarkModeView(width: Self.menuWidth)
        let display = Display.builtin
        presets = display.map(sliderPresets) ?? []
        appliedIndex = display.flatMap { currentIndex(presets, $0) }
        slider.isEnabled = presets.count > 1
        slider.minValue = 0
        slider.maxValue = Double(max(presets.count - 1, 1))
        slider.numberOfTickMarks = max(presets.count, 2)
        slider.doubleValue = Double(appliedIndex ?? 0)
        updateLabel()
        removeItem.isEnabled = display.map(Override.exists(for:)) ?? false
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func updateLabel() {
        let index = Int(slider.doubleValue.rounded())
        if Display.builtin == nil {
            valueLabel.stringValue = "The built-in display is off"
        } else {
            valueLabel.stringValue = presets.indices.contains(index) ? presets[index].label : "No sizes found"
        }
    }

    @objc func sliderMoved() {
        updateLabel()
        tickDots?.needsDisplay = true
    }

    func sliderReleased() {
        let index = Int(slider.doubleValue.rounded())
        guard presets.indices.contains(index), index != appliedIndex else { return }
        pending = presets[index]
        // Close the menu after the slider's drag loop ends, not inside it.
        DispatchQueue.main.async { [menu] in menu.cancelTracking() }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard let preset = pending, let display = Display.builtin else { return }
        pending = nil
        // Change the display after the menu is closed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !Display.set(preset.size, on: display) { NSSound.beep() }
        }
    }

    // MARK: Setup

    func showSetup(_ step: SetupModel.Step) {
        let model = SetupModel(step: step)
        model.onClose = { [weak self] in self?.setupWindow?.close() }
        model.onFront = { [weak self] in self?.setupWindow?.makeKeyAndOrderFront(nil) }
        let host = NSHostingController(rootView: SetupView(model: model))
        host.sizingOptions = [.preferredContentSize]
        let window = setupWindow ?? NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Display Scale Setup"
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.center()
        setupWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func openSetup() { showSetup(SetupModel.menuStep()) }

    @objc func removeCustomSizes() {
        let alert = NSAlert()
        alert.messageText = "Remove the custom sizes?"
        alert.informativeText = "macOS asks for your password. After a restart, only the standard sizes are available."
        alert.addButton(withTitle: "Remove…")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let model = SetupModel(step: .choose)
        model.removeSizes()
        if case .restart = model.step { showSetup(model.step) } else if let error = model.error { showError(error) }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Display Scale"
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
