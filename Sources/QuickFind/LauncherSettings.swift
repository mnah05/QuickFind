import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

struct ShortcutOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [ShortcutOption] = [
        ShortcutOption(id: "option-space", title: "⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        ShortcutOption(id: "control-space", title: "⌃ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)),
        ShortcutOption(id: "control-option-space", title: "⌃ ⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
        ShortcutOption(id: "command-shift-space", title: "⌘ ⇧ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey)),
        ShortcutOption(id: "option-k", title: "⌥ K", keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(optionKey))
    ]
}

extension Notification.Name {
    static let shortcutChanged = Notification.Name("QuickFind.shortcutChanged")
    static let shortcutCaptureBegan = Notification.Name("QuickFind.shortcutCaptureBegan")
    static let shortcutCaptureEnded = Notification.Name("QuickFind.shortcutCaptureEnded")
    static let shortcutCaptureDismissed = Notification.Name("QuickFind.shortcutCaptureDismissed")
}

@MainActor
final class LauncherPreferences: ObservableObject {
    static let shared = LauncherPreferences()
    @Published var selectedShortcutID: String {
        didSet {
            UserDefaults.standard.set(selectedShortcutID, forKey: "launcherShortcut.v1")
            NotificationCenter.default.post(name: .shortcutChanged, object: nil)
        }
    }

    @Published private(set) var customShortcut: ShortcutOption?

    private init() {
        let storedCustom: ShortcutOption?
        if let key = UserDefaults.standard.object(forKey: "customShortcutKey.v1") as? Int,
           let modifiers = UserDefaults.standard.object(forKey: "customShortcutModifiers.v1") as? Int,
           let title = UserDefaults.standard.string(forKey: "customShortcutTitle.v1") {
            storedCustom = ShortcutOption(id: "custom", title: title, keyCode: UInt32(key), modifiers: UInt32(modifiers))
        } else {
            storedCustom = nil
        }
        customShortcut = storedCustom
        let stored = UserDefaults.standard.string(forKey: "launcherShortcut.v1") ?? "option-space"
        selectedShortcutID = (stored == "custom" && storedCustom != nil) || ShortcutOption.all.contains(where: { $0.id == stored }) ? stored : "option-space"
    }

    var shortcut: ShortcutOption {
        if selectedShortcutID == "custom", let customShortcut { return customShortcut }
        return ShortcutOption.all.first(where: { $0.id == selectedShortcutID }) ?? ShortcutOption.all[0]
    }

    func setCustomShortcut(keyCode: UInt32, modifiers: UInt32, title: String) {
        customShortcut = ShortcutOption(id: "custom", title: title, keyCode: keyCode, modifiers: modifiers)
        UserDefaults.standard.set(Int(keyCode), forKey: "customShortcutKey.v1")
        UserDefaults.standard.set(Int(modifiers), forKey: "customShortcutModifiers.v1")
        UserDefaults.standard.set(title, forKey: "customShortcutTitle.v1")
        selectedShortcutID = "custom"
    }
}

@MainActor
final class ShortcutRecorderState: ObservableObject {
    static let shared = ShortcutRecorderState()
    @Published var isRecording = false
    @Published var hint = "Use at least one modifier key, such as ⌥ or ⌘."
}

struct ShortcutCaptureView: NSViewRepresentable {
    let onCapture: (UInt32, UInt32, String) -> Void
    let onCancel: () -> Void
    let onInvalid: (String) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.onInvalid = onInvalid
        return view
    }

    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.onInvalid = onInvalid
    }
}

final class ShortcutCaptureNSView: NSView {
    var onCapture: ((UInt32, UInt32, String) -> Void)?
    var onCancel: (() -> Void)?
    var onInvalid: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        guard carbonModifiers != 0 else {
            onInvalid?("Add a modifier key, such as ⌥, ⌃, or ⌘.")
            return
        }

        let code = UInt32(event.keyCode)
        if carbonModifiers == UInt32(cmdKey), [UInt32(kVK_ANSI_Q), UInt32(kVK_ANSI_H), UInt32(kVK_ANSI_M), UInt32(kVK_ANSI_W)].contains(code) {
            onInvalid?("That combination is reserved by macOS or common apps.")
            return
        }

        let character = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keyName: String
        if event.keyCode == UInt16(kVK_Space) { keyName = "Space" }
        else if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) { keyName = "Return" }
        else if event.keyCode == UInt16(kVK_Tab) { keyName = "Tab" }
        else if event.keyCode == UInt16(kVK_Delete) { keyName = "Delete" }
        else if event.keyCode == UInt16(kVK_ForwardDelete) { keyName = "Forward Delete" }
        else if event.keyCode == UInt16(kVK_LeftArrow) { keyName = "←" }
        else if event.keyCode == UInt16(kVK_RightArrow) { keyName = "→" }
        else if event.keyCode == UInt16(kVK_UpArrow) { keyName = "↑" }
        else if event.keyCode == UInt16(kVK_DownArrow) { keyName = "↓" }
        else if event.keyCode == UInt16(kVK_Escape) { keyName = "Esc" }
        else {
            let isControlChar = character.unicodeScalars.allSatisfy { $0.value < 0x20 || ($0.value >= 0x7F && $0.value <= 0x9F) || ($0.value >= 0xF700 && $0.value <= 0xF8FF) }
            keyName = (character.isEmpty || isControlChar) ? "Key \(code)" : character.uppercased()
        }

        let prefix = [
            (UInt32(controlKey), "⌃"),
            (UInt32(optionKey), "⌥"),
            (UInt32(shiftKey), "⇧"),
            (UInt32(cmdKey), "⌘")
        ].filter { carbonModifiers & $0.0 != 0 }.map(\.1).joined(separator: " ")
        onCapture?(code, carbonModifiers, "\(prefix) \(keyName)")
    }
}

