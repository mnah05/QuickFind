import AppKit
import SwiftUI

@main
struct QuickFindApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            SceneHostView()
        }
        .defaultSize(width: 1, height: 1)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

private struct SceneHostView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SelfClosingSceneView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SelfClosingSceneView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !(window is LauncherPanel) else { return }
        DispatchQueue.main.async { window.close() }
    }
}
