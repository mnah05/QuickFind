import SwiftUI

struct ResultRow: View {
    let result: SearchResult
    let selected: Bool
    let number: Int?
    let query: String

    var body: some View {
        HStack(spacing: 10) {
            // Selected indicator
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(selected ? Color.accentColor : Color.clear)
                .frame(width: 3, height: 16)

            icon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    highlightedTitle
                        .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(Color.primary.opacity(selected ? 1.0 : 0.92))
                        .lineLimit(1)
                        .layoutPriority(1)

                    if result.kind != .clipboard && !result.detail.isEmpty {
                        Text(verbatim: abbreviatedPath)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }

            Spacer(minLength: 8)

            // Right accessories
            if let number {
                HStack(spacing: 2) {
                    KeyCap(text: "⌘")
                    KeyCap(text: "\(number)")
                }
            } else if result.kind == .clipboard, isClipboardPinned == true {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("Pinned")
            }

            // Kind badge
            Text(result.kindLabel)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            if selected {
                KeyCap(text: "↵")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 40)
        .background(
            selected ? Color.qfSelection : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var abbreviatedPath: String {
        result.detail.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    private var isClipboardPinned: Bool? {
        guard let id = result.clipboardID else { return nil }
        return ClipboardHistory.shared.isPinned(id)
    }

    @ViewBuilder
    private var icon: some View {
        if let url = result.url {
            Image(nsImage: FileIconCache.icon(for: url))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else if result.id == "cmd:clipboard" {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }

    private var highlightedTitle: Text {
        guard let hit = FuzzyMatcher.match(candidate: result.title, query: query), !hit.ranges.isEmpty else {
            return Text(result.title)
        }
        var text = Text("")
        var cursor = result.title.startIndex
        for range in hit.ranges where range.lowerBound >= cursor && range.upperBound <= result.title.endIndex {
            if cursor < range.lowerBound {
                text = text + Text(String(result.title[cursor..<range.lowerBound]))
            }
            text = text + Text(String(result.title[range])).fontWeight(.bold).foregroundStyle(Color.accentColor)
            cursor = range.upperBound
        }
        if cursor < result.title.endIndex {
            text = text + Text(String(result.title[cursor...]))
        }
        return text
    }
}
