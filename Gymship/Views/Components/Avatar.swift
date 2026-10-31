import SwiftUI

/// A person, drawn as a colorful initials bubble. The color is derived from
/// the name, so everyone keeps the same look on every screen and device.
struct Avatar: View {
    @Environment(ThemeManager.self) private var theme

    var name: String
    var size: CGFloat = 40
    /// Draws a ring around the bubble (e.g. green = "synced").
    var ring: Color?

    var body: some View {
        let shift = Self.hueShift(for: name)
        let fills = theme.iconFill(shift: shift)
        Text(Self.initials(for: name))
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(theme.ink(on: fills[0]))
            .frame(width: size, height: size)
            .background(theme.iconGradient(shift: shift), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
            .overlay {
                if let ring {
                    Circle().strokeBorder(theme.highContrast ? .white.opacity(0.55) : ring, lineWidth: 2.5).padding(-4)
                }
            }
    }

    static func initials(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// Small hue offset in the current theme so people stay distinct without
    /// leaving the selected color family.
    static func hueShift(for name: String) -> Double {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 100 }
        return (Double(sum) / 100 - 0.5) * 0.12
    }
}

/// Overlapping avatars, capped with a "+N" bubble.
struct AvatarStack: View {
    @Environment(ThemeManager.self) private var theme

    var names: [String]
    var size: CGFloat = 30
    var limit = 4

    var body: some View {
        HStack(spacing: -size * 0.34) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { index, name in
                Avatar(name: name, size: size)
                    .overlay(Circle().strokeBorder(theme.baseColor, lineWidth: 2))
                    .zIndex(Double(limit - index))
            }
            if names.count > limit {
                Text("+\(names.count - limit)")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .frame(width: size, height: size)
                    .glassSurface(Circle())
            }
        }
    }
}
