import SwiftUI
import AppKit

struct RaycastDetailPane: View {
    let result: SearchResult?
    let calculation: CalculationDisplay?

    var body: some View {
        VStack(spacing: 0) {
            if let calculation {
                calculationView(calculation)
            } else if let result {
                switch result.kind {
                case .app, .file, .folder:
                    filePreview(result)
                case .clipboard:
                    clipboardPreview(result)
                }
            } else {
                emptyPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.12))
    }

    private var emptyPreview: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No Selection")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func filePreview(_ item: SearchResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    if let url = item.url {
                        Image(nsImage: FileIconCache.icon(for: url))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(2)
                        Text(item.typeDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)

                Divider().opacity(0.4)

                // Metadata
                Text("INFORMATION")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    metaRow("Kind", item.typeDescription)
                    if let version = item.appVersionString {
                        metaRow("Version", version)
                    }
                    if let size = item.fileSizeString {
                        metaRow("Size", size)
                    }
                    if let mod = item.modificationDateString {
                        metaRow("Modified", mod)
                    }
                    if !item.detail.isEmpty {
                        metaRow("Where", item.detail.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    }
                }

                Divider().opacity(0.4)

                // Quick Actions
                Text("QUICK ACTIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    actionRow(key: "↵", label: item.kind == .app ? "Open Application" : "Open File")
                    actionRow(key: "⌘ ↵", label: "Show in Finder")
                    actionRow(key: "⌘ ⇧ C", label: "Copy Path")
                }
            }
            .padding(18)
        }
    }

    private func clipboardPreview(_ item: SearchResult) -> some View {
        let text = item.text ?? item.title
        let charCount = text.count
        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        let isPinned = item.clipboardID.map { ClipboardHistory.shared.isPinned($0) } ?? false

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clipboard Entry")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(charCount) characters · \(wordCount) words")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)

            Divider().opacity(0.4)

            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(4)
                    .foregroundStyle(.primary.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
                    .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func calculationView(_ calc: CalculationDisplay) -> some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 8) {
                Text(calc.expression)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(calc.output)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(calc.state == .error ? Color.orange : .primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)

                Text(calc.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            if calc.state == .value {
                HStack(spacing: 4) {
                    KeyCap(text: "↵")
                    Text("Copy to clipboard")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private func actionRow(key: String, label: String) -> some View {
        HStack(spacing: 8) {
            KeyCap(text: key)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
