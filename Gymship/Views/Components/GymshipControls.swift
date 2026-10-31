import SwiftUI

// MARK: - Buttons

/// Icon-only glass circle. Glass is drawn in a fixed `Circle` so thin glyphs
/// like `minus` don't shrink the material versus their pair (`plus`).
struct GlassCircleButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let systemImage: String
    var label: LocalizedStringKey
    let action: () -> Void

    init(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .glassCircleSymbol()
        }
        .buttonStyle(.plain)
        .glassSurface(Circle(), interactive: true)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

/// The primary, full-width action: a capsule of tinted Liquid Glass.
struct GymshipButtonStyle: ButtonStyle {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(.headline))
            .foregroundStyle(theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background { if theme.highContrast { Capsule().fill(theme.accent) } }
            .glassSurface(Capsule(), tint: theme.highContrast ? nil : theme.accent, interactive: true)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .gymshipAnimation(Motion.press, value: configuration.isPressed)
    }
}

/// Official Sign in with Google control.
/// Light + pill, per https://developers.google.com/identity/branding-guidelines
/// Size matches Gymship's primary buttons so it isn't visually weaker.
struct GoogleSignInButton: View {
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image("GoogleG")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)

                if isLoading {
                    ProgressView()
                        .tint(GoogleSignInChrome.label)
                } else {
                    Text("Sign in with Google")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(GoogleSignInChrome.label)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Capsule())
        }
        .buttonStyle(GoogleSignInChrome())
        .disabled(isLoading)
        .accessibilityLabel(Text("Sign in with Google"))
    }
}

/// Light-theme Google chrome: white fill, #747775 hairline, 40pt+ pill.
private struct GoogleSignInChrome: ButtonStyle {
    static let fill = Color.white
    static let pressedFill = Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255)
    static let stroke = Color(red: 116 / 255, green: 119 / 255, blue: 117 / 255)
    static let label = Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Self.pressedFill : Self.fill, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Self.stroke, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .gymshipAnimation(Motion.press, value: configuration.isPressed)
    }
}

/// The compact primary action that sits inline on a card ("I'm in").
struct PillButtonStyle: ButtonStyle {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(.subheadline))
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background { if theme.highContrast { Capsule().fill(theme.accent) } }
            .glassSurface(Capsule(), tint: theme.highContrast ? nil : theme.accent, interactive: true)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .gymshipAnimation(Motion.press, value: configuration.isPressed)
    }
}

// MARK: - Text input

struct GlassTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white.opacity(0.08), in: Metrics.concentric(minimum: 18))
    }
}

extension View {
    func glassTextFieldStyle() -> some View {
        textFieldStyle(GlassTextFieldStyle())
    }
}

// MARK: - Segmented choice

/// A segmented control. Native (glass) normally; a flat white-on-black one in
/// High Contrast, where the system control would bring glass back.
struct SegmentedChoice<Value: Hashable>: View {
    @Environment(ThemeManager.self) private var theme

    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        if theme.highContrast {
            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    let selected = option.value == selection
                    Button {
                        selection = option.value
                    } label: {
                        Text(option.label)
                            .font(.system(.subheadline, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selected ? Color.white.opacity(0.16) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.06), in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } else {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].label).tag(options[index].value)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Grouped rows (Settings-style)

/// A single glass panel holding a stack of rows, with hairline dividers.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .glassCard(cornerRadius: 24)
    }
}

/// Inset divider matching `SettingsRow`'s icon column.
struct RowDivider: View {
    var body: some View {
        Divider()
            .overlay(.white.opacity(0.06))
            .padding(.leading, 60)
    }
}

/// An iOS-Settings-style rounded icon tile, painted from the selected theme.
struct IconTile: View {
    @Environment(ThemeManager.self) private var theme

    let symbol: String
    var shift: Double = 0
    var color: Color?
    var size: CGFloat = 30

    var body: some View {
        let fills = fillColors
        FittedSymbol(symbol, color: theme.ink(on: fills[0]))
            .padding(size * Metrics.glyphInsetRatio)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: fills, startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            )
    }

    private var fillColors: [Color] {
        if let color { return [color, color.opacity(0.7)] }
        return theme.iconFill(shift: shift)
    }
}

/// SF Symbol scaled to the offered space so wide glyphs don't overflow.
struct FittedSymbol: View {
    let symbol: String
    var color: Color

    init(_ symbol: String, color: Color) {
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .font(.body.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color)
    }
}

/// Circular badge painted from the selected theme. Same inset ratio at every
/// size, so `person.3` and `sparkles` sit equally in the circle.
struct GlyphBadge: View {
    @Environment(ThemeManager.self) private var theme

    let symbol: String
    var size: CGFloat = 84
    var shift: Double = 0

    var body: some View {
        let fills = theme.iconFill(shift: shift)
        FittedSymbol(symbol, color: theme.ink(on: fills[0]))
            .padding(size * Metrics.glyphInsetRatio)
            .frame(width: size, height: size)
            .background(theme.iconGradient(shift: shift), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Label content for a row inside a `GlassGroup`. Wrap in a `NavigationLink`
/// or `Button` (with `.buttonStyle(.plain)`) at the call site.
struct SettingsRow: View {
    let symbol: String
    var shift: Double = 0
    var color: Color?
    let title: String
    var detail: String?
    var showsChevron = true
    var titleColor: Color = .primary

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, shift: shift, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(titleColor)
                if let detail {
                    Text(detail)
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Feedback

/// Big, friendly placeholder for screens with nothing to show yet.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 18) {
            GlyphBadge(symbol: symbol, size: 84)

            VStack(spacing: 6) {
                Text(title)
                    .font(.display(.title2))
                Text(message)
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            actions
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Asks for a permission the screen can't work without.
struct PermissionCard: View {
    let symbol: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        EmptyStateView(symbol: symbol, title: title, message: message) {
            Button(buttonTitle, action: action)
                .buttonStyle(GymshipButtonStyle())
                .padding(.top, 4)
        }
        .glassCard()
    }
}

/// A quiet inline message: errors in red, info in secondary.
struct InlineMessage: View {
    let text: String
    var isError = false

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
            .font(.system(.footnote))
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard(cornerRadius: 18, tint: isError ? .red.opacity(0.2) : nil)
    }
}

/// A one-line "nothing here" tile used inside a section.
struct HintTile: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(.subheadline))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassCard(cornerRadius: 22)
    }
}
