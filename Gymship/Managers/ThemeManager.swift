import SwiftUI
import UIKit

/// Drives the app's color theme: a single background hue (picked from a
/// random-swatch selector in Settings) plus a "highlight" (accent) color
/// chosen from a handful of tone variations of that same hue — so the whole
/// app stays in one cohesive color family.
@Observable
@MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    var backgroundHue: Double {
        didSet { UserDefaults.standard.set(backgroundHue, forKey: Self.hueKey) }
    }
    var highlightIndex: Int {
        didSet { UserDefaults.standard.set(highlightIndex, forKey: Self.highlightKey) }
    }

    /// Black-and-white mode: no glass, maximum legibility. Follows Light/Dark
    /// (white-on-black or black-on-white).
    var highContrast: Bool {
        didSet { UserDefaults.standard.set(highContrast, forKey: Self.highContrastKey) }
    }

    /// SF Pro Rounded (on) or the standard SF Pro system font (off).
    var usesRoundedFont: Bool {
        didSet {
            UserDefaults.standard.set(usesRoundedFont, forKey: Self.roundedFontKey)
            Typography.applyToUIKitChrome(rounded: usesRoundedFont)
        }
    }

    /// Dark (the original look), Light, or follow the iPhone.
    var appearance: Appearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            switch appearance {
            case .light: isDark = false
            case .dark: isDark = true
            case .system: break
            }
        }
    }

    /// Whether surfaces currently use the dark palette. `.system` updates this
    /// from the window's color scheme in `sync(from:)`.
    var isDark = true

    private static let roundedFontKey = "gymship.theme.roundedFont"
    private static let highContrastKey = "gymship.theme.highContrast"
    private static let hueKey = "gymship.theme.backgroundHue"
    private static let highlightKey = "gymship.theme.highlightIndex"
    private static let appearanceKey = "gymship.theme.appearance"

    enum Appearance: String, CaseIterable, Identifiable, Hashable {
        case system, light, dark
        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: String(localized: "System")
            case .light: String(localized: "Light")
            case .dark: String(localized: "Dark")
            }
        }

        var preferredColorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// Deep navy/ice-blue — the hue the app's look was originally seeded from.
    static let defaultHue = 228.0 / 360.0

    private init() {
        let defaults = UserDefaults.standard
        highContrast = defaults.bool(forKey: Self.highContrastKey)
        usesRoundedFont = defaults.object(forKey: Self.roundedFontKey) != nil ? defaults.bool(forKey: Self.roundedFontKey) : true
        backgroundHue = defaults.object(forKey: Self.hueKey) != nil
            ? defaults.double(forKey: Self.hueKey)
            : Self.defaultHue
        highlightIndex = defaults.object(forKey: Self.highlightKey) != nil
            ? defaults.integer(forKey: Self.highlightKey)
            : 0
        if let raw = defaults.string(forKey: Self.appearanceKey), let stored = Appearance(rawValue: raw) {
            appearance = stored
        } else {
            appearance = .dark
        }
        isDark = appearance != .light
    }

    func sync(from colorScheme: ColorScheme) {
        let dark: Bool
        switch appearance {
        case .dark: dark = true
        case .light: dark = false
        case .system: dark = colorScheme == .dark
        }
        if dark != isDark { isDark = dark }
    }

    /// A named saturation/brightness combination, applied at the current
    /// `backgroundHue` to produce one highlight option.
    struct HighlightVariation: Identifiable {
        let name: String
        let saturation: Double
        let brightness: Double
        var id: String { name }
    }

    /// 8 tone variations of the same hue, from pale/icy to deep/muted.
    static let highlightVariations: [HighlightVariation] = [
        HighlightVariation(name: String(localized: "Ice"), saturation: 0.20, brightness: 0.95),
        HighlightVariation(name: String(localized: "Sky"), saturation: 0.45, brightness: 0.90),
        HighlightVariation(name: String(localized: "Classic"), saturation: 0.60, brightness: 0.85),
        HighlightVariation(name: String(localized: "Electric"), saturation: 0.85, brightness: 0.95),
        HighlightVariation(name: String(localized: "Neon"), saturation: 1.00, brightness: 1.00),
        HighlightVariation(name: String(localized: "Deep"), saturation: 0.75, brightness: 0.55),
        HighlightVariation(name: String(localized: "Muted"), saturation: 0.35, brightness: 0.65),
        HighlightVariation(name: String(localized: "Slate"), saturation: 0.18, brightness: 0.55),
    ]

    private var currentVariation: HighlightVariation {
        let variations = Self.highlightVariations
        let index = min(max(highlightIndex, 0), variations.count - 1)
        return variations[index]
    }

    /// The app-wide accent color: the current highlight variation at the
    /// current background hue.
    var accent: Color {
        if highContrast { return isDark ? .white : .black }
        return highlightColor(currentVariation)
    }

    func highlightColor(_ variation: HighlightVariation) -> Color {
        if isDark {
            return Color(hue: backgroundHue, saturation: variation.saturation, brightness: variation.brightness)
        }
        // Pale highlights wash out on a light mesh — deepen them so buttons and
        // labels still read.
        return Color(
            hue: backgroundHue,
            saturation: min(1, variation.saturation + 0.14),
            brightness: min(0.68, variation.brightness * 0.74)
        )
    }

    /// The canvas behind glass. Near-black in Dark, near-white in Light.
    var baseColor: Color {
        if highContrast { return Color(white: isDark ? 0.02 : 0.97) }
        if isDark {
            return Color(hue: backgroundHue, saturation: 0.62, brightness: 0.07)
        }
        return Color(hue: backgroundHue, saturation: 0.18, brightness: 0.96)
    }

    /// Translucent card fill so the mesh shows through.
    var wash: Color {
        if highContrast { return Color(white: isDark ? 0.13 : 0.90) }
        return isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.55)
    }

    /// A slightly stronger wash — composer, selected chips.
    var washStrong: Color {
        if highContrast { return Color(white: isDark ? 0.22 : 0.84) }
        return isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.72)
    }

    /// Hairline on cards, avatars, maps.
    var hairline: Color {
        if highContrast { return Color.primary.opacity(isDark ? 0.12 : 0.16) }
        return isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    /// Unfilled week-dial segments, progress tracks, idle dots.
    var emptyTrack: Color {
        if highContrast { return Color.primary.opacity(0.22) }
        return isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }

    /// A companion color in the same family, offset in hue — used for icon
    /// tiles and avatars so accents feel related without all being identical.
    func companion(_ shift: Double, saturation: Double = 0.55, brightness: Double = 0.9) -> Color {
        if highContrast { return isDark ? .white : .black }
        return Color(hue: shiftedHue(by: shift), saturation: saturation, brightness: brightness)
    }

    /// Two-stop fill for icon tiles, glyph badges, and avatars. Uses the
    /// selected hue and highlight, nudged by `shift` so siblings stay related.
    func iconFill(shift: Double = 0) -> [Color] {
        if highContrast {
            return isDark
                ? [Color(white: 0.22), Color(white: 0.14)]
                : [Color(white: 0.88), Color(white: 0.78)]
        }
        let variation = currentVariation
        return [
            Color(
                hue: shiftedHue(by: shift),
                saturation: variation.saturation,
                brightness: min(1, variation.brightness + 0.05)
            ),
            Color(
                hue: shiftedHue(by: shift + 0.04),
                saturation: min(1, variation.saturation + 0.18),
                brightness: max(0.32, variation.brightness - 0.22)
            ),
        ]
    }

    func iconGradient(shift: Double = 0) -> LinearGradient {
        LinearGradient(colors: iconFill(shift: shift), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Readable ink for a glyph sitting on `fill`.
    func ink(on fill: Color) -> Color {
        if highContrast { return isDark ? .white : .black }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(fill).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.62 ? Color(white: 0.06) : .white
    }

    private struct PaletteKey: Equatable {
        var hue: Double
        var highlight: Int
        var highContrast: Bool
        var isDark: Bool
    }

    @ObservationIgnored private var paletteCache: (key: PaletteKey, onAccent: Color, mesh: [Color])?

    private var paletteKey: PaletteKey {
        PaletteKey(hue: backgroundHue, highlight: highlightIndex, highContrast: highContrast, isDark: isDark)
    }

    /// Readable foreground (near-black or white) for content drawn on `accent`.
    var onAccent: Color { cachedPalette.onAccent }

    /// Nine colors for the 3x3 mesh gradient behind every screen.
    var meshColors: [Color] { cachedPalette.mesh }

    private var cachedPalette: (key: PaletteKey, onAccent: Color, mesh: [Color]) {
        let key = paletteKey
        if let paletteCache, paletteCache.key == key { return paletteCache }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(accent).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let packed = (
            key: key,
            onAccent: luminance > 0.62 ? Color(white: 0.06) : Color.white,
            mesh: isDark ? meshColorsDark : meshColorsLight
        )
        paletteCache = packed
        return packed
    }

    private var meshColorsDark: [Color] {
        func tone(_ shift: Double, _ saturation: Double, _ brightness: Double) -> Color {
            Color(hue: shiftedHue(by: shift), saturation: saturation, brightness: brightness)
        }
        return [
            tone(0.00, 0.64, 0.13), tone(0.01, 0.64, 0.16), tone(0.02, 0.62, 0.20),
            tone(0.00, 0.66, 0.24), tone(0.03, 0.74, 0.46), tone(-0.02, 0.62, 0.15),
            tone(-0.03, 0.60, 0.10), tone(0.00, 0.72, 0.34), tone(0.05, 0.70, 0.24),
        ]
    }

    private var meshColorsLight: [Color] {
        func tone(_ shift: Double, _ saturation: Double, _ brightness: Double) -> Color {
            Color(hue: shiftedHue(by: shift), saturation: saturation, brightness: brightness)
        }
        return [
            tone(0.00, 0.22, 0.97), tone(0.02, 0.18, 0.99), tone(-0.01, 0.24, 0.95),
            tone(0.01, 0.28, 0.93), tone(0.04, 0.32, 0.88), tone(-0.02, 0.20, 0.96),
            tone(-0.03, 0.16, 0.98), tone(0.00, 0.26, 0.91), tone(0.05, 0.22, 0.94),
        ]
    }

    private func shiftedHue(by delta: Double) -> Double {
        let shifted = (backgroundHue + delta).truncatingRemainder(dividingBy: 1.0)
        return shifted < 0 ? shifted + 1 : shifted
    }

    /// A fresh set of random, well-saturated hues for the background swatch
    /// picker's "shuffle" action.
    static func randomHues(count: Int = 12) -> [Double] {
        (0..<count).map { _ in Double.random(in: 0...1) }
    }

    /// Alternate home-screen icons are quantized to this many hue buckets
    /// times the eight highlight tones.
    static let appIconHueSteps = 12

    /// Bundled alternate-icon name for this hue and highlight, e.g. `AppIcon-8-3`.
    static func appIconName(hue: Double, highlight: Int) -> String {
        let wrapped = hue.truncatingRemainder(dividingBy: 1)
        let stepped = wrapped < 0 ? wrapped + 1 : wrapped
        let bucket = Int((stepped * Double(appIconHueSteps)).rounded()) % appIconHueSteps
        let tone = min(max(highlight, 0), highlightVariations.count - 1)
        return "AppIcon-\(bucket)-\(tone)"
    }

    /// Points the home-screen icon at the bundled variant for the current accent.
    /// iOS shows its own confirmation when the name actually changes, so call
    /// this when leaving Appearance — not on every swatch tap.
    func applyAppIcon() {
        let name = Self.appIconName(hue: backgroundHue, highlight: highlightIndex)
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard UIApplication.shared.alternateIconName != name else { return }
        Task { try? await UIApplication.shared.setAlternateIconName(name) }
    }
}

/// The font design for the whole app. SwiftUI text inherits it from
/// `.fontDesign(...)` at the root; the navigation titles and tab labels are
/// drawn by UIKit, so they're set here.
enum Typography {
    static func design(rounded: Bool) -> Font.Design { rounded ? .rounded : .default }

    private static func font(_ size: CGFloat, _ weight: UIFont.Weight, rounded: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func applyToUIKitChrome(rounded: Bool) {
        let largeTitle = font(34, .bold, rounded: rounded)
        let title = font(17, .semibold, rounded: rounded)
        let tab = font(10, .semibold, rounded: rounded)
        let tabSelected = font(10, .bold, rounded: rounded)

        // Bars created from now on.
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: largeTitle, .foregroundColor: UIColor.label]
        UINavigationBar.appearance().titleTextAttributes = [.font: title, .foregroundColor: UIColor.label]
        UITabBarItem.appearance().setTitleTextAttributes([.font: tab], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabSelected], for: .selected)

        // Bars already on screen only re-read their font when told to.
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    refresh(window, largeTitle: largeTitle, title: title, tab: tab, tabSelected: tabSelected)
                }
            }
        }
    }

    private static func refresh(_ view: UIView, largeTitle: UIFont, title: UIFont, tab: UIFont, tabSelected: UIFont) {
        if let bar = view as? UINavigationBar {
            func updated(_ appearance: UINavigationBarAppearance) -> UINavigationBarAppearance {
                let copy = appearance.copy()
                copy.largeTitleTextAttributes[.font] = largeTitle
                copy.largeTitleTextAttributes[.foregroundColor] = UIColor.label
                copy.titleTextAttributes[.font] = title
                copy.titleTextAttributes[.foregroundColor] = UIColor.label
                return copy
            }
            bar.standardAppearance = updated(bar.standardAppearance)
            if let compact = bar.compactAppearance { bar.compactAppearance = updated(compact) }
            if let scrollEdge = bar.scrollEdgeAppearance { bar.scrollEdgeAppearance = updated(scrollEdge) }
            if let compactScrollEdge = bar.compactScrollEdgeAppearance { bar.compactScrollEdgeAppearance = updated(compactScrollEdge) }
        } else if let tabBar = view as? UITabBar {
            for item in tabBar.items ?? [] {
                item.setTitleTextAttributes([.font: tab], for: .normal)
                item.setTitleTextAttributes([.font: tabSelected], for: .selected)
            }
        }
        for subview in view.subviews {
            refresh(subview, largeTitle: largeTitle, title: title, tab: tab, tabSelected: tabSelected)
        }
    }
}
