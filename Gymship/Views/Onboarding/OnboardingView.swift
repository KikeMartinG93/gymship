import SwiftUI

/// First run: four beats — hello, calendar, email sign-in, and a
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
    @State private var email = ""
    @State private var otp = ""
    @State private var otpSent = false
    @State private var username = ""
    @State private var handleStatus: HandleStatus = .empty
    @State private var handleCheckTask: Task<Void, Never>?

    enum Step: Int, CaseIterable {
        case welcome, calendarAccess, signIn, pickUsername, howItWorks
    }

    private enum HandleStatus: Equatable {
        case empty, tooShort, checking, available, taken, failed(String)

        var caption: String {
            switch self {
            case .empty: String(localized: "3–20 letters, numbers, or underscores.")
            case .tooShort: String(localized: "At least 3 characters.")
            case .checking: String(localized: "Checking…")
            case .available: String(localized: "Available. This is how you'll be known.")
            case .taken: String(localized: "That username is taken.")
            case .failed(let message): message
            }
        }

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }
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
                case .pickUsername: pickUsername
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
        .animation(.smooth(duration: 0.45), value: step)
        .task { await resumeIncompleteSignIn() }
        .onChange(of: username) { _, newValue in
            let sanitized = GymshipHandle.sanitize(newValue)
            if sanitized != newValue {
                username = sanitized
                return
            }
            scheduleHandleCheck()
        }
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
        .animation(.snappy, value: step)
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
        Image(systemName: symbol)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(theme.accent)
            .frame(width: 72, height: 72)
            .glassSurface(Metrics.concentric(minimum: 24))
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
            glyph("envelope.badge")
            if otpSent {
                headline(
                    String(localized: "Check your email"),
                    String(localized: "Enter the 6-digit code we sent to \(email).")
                )
            } else {
                headline(
                    String(localized: "Make it yours"),
                    String(localized: "We'll email you a 6-digit code. No password — and it works on a sideloaded build.")
                )
            }

            if otpSent {
                TextField("000000", text: $otp)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .glassTextFieldStyle()
                    .onChange(of: otp) { _, newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue { otp = String(digits.prefix(6)) }
                        else if newValue.count > 6 { otp = String(newValue.prefix(6)) }
                    }
                    .disabled(isSigningIn)
            } else {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .glassTextFieldStyle()
                    .submitLabel(.send)
                    .onSubmit { Task { await sendCode() } }
                    .disabled(isSigningIn)
            }

            if let errorMessage {
                InlineMessage(text: errorMessage, isError: true)
            }

            Button {
                Task { otpSent ? await verifyCode() : await sendCode() }
            } label: {
                if isSigningIn {
                    ProgressView()
                } else {
                    Text(otpSent ? "Verify code" : "Send code")
                }
            }
            .buttonStyle(GymshipButtonStyle())
            .disabled(isSigningIn || (otpSent ? otp.count != 6 : !emailLooksValid))

            if otpSent {
                HStack(spacing: 16) {
                    Button("Resend code") {
                        Task { await sendCode() }
                    }
                    Button("Different email") {
                        otp = ""
                        otpSent = false
                        errorMessage = nil
                    }
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
                .disabled(isSigningIn)
            }
        }
    }

    private var pickUsername: some View {
        VStack(alignment: .leading, spacing: 24) {
            glyph("at")
            headline(
                String(localized: "Pick a username"),
                String(localized: "This is how you'll be known in the app.")
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 2) {
                    Text("@")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .font(.system(.title3, weight: .semibold))
                        .submitLabel(.continue)
                        .onSubmit { Task { await saveUsername() } }
                        .disabled(isSigningIn)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white.opacity(0.08), in: Metrics.concentric(minimum: 18))

                Text(handleStatus.caption)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(handleStatusColor)
                    .padding(.horizontal, 4)
            }

            if let errorMessage {
                InlineMessage(text: errorMessage, isError: true)
            }

            Button {
                Task { await saveUsername() }
            } label: {
                if isSigningIn {
                    ProgressView()
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(GymshipButtonStyle())
            .disabled(isSigningIn || !handleStatus.isAvailable)
        }
        .onAppear { scheduleHandleCheck() }
    }

    private var handleStatusColor: Color {
        switch handleStatus {
        case .available: theme.accent
        case .taken, .failed, .tooShort: .red.opacity(0.9)
        case .empty, .checking: .secondary
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
        .animation(.smooth(duration: 0.35), value: tutorialPage)
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

    private var emailLooksValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return trimmed.count >= 5 && domain.contains(".")
    }

    private func sendCode() async {
        guard emailLooksValid else { return }
        isSigningIn = true
        errorMessage = nil
        do {
            try await supabase.sendEmailOTP(to: email)
            otp = ""
            otpSent = true
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        isSigningIn = false
    }

    private func verifyCode() async {
        guard otp.count == 6 else { return }
        isSigningIn = true
        errorMessage = nil
        do {
            try await supabase.verifyEmailOTP(otp, email: email)
            advanceAfterSignIn()
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        isSigningIn = false
    }

    /// If the app was killed after the email code but before a username,
    /// skip back to the right beat.
    private func resumeIncompleteSignIn() async {
        await supabase.restoreSession()
        if supabase.profile != nil {
            step = .howItWorks
        } else if supabase.currentUserId != nil {
            if username.isEmpty, let mail = email.split(separator: "@").first {
                username = GymshipHandle.sanitize(String(mail))
            }
            step = .pickUsername
        }
    }

    private func advanceAfterSignIn() {
        if supabase.profile != nil {
            step = .howItWorks
            return
        }
        if username.isEmpty, let mail = email.split(separator: "@").first {
            username = GymshipHandle.sanitize(String(mail))
        }
        errorMessage = nil
        step = .pickUsername
    }

    private func scheduleHandleCheck() {
        handleCheckTask?.cancel()
        errorMessage = nil
        guard !username.isEmpty else {
            handleStatus = .empty
            return
        }
        guard username.count >= GymshipHandle.minLength else {
            handleStatus = .tooShort
            return
        }
        handleStatus = .checking
        handleCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                let available = try await supabase.isHandleAvailable(username)
                guard !Task.isCancelled else { return }
                handleStatus = available ? .available : .taken
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                handleStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func saveUsername() async {
        guard handleStatus.isAvailable else { return }
        isSigningIn = true
        errorMessage = nil
        do {
            try await supabase.createProfile(handle: username, name: username)
            step = .howItWorks
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
            if case .handleTaken = error as? SupabaseServiceError {
                handleStatus = .taken
            }
        }
        isSigningIn = false
    }
}
