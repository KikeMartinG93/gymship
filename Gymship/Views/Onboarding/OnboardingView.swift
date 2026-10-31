import SwiftUI

/// First run: four beats — hello, calendar, Google sign-in, and a
/// short tour. Big type sits directly on the background; only the controls
/// are glass.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(SupabaseService.self) private var supabase
    @Environment(ThemeManager.self) private var theme

    @State private var step: Step = .welcome
    @State private var isRequestingAccess = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var tutorialPage = 0

    enum Step: Int, CaseIterable {
        case welcome, calendarAccess, signIn, howItWorks
    }

    private struct TutorialSlide {
        let systemImage: String
        let title: String
        let description: String
    }

    private let tutorialSlides: [TutorialSlide] = [
        TutorialSlide(
            systemImage: "calendar.badge.clock",
            title: String(localized: "Your calendar, private"),
            description: String(localized: "Mark which calendars count as busy. Gymship shares only when you're busy — never why.")
        ),
        TutorialSlide(
            systemImage: "person.3.fill",
            title: String(localized: "Start a crew"),
            description: String(localized: "Make a crew and share its invite code, or join a friend's. Up to five people per crew.")
        ),
        TutorialSlide(
            systemImage: "sparkles",
            title: String(localized: "Let AI find the time"),
            description: String(localized: "Once everyone's synced, Apple Intelligence suggests the best slot on each free day.")
        ),
        TutorialSlide(
            systemImage: "checkmark.seal.fill",
            title: String(localized: "Say you're in"),
            description: String(localized: "Tap I'm in. When a second person joins, the workout locks — then plan the ride and see who's leaving when.")
        ),
        TutorialSlide(
            systemImage: "target",
            title: String(localized: "Hit your week"),
            description: String(localized: "The Plan dial tracks your weekly goal and suggests solo sessions to fill the gaps.")
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            heroDial
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            SwiftUI.Group {
                switch step {
                case .welcome: welcome
                case .calendarAccess: calendarAccess
                case .signIn: signIn
                case .howItWorks: howItWorks
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            progressDots
                .padding(.top, 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .gymshipAnimation(Motion.screen, value: step)
    }

    // MARK: Chrome

    /// A decorative week dial that fills in as you move through the flow.
    private var heroDial: some View {
        let start = EventKitManager.currentWeekInterval().start
        let calendar = Calendar.current
        let filled = min(7, step.rawValue * 2 + (step == .howItWorks ? tutorialPage / 2 : 0))
        let days = Set((0..<filled).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { calendar.startOfDay(for: $0) })

        return ZStack {
            WeekRingView(
                weekStart: start,
                committed: days,
                locked: days,
                goal: 7,
                selectedDay: nil,
                showsCenter: false,
                showsLabels: false
            ) { _ in }
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(theme.accent)
                .symbolBounceIfAllowed(value: step)
        }
        .frame(width: 240, height: 240)
        .accessibilityHidden(true)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { candidate in
                Capsule()
                    .fill(candidate == step ? theme.accent : .white.opacity(0.25))
                    .frame(width: candidate == step ? 26 : 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .gymshipAnimation(value: step)
    }

    private func headline(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.display(40))
                .lineSpacing(-4)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(.system(.title3))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func glyph(_ symbol: String) -> some View {
        GlyphBadge(symbol: symbol, size: 72)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            headline(String(localized: "Gymship"), String(localized: "Your crew's free time, turned into workouts."))
            Button("Get started") {
                step = .calendarAccess
            }
            .buttonStyle(GymshipButtonStyle())
        }
    }

    private var calendarAccess: some View {
        VStack(alignment: .leading, spacing: 24) {
            glyph("calendar.badge.clock")
            headline(String(localized: "See when you're free"), String(localized: "Gymship reads your calendar to find gaps, and writes locked-in workouts to its own calendar."))

            if let errorMessage {
                InlineMessage(text: errorMessage, isError: true)
            }

            Button {
                Task { await requestAccess() }
            } label: {
                if isRequestingAccess {
                    ProgressView()
                } else {
                    Text("Allow calendar access")
                }
            }
            .buttonStyle(GymshipButtonStyle())
            .disabled(isRequestingAccess)
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 24) {
            glyph("person.crop.circle.badge.checkmark")
            headline(String(localized: "Make it yours"), String(localized: "Sign in with Google to create your Gymship account. No password."))

            if let errorMessage {
                InlineMessage(text: errorMessage, isError: true)
            }

            GoogleSignInButton(isLoading: isSigningIn) {
                Task { await handleGoogleSignIn() }
            }
        }
    }

    private var howItWorks: some View {
        let slide = tutorialSlides[tutorialPage]
        let isLast = tutorialPage == tutorialSlides.count - 1

        return VStack(alignment: .leading, spacing: 24) {
            glyph(slide.systemImage)
                .id("glyph-\(tutorialPage)")
                .transition(.scale.combined(with: .opacity))

            VStack(alignment: .leading, spacing: 12) {
                Text(slide.title)
                    .font(.display(32))
                    .fixedSize(horizontal: false, vertical: true)
                Text(slide.description)
                    .font(.system(.title3))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id("copy-\(tutorialPage)")
            .transition(.opacity)

            HStack(spacing: 12) {
                if tutorialPage > 0 {
                    Button {
                        tutorialPage -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(.headline))
                            .frame(width: 30, height: 30)
                    }
                    .glassButton(circle: true)
                    .buttonBorderShape(.circle)
                }
                Button(isLast ? "Let's go" : "Next") {
                    if isLast {
                        appState.isOnboarded = true
                    } else {
                        tutorialPage += 1
                    }
                }
                .buttonStyle(GymshipButtonStyle())
            }
        }
        .gymshipAnimation(Motion.ui, value: tutorialPage)
    }

    // MARK: Actions

    private func requestAccess() async {
        isRequestingAccess = true
        errorMessage = nil
        let granted = await eventKitManager.requestAccess()
        isRequestingAccess = false
        if granted {
            step = .signIn
        } else {
            errorMessage = String(localized: "Calendar access was denied. You can enable it later in Settings.")
        }
    }

    private func handleGoogleSignIn() async {
        errorMessage = nil
        isSigningIn = true
        do {
            try await supabase.signInWithGoogle()
            step = .howItWorks
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        isSigningIn = false
    }
}
