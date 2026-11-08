import AppKit
import SwiftUI

struct QuickFindView: View {
    @StateObject private var model = QuickFindModel()
    @ObservedObject private var clipboard = ClipboardHistory.shared
    @StateObject private var selection = SelectionState()
    @StateObject private var navigation = SettingsNavigation()
    @ObservedObject private var preferences = LauncherPreferences.shared
    @StateObject private var actionPanel = ActionPanelState()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if navigation.showingSettings {
                    PreferencesView {
                        navigation.showingSettings = false
                        focused = true
                    }
                } else {
                    searchBar
                    Divider().opacity(0.35)
                    splitContent
                }
                footer
            }
            .frame(width: LauncherPanel.panelSize.width, height: LauncherPanel.panelSize.height)
            .background(Color.clear)

            // Raycast Action Panel Overlay (⌘K)
            if actionPanel.isShowing {
                Color.black.opacity(0.25)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { actionPanel.isShowing = false } }

                RaycastActionPanel(
                    result: selectedResult,
                    calculation: model.calculation,
                    onDismiss: { withAnimation(.easeInOut(duration: 0.15)) { actionPanel.isShowing = false; focused = true } },
                    onOpenPreferences: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            actionPanel.isShowing = false
                            navigation.showingSettings = true
                        }
                    }
                )
                .padding(.trailing, 16)
                .padding(.bottom, 46)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .onKeyPress(.escape) {
            if actionPanel.isShowing {
                withAnimation(.easeInOut(duration: 0.15)) { actionPanel.isShowing = false }
                focused = true
                return .handled
            }
            if navigation.showingSettings {
                cancelShortcutCaptureIfNeeded()
                navigation.showingSettings = false
                focused = true
                return .handled
            }
            if !model.query.isEmpty {
                model.query = ""
                return .handled
            }
            NotificationCenter.default.post(name: .closeQuickFind, object: nil)
            return .handled
        }
        .onAppear { focused = true }
        .onChange(of: model.query) { _, _ in
            selection.selectedResultID = model.results.first?.id
            selection.allowHover = false
        }
        .onChange(of: model.results.map(\.id)) { _, resultIDs in
            if !resultIDs.contains(where: { $0 == selection.selectedResultID }) {
                selection.selectedResultID = resultIDs.first
            }
        }
        .onReceive(clipboard.$entries) { _ in
            if case .clipboard = model.parsed { model.search() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusQuickFind)) { _ in
            cancelShortcutCaptureIfNeeded()
            actionPanel.isShowing = false
            model.query = ""
            selection.selectedResultID = model.results.first?.id
            navigation.showingSettings = false
            focused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutCaptureDismissed)) { _ in
            ShortcutRecorderState.shared.isRecording = false
        }
        .onContinuousHover { phase in
            selection.handleHover(phase)
        }
    }

    // MARK: - Search Bar (Raycast Header)

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.85))

            // Breadcrumb mode pill for clipboard
            if case .clipboard = model.parsed {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11))
                    Text("Clipboard")
                        .font(.system(size: 12, weight: .medium))
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(Color.accentColor)
            }

            TextField("Search apps, files, commands, conversions…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15.5, weight: .regular))
                .focused($focused)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.command) {
                        revealSelection()
                    } else {
                        activateSelection()
                    }
                }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(keys: [.return]) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    revealSelection()
                    return .handled
                }
                .onKeyPress(keys: [KeyEquivalent("c"), KeyEquivalent("C")]) { press in
                    guard press.modifiers.contains(.command), press.modifiers.contains(.shift) else { return .ignored }
                    copySelectedPath()
                    return .handled
                }
                .onKeyPress(keys: [KeyEquivalent("k"), KeyEquivalent("K")]) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    withAnimation(.easeInOut(duration: 0.15)) { actionPanel.isShowing.toggle() }
                    return .handled
                }
                .onKeyPress(keys: [KeyEquivalent(",")]) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    navigation.showingSettings = true
                    return .handled
                }
                .onKeyPress(keys: [KeyEquivalent("p"), KeyEquivalent("P")]) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    if let id = selectedResult?.clipboardID {
                        clipboard.togglePin(id)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(keys: Set((1...9).map { KeyEquivalent(Character("\($0)")) })) { press in
                    guard let number = Int(press.characters) else { return .ignored }
                    return launchIndexedApp(number, press: press)
                }

            if model.searchingFiles {
                ProgressView().controlSize(.mini)
            }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            Button {
                navigation.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    // MARK: - Split Content (List + Detail Pane)

    private var splitContent: some View {
        HStack(spacing: 0) {
            // Left: Results list
            VStack(spacing: 0) {
                if model.results.isEmpty && (model.searchingFiles || !model.appsReady) {
                    VStack(spacing: 10) {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text(model.appsReady ? "Searching files…" : "Indexing applications…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if model.results.isEmpty && model.calculation == nil {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("No Results Found")
                            .font(.system(size: 13.5, weight: .medium))
                        Text("Try a different search term or check spelling.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    resultsListView
                }
            }
            .frame(width: 395)

            // Vertical 1px Divider
            Divider().opacity(0.35)

            // Right: Raycast Preview Pane
            RaycastDetailPane(result: selectedResult, calculation: model.calculation)
                .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    headerSectionLabel
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                        let number = appShortcutNumber(for: result, at: index)
                        resultRowButton(result, number: number)
                            .id(result.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: selection.selectedResultID) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.10)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    @ViewBuilder
    private var headerSectionLabel: some View {
        HStack {
            Text(currentSectionTitle)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(model.results.count)")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var currentSectionTitle: String {
        switch model.parsed {
        case .empty:
            return "SUGGESTIONS"
        case .clipboard:
            return "CLIPBOARD HISTORY"
        case .currency, .calculation:
            return "CALCULATOR"
        case .search:
            return "RESULTS"
        }
    }

    private func resultRowButton(_ result: SearchResult, number: Int?) -> some View {
        Button {
            model.activate(result)
            if result.id != "cmd:clipboard" {
                NotificationCenter.default.post(name: .closeQuickFind, object: nil)
            }
        } label: {
            ResultRow(
                result: result,
                selected: result.id == selection.selectedResultID,
                number: number,
                query: highlightQuery,
                reserveIndexColumn: model.results.contains(where: { $0.kind == .app })
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard hovering, selection.allowHover else { return }
            selection.selectedResultID = result.id
        }
        .contextMenu {
            Button(result.kind == .clipboard ? "Copy to Clipboard" : "Open") {
                model.activate(result)
                if result.id != "cmd:clipboard" {
                    NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                }
            }
            if let url = result.url {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                }
                Button("Copy Path") {
                    clipboard.copy(url.path)
                    NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                }
                Button("Copy Name") {
                    clipboard.copy(url.lastPathComponent)
                    NotificationCenter.default.post(name: .closeQuickFind, object: nil)
                }
            }
            if let id = result.clipboardID {
                Button(clipboard.isPinned(id) ? "Unpin Item" : "Pin Item") {
                    clipboard.togglePin(id)
                }
            }
        }
    }

    // MARK: - Footer (Raycast Action Bar)

    private var footer: some View {
        HStack(alignment: .center, spacing: 14) {
            // Primary action
            HStack(spacing: 5) {
                KeyCap(text: "↵")
                Text(footerReturnActionLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
            }

            // Secondary action: Show in Finder
            if selectedResult?.url != nil && !navigation.showingSettings {
                HStack(spacing: 5) {
                    HStack(spacing: 2) {
                        KeyCap(text: "⌘")
                        KeyCap(text: "↵")
                    }
                    Text("Show in Finder")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Copy path
            if selectedResult?.url != nil && !navigation.showingSettings {
                HStack(spacing: 5) {
                    HStack(spacing: 2) {
                        KeyCap(text: "⌘")
                        KeyCap(text: "⇧")
                        KeyCap(text: "C")
                    }
                    Text("Copy Path")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions (⌘K)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    actionPanel.isShowing.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Text("Actions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                    HStack(spacing: 2) {
                        KeyCap(text: "⌘")
                        KeyCap(text: "K")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Show Actions (⌘K)")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .frame(height: 40)
        .background(Color.black.opacity(0.25))
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }

    private var footerReturnActionLabel: String {
        if navigation.showingSettings { return "Select" }
        if model.calculation?.state == .value { return "Copy to Clipboard" }
        if selectedResult?.id == "cmd:clipboard" { return "Open Clipboard History" }
        if case .clipboard = model.parsed { return "Copy to Clipboard" }
        if selectedResult?.kind == .app { return "Open Application" }
        if selectedResult?.kind == .folder { return "Open Folder" }
        return "Open"
    }

    private var selectedResult: SearchResult? {
        model.results.first(where: { $0.id == selection.selectedResultID }) ?? model.results.first
    }

    private var highlightQuery: String {
        if case .clipboard(let filter) = model.parsed { return filter }
        if case .search(let text) = model.parsed { return text }
        return model.query
    }

    private func appShortcutNumber(for result: SearchResult, at index: Int) -> Int? {
        guard result.kind == .app else { return nil }
        let number = model.results.prefix(index + 1).filter { $0.kind == .app }.count
        return number <= 9 ? number : nil
    }

    private func moveSelection(_ delta: Int) {
        guard !model.results.isEmpty else { return }
        selection.allowHover = false
        guard let current = model.results.firstIndex(where: { $0.id == selection.selectedResultID }) else {
            selection.selectedResultID = model.results.first?.id
            return
        }
        let next = min(max(current + delta, 0), model.results.count - 1)
        selection.selectedResultID = model.results[next].id
    }

    private func activateSelection() {
        if let calculation = model.calculation, calculation.state == .value {
            clipboard.copy(calculation.copyText)
            NotificationCenter.default.post(name: .closeQuickFind, object: nil)
            return
        }
        guard let result = model.results.first(where: { $0.id == selection.selectedResultID }) ?? model.results.first else { return }
        model.activate(result)
        if result.id != "cmd:clipboard" {
            NotificationCenter.default.post(name: .closeQuickFind, object: nil)
        }
    }

    private func revealSelection() {
        guard let url = selectedResult?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        NotificationCenter.default.post(name: .closeQuickFind, object: nil)
    }

    private func copySelectedPath() {
        guard let url = selectedResult?.url else { return }
        clipboard.copy(url.path)
        NotificationCenter.default.post(name: .closeQuickFind, object: nil)
    }

    private func cancelShortcutCaptureIfNeeded() {
        guard ShortcutRecorderState.shared.isRecording else { return }
        ShortcutRecorderState.shared.isRecording = false
        NotificationCenter.default.post(name: .shortcutCaptureEnded, object: nil)
    }

    private func launchIndexedApp(_ number: Int, press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command), !press.modifiers.contains(.shift) else { return .ignored }
        let apps = model.results.filter { $0.kind == .app }
        guard apps.indices.contains(number - 1) else { return .handled }
        model.activate(apps[number - 1])
        NotificationCenter.default.post(name: .closeQuickFind, object: nil)
        return .handled
    }
}

@MainActor
final class SelectionState: ObservableObject {
    @Published var selectedResultID: String?
    @Published var allowHover = true
    private var lastHoverPoint: CGPoint?

    func handleHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let point):
            if let lastHoverPoint, abs(point.x - lastHoverPoint.x) > 3 || abs(point.y - lastHoverPoint.y) > 3 {
                allowHover = true
            }
            lastHoverPoint = point
        case .ended:
            lastHoverPoint = nil
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var showingSettings = false
}

@MainActor
final class ActionPanelState: ObservableObject {
    @Published var isShowing = false
}
