// The setup window. It takes a new user through these steps:
//   1. Display Scale records the standard sizes and suggests two custom sizes.
//   2. The user changes the widths if necessary and clicks Add Sizes. macOS asks for the password.
//   3. The user restarts the Mac.
//   4. After the restart, the window tells the user that the sizes are ready.

import ServiceManagement
import SwiftUI

final class SetupModel: ObservableObject {
    enum Step: Equatable {
        case noDisplay        // the built-in display is off (for example, the lid is closed)
        case blocked          // another override exists, so the standard sizes are not known
        case choose           // the user selects the custom widths
        case restart(String)  // a restart is necessary; the text tells why
        case done             // the custom sizes are active
        case failed           // after a restart, macOS did not show the custom sizes
    }

    private static let pendingKey = "pendingSizes"
    private static let pendingSinceKey = "pendingSince"

    @Published var step: Step
    @Published var widths: [String]
    @Published var error: String?
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled

    let display: CGDirectDisplayID?
    let native: Size?
    let stock: [Size]
    let moreSpace: Size?
    var onClose: () -> Void = {}

    /// The step to show at launch, or nil when the setup is complete.
    static func launchStep() -> Step? {
        guard let display = Display.builtin else { return nil }
        let defaults = UserDefaults.standard
        if let pending = defaults.stringArray(forKey: pendingKey),
           let since = defaults.object(forKey: pendingSinceKey) as? Date {
            let available = Set(Display.hiDPISizes(display))
            if pending.compactMap({ Size(text: $0) }).allSatisfy(available.contains) {
                clearPending()
                return .done
            }
            if Restart.bootTime > since {
                clearPending()
                return .failed
            }
            return .restart("macOS loads the new sizes when the Mac starts.")
        }
        if Config.readStock() == nil { return Override.exists(for: display) ? .blocked : .choose }
        if Config.readPresets() == nil { return .choose }
        return nil
    }

    /// The step to show when the user opens the setup from the menu.
    static func menuStep() -> Step {
        guard let display = Display.builtin else { return .noDisplay }
        return Config.readStock() == nil && Override.exists(for: display) ? .blocked : .choose
    }

