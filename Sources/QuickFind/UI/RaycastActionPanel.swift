import SwiftUI
import AppKit

struct ActionItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    let shortcut: [String]
    let action: () -> Void
}

@MainActor
final class ActionPanelFilterState: ObservableObject {
    @Published var filter = ""
    @Published var selectedIndex = 0
}

struct RaycastActionPanel: View {
    let result: SearchResult?
    let calculation: CalculationDisplay?
    let onDismiss: () -> Void
    let onOpenPreferences: () -> Void

    @StateObject private var state = ActionPanelFilterState()
    @FocusState private var isFieldFocused: Bool

    private var allActions: [ActionItem] {
        var list: [ActionItem] = []

        if let calculation, calculation.state == .value {
            list.append(ActionItem(
                id: "copy_calc",
                title: "Copy Calculation to Clipboard",
                icon: "doc.on.doc",
                shortcut: ["↵"],
                action: {
                    ClipboardHistory.shared.copy(calculation.copyText)
                    NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                }
            ))
        }

        if let result {
            if result.kind == .app {
                list.append(ActionItem(
                    id: "open",
                    title: "Open Application",
                    icon: "arrow.up.forward.app",
                    shortcut: ["↵"],
                    action: {
                        if let url = result.url {
                            UsageTracker.shared.recordUse(of: url)
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                                if error != nil { DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
                            }
                        }
                        NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                    }
                ))
            } else if result.kind == .file || result.kind == .folder {
                list.append(ActionItem(
                    id: "open",
                    title: result.kind == .folder ? "Open Folder in Finder" : "Open File",
                    icon: "doc",
                    shortcut: ["↵"],
                    action: {
                        if let url = result.url {
                            UsageTracker.shared.recordUse(of: url)
                            NSWorkspace.shared.open(url)
                        }
                        NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                    }
                ))
            } else if result.kind == .clipboard {
                list.append(ActionItem(
                    id: "copy_clip",
                    title: "Copy to Clipboard",
                    icon: "doc.on.clipboard",
                    shortcut: ["↵"],
                    action: {
                        if let text = result.text {
                            ClipboardHistory.shared.copy(text)
                        }
                        NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                    }
                ))
                if let id = result.clipboardID {
                    let isPinned = ClipboardHistory.shared.isPinned(id)
                    list.append(ActionItem(
                        id: "pin",
                        title: isPinned ? "Unpin from Clipboard" : "Pin to Clipboard",
                        icon: isPinned ? "pin.slash" : "pin",
                        shortcut: ["⌘", "P"],
                        action: {
                            ClipboardHistory.shared.togglePin(id)
                        }
                    ))
                }
            }

            if let url = result.url {
                list.append(ActionItem(
                    id: "reveal",
                    title: "Show in Finder",
                    icon: "folder",
                    shortcut: ["⌘", "↵"],
                    action: {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                    }
                ))
                list.append(ActionItem(
                    id: "copy_path",
                    title: "Copy Path",
                    icon: "link",
                    shortcut: ["⌘", "⇧", "C"],
                    action: {
                        ClipboardHistory.shared.copy(url.path)
                        NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                    }
                ))
                list.append(ActionItem(
                    id: "copy_name",
                    title: "Copy Name",
                    icon: "character.cursor.ibeam",
                    shortcut: ["⌘", "⌥", "C"],
                    action: {
                        ClipboardHistory.shared.copy(url.lastPathComponent)
                        NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                    }
                ))
            }
        }

        list.append(ActionItem(
            id: "preferences",
            title: "QuickFind Settings…",
            icon: "gearshape",
            shortcut: ["⌘", ","],
            action: {
                onOpenPreferences()
            }
        ))

        list.append(ActionItem(
            id: "quit",
            title: "Quit QuickFind",
            icon: "power",
            shortcut: ["⌘", "Q"],
            action: {
                NSApp.terminate(nil)
            }
        ))

        return list
    }

    private var filteredActions: [ActionItem] {
        let trimmed = state.filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return allActions }
        return allActions.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("Search actions…", text: $state.filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFieldFocused)
                    .onSubmit {
                        executeSelected()
                    }
                    .onKeyPress(.downArrow) {
                        moveSelection(1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        moveSelection(-1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        onDismiss()
                        return .handled
                    }

                Spacer()

                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))

            Divider().opacity(0.3)

            // Action Items
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, item in
                            actionRow(item: item, selected: index == state.selectedIndex)
                                .id(item.id)
                                .onTapGesture {
                                    item.action()
                                    onDismiss()
                                }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: state.selectedIndex) { _, newIndex in
                    if filteredActions.indices.contains(newIndex) {
                        proxy.scrollTo(filteredActions[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 320, height: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
        .onAppear {
            isFieldFocused = true
            state.selectedIndex = 0
        }
    }

    private func actionRow(item: ActionItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 18)

            Text(item.title)
                .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                .foregroundStyle(Color.primary.opacity(selected ? 1.0 : 0.85))

            Spacer()

            HStack(spacing: 2) {
                ForEach(item.shortcut, id: \.self) { key in
                    KeyCap(text: key)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            selected ? Color.white.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private func moveSelection(_ delta: Int) {
        guard !filteredActions.isEmpty else { return }
        let next = min(max(state.selectedIndex + delta, 0), filteredActions.count - 1)
        state.selectedIndex = next
    }

    private func executeSelected() {
        guard filteredActions.indices.contains(state.selectedIndex) else { return }
        filteredActions[state.selectedIndex].action()
        onDismiss()
    }
}
