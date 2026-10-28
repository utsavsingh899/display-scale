// Display Scale: a menu bar slider for the scaled resolution of the built-in display,
// with a setup window that adds custom sizes above More Space.
//
// Test options. They print and quit, and they do not change the display or any file:
//   DisplayScale --presets            the slider stops ("*" marks the current one)
//   DisplayScale --plan <width> ...   the presets file and the override plist that the setup makes
//
// Build: ./build.sh in the repository root.

import AppKit

func printPresets() {
    guard let display = Display.builtin else { return print("The built-in display is off.") }
    let presets = sliderPresets(display)
    let index = currentIndex(presets, display)
    for (i, preset) in presets.enumerated() { print(i == index ? "*" : " ", preset.label) }
}

func printPlan(_ widths: [Int]) {
    guard let display = Display.builtin, let native = Display.nativePixels(display), let stock = Config.readStock() else {
        return print("The built-in display is off, or \(Config.stockFile.path) does not exist.")
    }
    let custom = widths.map { Config.customSize(width: $0, native: native) }
    let presets = Config.makePresets(stock: stock, native: native, defaultSize: Display.defaultSize(display), custom: custom)
    print(Config.presetsText(presets), terminator: "")
    print("---")
    print(Override.path(for: display))
    fflush(stdout)
    FileHandle.standardOutput.write(try! Override.plist(sizes: stock + custom, display: display))
}

let arguments = CommandLine.arguments
if arguments.contains("--presets") {
    printPresets()
    exit(0)
}
if let index = arguments.firstIndex(of: "--plan") {
    printPlan(arguments[(index + 1)...].compactMap { Int($0) })
    exit(0)
}

let app = NSApplication.shared
let controller = MenuController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
