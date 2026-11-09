import AppKit
import SwiftUI

/// Reusable Apple-styled keycap badge for keyboard shortcuts
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

/// Semantic colors for QuickFind's native Apple macOS appearance
extension Color {
    /// Elegant translucent selection highlight that blends naturally on translucent HUD/materials.
    static var qfSelection: Color {
        Color.white.opacity(0.10)
    }
    /// Secondary hover fill
    static var qfHover: Color {
        Color.white.opacity(0.05)
    }
    static var qfSeparator: Color {
        Color.white.opacity(0.08)
    }
    static var qfTertiary: Color {
        Color.white.opacity(0.40)
    }
    static var qfSubtleFill: Color {
        Color.white.opacity(0.06)
    }
}
