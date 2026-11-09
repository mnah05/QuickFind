import AppKit
import SwiftUI

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
                HStack(spacing: 12) {
                    if let url = item.url {
                        Image(nsImage: FileIconCache.icon(for: url))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                        Text(item.typeDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)

                Divider()

                sectionLabel("INFORMATION")

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
                        metaRow("Where", abbreviated(item.detail))
                    }
                }

                Divider()

                sectionLabel("QUICK ACTIONS")

                VStack(spacing: 6) {
                    actionRow("↵", item.kind == .app ? "Open Application" : "Open File")
                    actionRow("⌘ ↵", "Show in Finder")
                    actionRow("⌘ ⇧ C", "Copy Path")
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
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clipboard Entry")
                        .font(.headline)
                    Text("\(charCount) characters · \(wordCount) words")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 18)

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(4)
                    .foregroundStyle(.primary.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func calculationView(_ calc: CalculationDisplay) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Text(calc.expression)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(calc.output)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(calc.state == .error ? Color.orange : Color.primary)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: calc.output)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)

            Text(calc.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if calc.state == .value {
                HStack(spacing: 5) {
                    KeyCap(text: "↵")
                    Text("Copy to clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)
            Text(verbatim: value)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private func actionRow(_ key: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            KeyCap(text: key)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func abbreviated(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}
