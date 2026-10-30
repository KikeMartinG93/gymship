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
        let hue = Self.hue(for: name)
        Text(Self.initials(for: name))
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                theme.highContrast
                    ? AnyShapeStyle(Color(white: 0.20))
                    : AnyShapeStyle(LinearGradient(
                        colors: [
                            Color(hue: hue, saturation: 0.55, brightness: 0.95),
                            Color(hue: (hue + 0.07).truncatingRemainder(dividingBy: 1), saturation: 0.78, brightness: 0.62),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )),
                in: Circle()
            )
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

    static func hue(for name: String) -> Double {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }
        return Double(sum) / 360
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
