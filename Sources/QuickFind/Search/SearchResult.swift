import Foundation

struct SearchResult: Identifiable, Equatable {
    enum Kind: Equatable { case app, file, folder, clipboard }

    let id: String
    let title: String
    let detail: String
    let kind: Kind
    let url: URL?
    let text: String?
    var clipboardID: UUID? = nil

    var kindLabel: String {
        switch kind {
        case .app: "App"
        case .file: "File"
        case .folder: "Folder"
        case .clipboard: "Clipboard"
        }
    }

    var fileSizeString: String? {
        guard let url, kind == .file else { return nil }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var appVersionString: String? {
        guard let url, kind == .app else { return nil }
        return Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var modificationDateString: String? {
        guard let url else { return nil }
        guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var typeDescription: String {
        if kind == .clipboard { return "Clipboard Entry" }
        if kind == .app { return "Application" }
        if let url, let desc = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription {
            return desc
        }
        return kindLabel
    }

    static func app(url: URL) -> SearchResult {
        let name = url.deletingPathExtension().lastPathComponent
        return SearchResult(
            id: "app:\(url.standardizedFileURL.path)",
            title: name,
            detail: url.deletingLastPathComponent().path,
            kind: .app,
            url: url,
            text: nil
        )
    }

    static func file(url: URL) -> SearchResult {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isFolder = (values?.isDirectory == true)
            && (values?.isPackage != true)
            && url.pathExtension != "app"
        return SearchResult(
            id: "file:\(url.standardizedFileURL.path)",
            title: url.lastPathComponent,
            detail: url.deletingLastPathComponent().path,
            kind: isFolder ? .folder : .file,
            url: url,
            text: nil
        )
    }

    static func clipboard(_ entry: ClipboardEntry) -> SearchResult {
        SearchResult(
            id: "clip:\(entry.id.uuidString)",
            title: entry.text.prefix(100).components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " "),
            detail: entry.isPinned ? "Pinned · Return to copy" : "Return to copy",
            kind: .clipboard,
            url: nil,
            text: entry.text,
            clipboardID: entry.id
        )
    }
}

extension Array {
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