@MainActor
final class HotKeyStatus: ObservableObject {
    static let shared = HotKeyStatus()
    @Published private(set) var message = ""
    @Published private(set) var isRegistered = false

    func update(_ status: OSStatus) {
        isRegistered = status == noErr
        message = status == noErr ? "Shortcut is ready." : "That shortcut is unavailable. Choose another one."
    }

    func listen() {
        isRegistered = false
        message = "Listening for a shortcut…"
    }
}

@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()
    @Published private(set) var isEnabled = false
    @Published private(set) var message = ""

    private init() { refresh() }

    func refreshStatus() { refresh() }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            message = error.localizedDescription
            refresh(keepMessage: true)
        }
    }

    private func refresh(keepMessage: Bool = false) {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        if !keepMessage {
            switch status {
            case .enabled: message = "QuickFind will open when you sign in."
            case .requiresApproval: message = "Allow QuickFind in System Settings → General → Login Items."
            case .notRegistered: message = "QuickFind won’t open automatically."
            case .notFound: message = "Build and run the QuickFind app bundle to enable this."
            @unknown default: message = "Login item status is unavailable."
            }
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var preferences = LauncherPreferences.shared
    @ObservedObject var shortcutStatus = HotKeyStatus.shared
    @ObservedObject var loginItem = LoginItemManager.shared
    @ObservedObject var clipboard = ClipboardHistory.shared
    @ObservedObject var updates = UpdateManager.shared
    @ObservedObject private var recorder = ShortcutRecorderState.shared
    let goBack: () -> Void

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    if recorder.isRecording {
                        recorder.isRecording = false
                        NotificationCenter.default.post(name: .shortcutCaptureEnded, object: nil)
                    }
                    goBack()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28).background(Color.primary.opacity(0.05), in: Circle())
                }.buttonStyle(.plain).help("Back to search")
                VStack(alignment: .leading, spacing: 2) {
                    Text("QuickFind settings").font(.system(size: 15, weight: .semibold))
                    Text("Shortcuts and privacy").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.bottom, 18)

            Text("LAUNCHER").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            HStack {
                Label("Global shortcut", systemImage: "keyboard")
                Spacer()
                Picker("Global shortcut", selection: $preferences.selectedShortcutID) {
                    ForEach(ShortcutOption.all) { option in Text(option.title).tag(option.id) }
                    if let custom = preferences.customShortcut { Text("Custom · \(custom.title)").tag(custom.id) }
                }.labelsHidden().pickerStyle(.menu).frame(width: 145)
            }.padding(.top, 8)
            Text(shortcutStatus.message).font(.system(size: 11)).foregroundStyle(shortcutStatus.isRegistered ? Color.gray : Color.orange).padding(.leading, 25).padding(.top, 3)
            if recorder.isRecording {
                ShortcutCaptureView(onCapture: { keyCode, modifiers, title in
                    preferences.setCustomShortcut(keyCode: keyCode, modifiers: modifiers, title: title)
                    recorder.hint = "Saved \(title)."
                    recorder.isRecording = false
                    NotificationCenter.default.post(name: .shortcutCaptureEnded, object: nil)
                }, onCancel: {
                    recorder.isRecording = false
                    recorder.hint = "Shortcut recording cancelled."
                    NotificationCenter.default.post(name: .shortcutCaptureEnded, object: nil)
                }, onInvalid: { recorder.hint = $0 })
                    .frame(height: 36)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 8)
                Text(recorder.hint).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 25).padding(.top, 3)
            } else {
                Button("Record a custom shortcut…") {
                    recorder.hint = "Use at least one modifier key, such as ⌥ or ⌘."
                    recorder.isRecording = true
                    NotificationCenter.default.post(name: .shortcutCaptureBegan, object: nil)
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.accentColor).padding(.leading, 25).padding(.top, 7)
            }

            Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })) {
                Label("Open at login", systemImage: "power")
            }.toggleStyle(.switch).padding(.top, 16)
            Text(loginItem.message).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 25).padding(.top, 3)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.vertical, 16)
            Text("CLIPBOARD").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            Toggle(isOn: $clipboard.isPaused) {
                Label("Pause clipboard capture", systemImage: clipboard.isPaused ? "pause.circle" : "doc.on.clipboard")
            }.toggleStyle(.switch).padding(.top, 8)
            HStack {
                Label("Auto-clear unpinned items", systemImage: "clock")
                Spacer()
                Picker("Auto-clear", selection: $clipboard.expiryDays) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("Never").tag(0)
                }.labelsHidden().pickerStyle(.menu).frame(width: 115)
            }.padding(.top, 12)
            Text("Pinned items don’t expire. Clipboard text stays on this Mac.")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 25).padding(.top, 4)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.vertical, 16)
            Text("UPDATES").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            Toggle(isOn: $updates.automaticChecksEnabled) {
                Label("Check for updates automatically", systemImage: "arrow.down.circle")
            }.toggleStyle(.switch).padding(.top, 8)
            HStack(alignment: .top, spacing: 8) {
                Text(updates.statusMessage)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Check now") { updates.checkNow() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.accentColor)
                    .disabled(updates.isChecking)
            }.padding(.leading, 25).padding(.top, 5)
            Text("When enabled, QuickFind checks GitHub at launch. Downloads start only after you choose Download Update.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary).padding(.leading, 25).padding(.top, 4)

            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Label("Quit QuickFind", systemImage: "power")
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.clear)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loginItem.refreshStatus() }
    }
}