    private static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: pendingSinceKey)
    }

    init(step: Step) {
        let display = Display.builtin
        let native = display.flatMap(Display.nativePixels)
        // Record the standard sizes before any override exists.
        if let display, Config.readStock() == nil, !Override.exists(for: display) {
            try? Config.writeStock(Display.hiDPISizes(display))
        }
        let stock = Config.readStock() ?? []
        let moreSpace = native.flatMap { Config.moreSpace(stock, native: $0) }

        // Start with the custom widths in use, or else with the suggested widths.
        let current = Config.readPresets().map { Config.customSizes($0, stock: stock).map(\.width) } ?? []
        let start = current.isEmpty ? (moreSpace.map(Config.suggestedWidths) ?? []) : current

        self.display = display
        self.native = native
        self.stock = stock
        self.moreSpace = moreSpace
        self.step = display == nil ? .noDisplay : step
        widths = [0, 1].map { $0 < start.count ? String(start[$0]) : "" }
    }

    // MARK: Custom sizes

    func size(at index: Int) -> Size? {
        guard let native, let width = Int(widths[index].trimmingCharacters(in: .whitespaces)) else { return nil }
        return Config.customSize(width: width, native: native)
    }

    func problem(at index: Int) -> String? {
        let text = widths[index].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        guard let width = Int(text) else { return "Enter a number." }
        return moreSpace.flatMap { Config.problem(width: width, moreSpace: $0) }
    }

    var customSizes: [Size] { Array(Set(widths.indices.compactMap(size(at:)))).sorted() }

    var canAdd: Bool { !customSizes.isEmpty && widths.indices.allSatisfy { problem(at: $0) == nil } }

    var suggestion: String {
        moreSpace.map { Config.suggestedWidths(moreSpace: $0).map(String.init).joined(separator: " and ") } ?? "-"
    }

    // MARK: Actions

    func addSizes() {
        guard let display, let native, canAdd else { return }
        let custom = customSizes
        let presets = Config.makePresets(stock: stock, native: native, defaultSize: Display.defaultSize(display), custom: custom)
        run {
            try Override.install(sizes: stock + custom, display: display)
            try Config.writePresets(presets)
            UserDefaults.standard.set(custom.map(\.description), forKey: Self.pendingKey)
            UserDefaults.standard.set(Date(), forKey: Self.pendingSinceKey)
            step = .restart("macOS loads the new sizes when the Mac starts.")
        }
    }

    /// Keep only the standard sizes for now.
    func notNow() {
        if Config.readPresets() == nil, let display, let native {
            try? Config.writePresets(Config.makePresets(stock: stock, native: native,
                                                        defaultSize: Display.defaultSize(display), custom: []))
        }
        onClose()
    }

    func removeOtherOverride() {
        guard let display else { return }
        run {
            try Override.remove(for: display)
            step = .restart("Then open Display Scale again to continue the setup.")
        }
    }

    func removeSizes() {
        guard let display, let native else { return }
        run {
            try Override.remove(for: display)
            try Config.writePresets(Config.makePresets(stock: stock, native: native,
                                                       defaultSize: Display.defaultSize(display), custom: []))
            Self.clearPending()
            step = .restart("After the restart, macOS shows only the standard sizes.")
        }
    }

    func restartNow() {
        if !Restart.request() { error = "macOS did not accept the request. Use Apple menu > Restart." }
    }

    func setOpenAtLogin(_ on: Bool) {
        run {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func run(_ action: () throws -> Void) {
        error = nil
        do {
            try action()
        } catch is Override.Cancelled {
            // The user clicked Cancel in the password prompt.
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Display Scale").font(.title2.bold())
                    Text("Custom sizes for your built-in display").foregroundStyle(.secondary)
                }
            }
            content
            if let error = model.error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .noDisplay:
            Text("Display Scale works only with the built-in display. Open the lid of your Mac, then try again.")
            buttons { Button("Close") { model.onClose() }.keyboardShortcut(.defaultAction) }

        case .blocked:
            Text("Another display override exists for this screen.").font(.headline)
            Text("Another app (for example BetterDisplay) made it. While it is there, Display Scale cannot read the standard sizes of your display. Quit the other app first. Then remove the override and restart the Mac.")
                .fixedSize(horizontal: false, vertical: true)
            Text(model.display.map(Override.path(for:)) ?? "").font(.caption.monospaced()).textSelection(.enabled)
            buttons {
                Button("Close") { model.onClose() }
                Button("Remove Override…") { model.removeOtherOverride() }.keyboardShortcut(.defaultAction)
            }

        case .choose:
            chooseView

        case .restart(let reason):
            Text("Restart the Mac to finish.").font(.headline)
            Text(reason).fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Restart Later") { model.onClose() }
                Button("Restart Now…") { model.restartNow() }.keyboardShortcut(.defaultAction)
            }

        case .done:
            Text("Your new sizes are ready.").font(.headline)
            Text("Click the display icon in the menu bar, then drag the slider. When you release the slider, the screen changes to that size.")
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Open Display Scale at login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
            buttons { Button("Done") { model.onClose() }.keyboardShortcut(.defaultAction) }

        case .failed:
            Text("macOS did not load the new sizes.").font(.headline)
            Text("Display Scale installed the sizes, but they were not there after the restart. This method may not work on this Mac or on this macOS version. Remove the sizes to go back to the standard list.")
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Close") { model.onClose() }
                Button("Remove Sizes…") { model.removeSizes() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder private var chooseView: some View {
        if let native = model.native, let more = model.moreSpace {
            Text("Your built-in display has \(native.display) pixels. Its largest standard size, More Space, is \(more.display).")
                .fixedSize(horizontal: false, vertical: true)
            Text("Add up to two larger sizes. A larger size shows more on the screen, and the text gets smaller.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    HStack(spacing: 10) {
                        Text("Size \(index + 1)").frame(width: 48, alignment: .leading)
                        TextField("Width", text: $model.widths[index])
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                        if let problem = model.problem(at: index) {
                            Text(problem).foregroundStyle(.red)
                        } else if let size = model.size(at: index) {
                            Text("\(size.display)  ·  text at \(Config.percent(size, moreSpace: more))% of More Space")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not used").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Suggested widths: \(model.suggestion). Leave a field empty to add only one size.")
                .font(.caption).foregroundStyle(.secondary)
            Text("When you click Add Sizes, macOS asks for your password. Display Scale then writes one file in /Library/Displays, and you restart the Mac once.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Not Now") { model.notNow() }
                Button("Add Sizes…") { model.addSizes() }.keyboardShortcut(.defaultAction).disabled(!model.canAdd)
            }
        } else {
            Text("Display Scale cannot read the standard sizes of this display.")
            buttons { Button("Close") { model.onClose() }.keyboardShortcut(.defaultAction) }
        }
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer()
            content()
        }
    }
}
