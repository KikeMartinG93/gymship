import SwiftUI
import UIKit

// MARK: - Tokens

enum Metrics {
    static let gutter: CGFloat = 16
    static let cardRadius: CGFloat = 28
    static let tileRadius: CGFloat = 18

    /// Shape that follows the device / container corners, never tighter than `minimum`.
    static func concentric(minimum: CGFloat = cardRadius) -> ConcentricRectangle {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(minimum)), isUniform: true)
    }

    /// Padding inside a circular glyph badge, as a fraction of diameter.
    /// Wide symbols like `person.3` scale down to this box instead of overflowing.
    static let glyphInsetRatio: CGFloat = 0.28
}

extension Font {
    /// Gymship's display voice — bold numerals and titles, in whichever design
    /// (rounded or standard) the user has chosen.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    static func display(_ style: Font.TextStyle, _ weight: Font.Weight = .semibold) -> Font {
        .system(style, weight: weight)
    }
}

/// Shared timing. Snappy and short — springs with bounce feel slow on ProMotion
/// and fight Liquid Glass, which already interpolates.
enum Motion {
    static let press = Animation.snappy(duration: 0.14)
    static let ui = Animation.snappy(duration: 0.22)
    static let screen = Animation.snappy(duration: 0.28)

    @MainActor
    static func run(_ animation: Animation = ui, _ updates: () -> Void) {
        if UIAccessibility.isReduceMotionEnabled {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

extension View {
    /// Soft scroll-edge dissolve on every edge. Required on every `ScrollView`,
    /// `List`, and `Form` in the app.
    func gymshipScrollEdges() -> some View {
        scrollEdgeEffectStyle(.soft, for: .all)
    }

    /// Bounce only when motion and power budget allow it.
    func symbolBounceIfAllowed<V: Equatable>(value: V) -> some View {
        modifier(SymbolBounceIfAllowed(value: value))
    }

    /// Value animation that no-ops under Reduce Motion.
    func gymshipAnimation<V: Equatable>(_ animation: Animation = Motion.ui, value: V) -> some View {
        modifier(GymshipAnimation(animation: animation, value: value))
    }

    /// Counting transitions are expensive on ProMotion; skip them when motion is reduced.
    func gymshipNumericText(_ value: Double) -> some View {
        modifier(GymshipNumericText(value: value))
    }
}

private struct SymbolBounceIfAllowed<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLowPowerModeEnabled) private var isLowPowerModeEnabled
    let value: V

    func body(content: Content) -> some View {
        if reduceMotion || isLowPowerModeEnabled {
            content
        } else {
            content.symbolEffect(.bounce, value: value)
        }
    }
}

private struct GymshipAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct GymshipNumericText: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .identity : .numericText(value: value))
    }
}

// MARK: - Content surfaces (not Liquid Glass)

/// Content-layer panel: a concentric translucent wash so the mesh shows
/// through without a second glass sampling pass. Liquid Glass is reserved
/// for chrome and controls — see `glassSurface`.
struct ContentSurface<S: Shape>: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    let shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        if theme.highContrast {
            let emphasized = tint != nil
            content
                .background(shape.fill(Color(white: emphasized ? 0.22 : 0.13)))
                .overlay(shape.stroke(.white.opacity(emphasized ? 0.12 : 0.06), lineWidth: 1))
        } else {
            let fill = tint ?? Color.white.opacity(0.08)
            content.background(fill, in: shape)
        }
    }
}

// MARK: - Liquid Glass surfaces (chrome and controls only)

/// The one place a control is drawn in Liquid Glass; in High Contrast it's a
/// flat panel. A `tint` marks an emphasized (e.g. primary) control.
struct GlassSurface<S: Shape>: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    let shape: S
    var tint: Color?
    var interactive = false

    func body(content: Content) -> some View {
        if theme.highContrast {
            let emphasized = tint != nil
            content
                .background(shape.fill(Color(white: emphasized ? 0.22 : 0.13)))
                .overlay(shape.stroke(.white.opacity(emphasized ? 0.12 : 0.06), lineWidth: 1))
        } else {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            content
                .contentShape(shape)
                .glassEffect(interactive ? base.interactive() : base, in: shape)
        }
    }
}

extension View {
    /// Liquid Glass in `shape` — reserved for chrome and controls.
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    /// A content card. Pass `tint` for a colored (e.g. "locked in") state.
    /// This is not Liquid Glass — glass-on-glass over the tab bar is disallowed.
    func glassCard(cornerRadius: CGFloat = Metrics.cardRadius, tint: Color? = nil) -> some View {
        modifier(ContentSurface(shape: Metrics.concentric(minimum: cornerRadius), tint: tint))
    }

    /// A small capsule for labels and chips. `tint` is a semantic color;
    /// omit it to use the app's highlight color.
    func glassPill(tint: Color? = nil, isActive: Bool = true) -> some View {
        modifier(GlassPill(tint: tint, isActive: isActive))
    }

    /// A flat, faint inset — for rows nested *inside* a card, where a second
    /// layer of glass would muddy the surface.
    func inset(cornerRadius: CGFloat = Metrics.tileRadius) -> some View {
        background(.white.opacity(0.07), in: Metrics.concentric(minimum: cornerRadius))
    }

