import SwiftUI

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
    }
}

struct ResultRow: View {
    let result: SearchResult
    let selected: Bool
    let number: Int?
    let query: String

    var body: some View {
        HStack(spacing: 10) {
            // Selected indicator
            RoundedRectangle(cornerRadius: 2, style: .continuous)
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
                        Text(result.detail.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
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
            } else if result.kind == .clipboard, let isPinned = isClipboardPinned, isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 4)
            }

            // Kind badge
            Text(result.kindLabel)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            if selected {
                KeyCap(text: "↵")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 42)
        .background(
            selected ? Color.white.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }

    private var highlightedTitle: Text {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let range = result.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(result.title)
        }
        let before = String(result.title[..<range.lowerBound])
        let match = String(result.title[range])
        let after = String(result.title[range.upperBound...])
        return Text(before) + Text(match).fontWeight(.bold).foregroundStyle(Color.accentColor) + Text(after)
    }
}
