import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var recordingShortcut = false
    private var panel: LauncherPanel?
    private var closedAt: Date?
    private let hotKeyCenter = HotKeyCenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ClipboardHistory.shared.startMonitoring()
        panel = LauncherPanel(rootView: QuickFindView())

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "QuickFind")
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePanel)

        NotificationCenter.default.addObserver(self, selector: #selector(hidePanel), name: .closeQuickFind, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutChanged), name: .shortcutChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(beginShortcutCapture), name: .shortcutCaptureBegan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(endShortcutCapture), name: .shortcutCaptureEnded, object: nil)

        hotKeyCenter.onPressed = { [weak self] in self?.handleToggle(ignoreCloseDebounce: true) }
        hotKeyCenter.install()
        registerGlobalHotKey()
        closeAuxiliaryWindows()
        DispatchQueue.main.async { [weak self] in self?.closeAuxiliaryWindows() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.closeAuxiliaryWindows() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UpdateManager.shared.checkAutomaticallyIfEnabled()
        }
        showPanel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    private func closeAuxiliaryWindows() {
        for window in NSApp.windows where !(window is LauncherPanel) {
            window.orderOut(nil)
            window.close()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyCenter.uninstall()
        NotificationCenter.default.removeObserver(self)
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard !recordingShortcut else { return }
        hidePanel()
    }

    @objc private func togglePanel() {
        handleToggle(ignoreCloseDebounce: false)
    }

    private func handleToggle(ignoreCloseDebounce: Bool) {
        if panel?.isVisible == true {
            hidePanel()
            return
        }
        if !ignoreCloseDebounce, let closedAt, Date().timeIntervalSince(closedAt) < 0.18 {
            return
        }
        showPanel()
    }

    private func showPanel() {
        guard let panel else { return }
        panel.centerOnMouseScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusQuickFind, object: nil)
        }
    }

    @objc private func hidePanel() {
        if recordingShortcut {
            endShortcutCapture()
            NotificationCenter.default.post(name: .shortcutCaptureDismissed, object: nil)
        }
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        closedAt = Date()
    }

    @objc private func shortcutChanged() { registerGlobalHotKey() }

    @objc private func beginShortcutCapture() {
        recordingShortcut = true
        panel?.hidesOnDeactivate = false
        hotKeyCenter.unregister()
        HotKeyStatus.shared.listen()
    }

    @objc private func endShortcutCapture() {
        recordingShortcut = false
        panel?.hidesOnDeactivate = true
        registerGlobalHotKey()
    }

    private func registerGlobalHotKey() {
        guard !recordingShortcut else { return }
        let status = hotKeyCenter.register(LauncherPreferences.shared.shortcut)
        HotKeyStatus.shared.update(status)
    }
}

@MainActor
final class HotKeyCenter {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onPressed: (() -> Void)?

    func install() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let callback: EventHandlerProcPtr = { _, event, userData in
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            if status == noErr, identifier.id == 1, let userData {
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { center.onPressed?() }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    @discardableResult
    func register(_ shortcut: ShortcutOption) -> OSStatus {
        unregister()
        let identifier = EventHotKeyID(signature: OSType(0x51464E44), id: 1)
        var registeredHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier, GetApplicationEventTarget(), 0, &registeredHotKey)
        hotKey = status == noErr ? registeredHotKey : nil
        return status
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    }

    func uninstall() {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
    }
}