    /// Native glass button — or an outlined black/white one in High Contrast.
    func glassButton(circle: Bool = false) -> some View {
        modifier(GlassButton(circle: circle))
    }

    /// Native switch — or a bold outlined one in High Contrast.
    func adaptiveToggle() -> some View {
        modifier(AdaptiveToggle())
    }

    /// Solid black sheets in High Contrast (the default is glass).
    func highContrastSheetBackground() -> some View {
        modifier(HighContrastSheetBackground())
    }
}

struct GlassPill: ViewModifier {
    @Environment(ThemeManager.self) private var theme
    var tint: Color?
    var isActive: Bool

    func body(content: Content) -> some View {
        let resolved = tint ?? theme.accent
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassSurface(Capsule(), tint: isActive ? resolved.opacity(0.45) : nil)
    }
}

// MARK: - Buttons & chrome

private struct GlassButton: ViewModifier {
    @Environment(ThemeManager.self) private var theme
    let circle: Bool

    func body(content: Content) -> some View {
        if theme.highContrast {
            content.buttonStyle(HighContrastButtonStyle(isCircle: circle))
        } else {
            content.buttonStyle(.glass)
        }
    }
}

/// A soft, tonal button for High Contrast: a shade lighter than the
/// background, no outline — round for icon-only buttons.
struct HighContrastButtonStyle: ButtonStyle {
    var isCircle = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, isCircle ? 0 : 16)
            .padding(.vertical, isCircle ? 0 : 9)
            .frame(minWidth: isCircle ? 44 : nil, minHeight: isCircle ? 44 : nil)
            .background {
                let fill = Color(white: configuration.isPressed ? 0.26 : 0.16)
                if isCircle {
                    Circle().fill(fill)
                } else {
                    Capsule().fill(fill)
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ToolbarContent {
    /// Removes the system glass capsule behind a toolbar item in High Contrast.
    func flatInHighContrast() -> some ToolbarContent {
        sharedBackgroundVisibility(ThemeManager.shared.highContrast ? .hidden : .automatic)
    }
}

private struct AdaptiveToggle: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        if theme.highContrast {
            content.tint(Color(white: 0.4))
        } else {
            content
        }
    }
}

private struct HighContrastSheetBackground: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        if theme.highContrast {
            content.presentationBackground(Color(white: 0.02))
        } else {
            content
        }
    }
}

// MARK: - Section header

/// Section title (sentence case, like the system's own sections) with an
/// optional one-line explanation, used identically on every screen.
struct SectionHeader<Trailing: View>: View {
    @Environment(ThemeManager.self) private var theme

    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(theme.highContrast ? Color.primary.opacity(0.8) : Color.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Background

/// The ambient world every screen sits in: a slowly drifting mesh gradient in
/// the theme's hue. Glass refracts it, which is what gives the surfaces their
/// depth. Animates at ~2 fps for a few seconds, then freezes so ProMotion can
/// idle. Full-screen covers pass `allowsMotion: false` so they never start a
/// second timeline.
struct GymshipBackground: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLowPowerModeEnabled) private var isLowPowerModeEnabled

    var allowsMotion = true

    @State private var isOnScreen = true
    @State private var settled = false
    @State private var frozenDate = Date()

    private var shouldAnimate: Bool {
        allowsMotion
            && isOnScreen
            && scenePhase == .active
            && !settled
            && !theme.highContrast
            && !reduceMotion
            && !reduceTransparency
            && !isLowPowerModeEnabled
    }

    var body: some View {
        SwiftUI.Group {
            if theme.highContrast || reduceTransparency {
                Color(white: 0.02)
            } else if shouldAnimate {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    mesh(at: context.date.timeIntervalSinceReferenceDate)
                        // Never interpolate between 2fps samples — that would pin ProMotion at 120.
                        .transaction { $0.animation = nil }
                }
            } else {
                mesh(at: (reduceMotion || !allowsMotion) ? 0 : frozenDate.timeIntervalSinceReferenceDate)
                    .transaction { $0.animation = nil }
            }
        }
        .ignoresSafeArea()
        .backgroundExtensionEffect()
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .task(id: shouldAnimate) {
            guard shouldAnimate else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            frozenDate = Date()
            settled = true
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            // Don't restart the 2fps timeline when returning from Control Center.
            frozenDate = Date()
            settled = true
        }
    }

    private func mesh(at t: Double) -> MeshGradient {
        MeshGradient(
            width: 3,
            height: 3,
            points: Self.points(at: t),
            colors: theme.meshColors,
            smoothsColors: true
        )
    }

    private static func points(at t: Double) -> [SIMD2<Float>] {
        func f(_ value: Double) -> Float { Float(value) }
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, f(0.48 + 0.05 * sin(t * 0.30))],
            [f(0.5 + 0.10 * sin(t * 0.23)), f(0.5 + 0.09 * cos(t * 0.19))],
            [1, f(0.52 + 0.05 * cos(t * 0.27))],
            [0, 1], [f(0.5 + 0.12 * sin(t * 0.21)), 1], [1, 1],
        ]
    }
}
