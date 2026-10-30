import SwiftUI

/// You: profile, availability, crews, appearance, and the testing reset.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SupabaseService.self) private var supabase
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(ThemeManager.self) private var theme

    @State private var isShowingJoinCreate = false
    @State private var isShowingEditProfile = false
    @State private var isShowingWhatsNew = false
    @State private var isShowingWhatToTest = false
    @State private var isShowingResetConfirmation = false
    @State private var isResetting = false

    var body: some View {
        @Bindable var theme = theme
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    profileHeader

                    GlassGroup {
                        NavigationLink {
                            CalendarSetupView()
                        } label: {
                            SettingsRow(
                                symbol: "calendar",
                                color: theme.companion(0),
                                title: String(localized: "Availability"),
                                detail: availabilitySummary
                            )
                        }
                        .buttonStyle(.plain)

                        RowDivider()

                        Button {
                            isShowingJoinCreate = true
                        } label: {
                            SettingsRow(
                                symbol: "person.badge.plus",
                                color: theme.companion(0.08),
                                title: String(localized: "Start or join a crew")
                            )
                        }
                        .buttonStyle(.plain)

                        RowDivider()

                        Toggle(isOn: $theme.highContrast.animation(.smooth)) {
                            HStack(spacing: 14) {
                                IconTile(symbol: "circle.lefthalf.filled", color: .gray)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("High contrast")
                                        .font(.system(.body, weight: .medium))
                                    Text("Black & white, no glass")
                                        .font(.system(.footnote))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .adaptiveToggle()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        RowDivider()

                        Toggle(isOn: $theme.usesRoundedFont) {
                            HStack(spacing: 14) {
                                IconTile(symbol: "textformat", color: theme.companion(-0.16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Rounded font")
                                        .font(.system(.body, weight: .medium))
                                    Text(theme.usesRoundedFont ? "SF Pro Rounded" : "Standard SF Pro")
                                        .font(.system(.footnote))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .adaptiveToggle()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        RowDivider()

                        NavigationLink {
                            PreferencesView()
                        } label: {
                            SettingsRow(
                                symbol: "slider.horizontal.3",
                                color: theme.companion(0.16),
                                title: String(localized: "Preferences"),
                                detail: String(localized: "Hours, mornings or evenings, rest days")
                            )
                        }
                        .buttonStyle(.plain)

                        RowDivider()

                        NavigationLink {
                            AppearanceView()
                        } label: {
                            SettingsRow(
                                symbol: "paintpalette.fill",
                                color: theme.companion(-0.08),
                                title: String(localized: "Appearance"),
                                detail: theme.highContrast ? String(localized: "Off while High contrast is on") : String(localized: "Background & highlight")
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    GlassGroup {
                        Button {
                            isShowingWhatToTest = true
                        } label: {
                            SettingsRow(
                                symbol: "checklist",
                                color: theme.companion(0.24),
                                title: String(localized: "What to test"),
                                detail: String(localized: "What Gymship does, and what to try")
                            )
                        }
                        .buttonStyle(.plain)

                        RowDivider()

                        Button {
                            isShowingWhatsNew = true
                        } label: {
                            SettingsRow(
                                symbol: "megaphone.fill",
                                color: theme.companion(0.16),
                                title: String(localized: "What's new"),
                                detail: String(localized: "See what changed in each update")
                            )
                        }
                        .buttonStyle(.plain)

                        RowDivider()

                        HStack {
                            IconTile(symbol: "info.circle.fill", color: .gray)
                            Text("Version")
                                .font(.system(.body, weight: .medium))
                            Spacer()
                            Text(Self.versionString)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: String(localized: "Testing"))
                        GlassGroup {
                            Button {
                                isShowingResetConfirmation = true
                            } label: {
                                SettingsRow(
                                    symbol: "arrow.counterclockwise",
                                    color: .red,
                                    title: String(localized: "Reset to factory defaults"),
                                    detail: String(localized: "Signs out and clears this device's local data"),
                                    showsChevron: false,
                                    titleColor: .red
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isResetting)
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 32)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingJoinCreate) {
                GroupJoinCreateView()
            }
            .sheet(isPresented: $isShowingEditProfile) {
                EditProfileSheet()
            }
            .fullScreenCover(isPresented: $isShowingWhatsNew) {
                WhatsNewView(releases: ReleaseNotes.all) { isShowingWhatsNew = false }
            }
            .fullScreenCover(isPresented: $isShowingWhatToTest) {
                WhatToTestView { isShowingWhatToTest = false }
            }
            .alert("Reset to factory defaults?", isPresented: $isShowingResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    Task { await resetToFactoryDefaults() }
                }
            } message: {
                Text("This signs you out and clears all local app data (profile, groups, availability, goals) on this device. Nothing on the server is deleted. For testing only.")
            }
            .task {
                if eventKitManager.isAuthorized {
                    await eventKitManager.refreshCalendars()
                }
            }
        }
    }

    // MARK: Pieces

    private var profileHeader: some View {
        VStack(spacing: 14) {
            Avatar(name: supabase.profile?.name ?? "?", size: 88)
                .shadow(color: theme.highContrast ? .clear : theme.accent.opacity(0.35), radius: 8)

            if let profile = supabase.profile {
                VStack(spacing: 2) {
                    Text(profile.name)
                        .font(.display(28))
                    Text("@\(profile.handle)")
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Button("Edit profile", systemImage: "pencil") { isShowingEditProfile = true }
                    .glassButton()
            } else {
                Text("Not signed in")
                    .font(.display(.title3))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var availabilitySummary: String {
        guard eventKitManager.isAuthorized else { return String(localized: "Calendar access needed") }
        let busy = eventKitManager.calendars.filter { (eventKitManager.availability[$0.id] ?? .unavailable) == .unavailable }.count
        return String(localized: "\(busy) of \(eventKitManager.calendars.count) calendars count as busy")
    }

    private func resetToFactoryDefaults() async {
        isResetting = true
        await supabase.resetLocalState()
        eventKitManager.resetLocalState()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "gymship.weeklyGoal")
        defaults.removeObject(forKey: "gymship.weeklySoloDurationMinutes")

        theme.backgroundHue = ThemeManager.defaultHue
        theme.highlightIndex = 0
        theme.highContrast = false
        theme.usesRoundedFont = true

        isResetting = false
        appState.isOnboarded = false
    }

    private static var versionString: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }
}

// MARK: - Edit profile

private struct EditProfileSheet: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var handle = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var hasChanges: Bool {
        guard let profile = supabase.profile else { return false }
        return name != profile.name || handle.lowercased() != profile.handle.lowercased()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()
                    Avatar(name: name.isEmpty ? "?" : name, size: 84)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                        .glassTextFieldStyle()
                    TextField("Handle", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .glassTextFieldStyle()
                    Text("Friends find you by your handle: 3–20 lowercase letters or numbers.")
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                if let errorMessage {
                    InlineMessage(text: errorMessage, isError: true)
                }

                Spacer()

                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save") }
                }
                .buttonStyle(GymshipButtonStyle())
                .disabled(isSaving || !hasChanges || name.isEmpty || handle.isEmpty)
            }
            .padding(Metrics.gutter)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                .flatInHighContrast()
            }
            .onAppear {
                if let profile = supabase.profile {
                    name = profile.name
                    handle = profile.handle
                }
            }
        }
        .presentationDetents([.large])
        .highContrastSheetBackground()
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            try await supabase.updateProfile(handle: handle, name: name)
            dismiss()
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        isSaving = false
    }
}

// MARK: - Appearance

/// Pick the background hue and a highlight tone. Changes apply live — the
/// screen you're looking at is the preview.
private struct AppearanceView: View {
    @Environment(ThemeManager.self) private var theme

    @State private var randomHues: [Double] = ThemeManager.randomHues(count: 11)

    private var backgroundHues: [Double] { [theme.backgroundHue] + randomHues }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                preview

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: String(localized: "Background"), subtitle: String(localized: "Every screen adopts the hue")) {
                        Button("Shuffle", systemImage: "shuffle") {
                            withAnimation(.snappy) { randomHues = ThemeManager.randomHues(count: 11) }
                        }
                        .font(.system(.footnote, weight: .semibold))
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), spacing: 14) {
                        ForEach(Array(backgroundHues.enumerated()), id: \.offset) { _, hue in
                            swatch(color: Color(hue: hue, saturation: 0.6, brightness: 0.85), selected: abs(hue - theme.backgroundHue) < 0.0005) {
                                withAnimation(.smooth) { theme.backgroundHue = hue }
                            }
                        }
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 28)
                    .sensoryFeedback(.selection, trigger: theme.backgroundHue)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: String(localized: "Highlight"), subtitle: String(localized: "Buttons, the week dial and accents"))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 18) {
                        ForEach(Array(ThemeManager.highlightVariations.enumerated()), id: \.offset) { index, variation in
                            VStack(spacing: 8) {
                                swatch(color: theme.highlightColor(variation), selected: theme.highlightIndex == index) {
                                    withAnimation(.smooth) { theme.highlightIndex = index }
                                }
                                Text(variation.name)
                                    .font(.system(.caption, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 28)
                    .sensoryFeedback(.selection, trigger: theme.highlightIndex)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A miniature of the real UI, so a change is judged in context.
    private var preview: some View {
        HStack(spacing: 18) {
            ZStack {
                ForEach(0..<7, id: \.self) { index in
                    Circle()
                        .trim(from: Double(index) / 7 + 0.02, to: Double(index + 1) / 7 - 0.02)
                        .stroke(
                            index < 3 ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.white.opacity(0.1)),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                Text(String(localized: "3"))
                    .font(.display(34))
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Thursday · 6:30 PM"))
                    .font(.display(.headline))
                Button("I'm in") {}
                    .buttonStyle(PillButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .glassCard(cornerRadius: 30, tint: theme.accent.opacity(0.22))
    }

    private func swatch(color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 38, height: 38)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .overlay {
                    if selected {
                        Circle().strokeBorder(.white, lineWidth: 3).padding(-5)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Preferences

/// Personal scheduling rules that shape every workout Gymship suggests from
/// this device.
private struct PreferencesView: View {
    @AppStorage(WorkoutPreferences.storageKey) private var stored = ""
    @State private var prefs = WorkoutPreferences.current

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private static func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func timeBinding(_ keyPath: WritableKeyPath<WorkoutPreferences, Int>) -> Binding<Date> {
        Binding(
            get: { Self.date(minutes: prefs[keyPath: keyPath]) },
            set: { prefs[keyPath: keyPath] = Self.minutes($0) }
        )
    }

    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: String(localized: "Never outside"), subtitle: String(localized: "Workouts are never suggested beyond these hours"))
                    GlassGroup {
                        DatePicker(String(localized: "Never before"), selection: timeBinding(\.earliestStart), displayedComponents: .hourAndMinute)
                            .padding(16)
                        RowDivider().padding(.leading, 16)
                        DatePicker(String(localized: "Never after"), selection: timeBinding(\.latestEnd), displayedComponents: .hourAndMinute)
                            .padding(16)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: String(localized: "Preferred time"), subtitle: String(localized: "A nudge, not a rule — used when a day has options"))
                    GlassGroup {
                        SegmentedChoice(
                            title: String(localized: "Preferred time"),
                            selection: $prefs.lean,
                            options: [
                                (WorkoutPreferences.Lean.none, String(localized: "No preference")),
                                (.before, String(localized: "Before")),
                                (.after, String(localized: "After")),
                            ]
                        )
                        .padding(16)
                        if prefs.lean != .none {
                            RowDivider().padding(.leading, 16)
                            DatePicker(
                                prefs.lean == .before ? String(localized: "Prefer before") : String(localized: "Prefer after"),
                                selection: timeBinding(\.leanMinutes),
                                displayedComponents: .hourAndMinute
                            )
                            .padding(16)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: String(localized: "Rest days"), subtitle: String(localized: "No workouts on these days"))
                    HStack(spacing: 8) {
                        ForEach(weekdayOrder, id: \.self) { weekday in
                            let off = prefs.restWeekdays.contains(weekday)
                            Button {
                                if off { prefs.restWeekdays.remove(weekday) } else { prefs.restWeekdays.insert(weekday) }
                            } label: {
                                Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(off ? .primary : .secondary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(off ? Color.white.opacity(0.18) : Color.white.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                            .accessibilityValue(off ? String(localized: "Rest day") : "")
                        }
                    }
                }

                Text("These apply to suggestions made on this device, for you and for your crews.")
                    .font(.system(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: prefs) {
            if prefs.latestEnd <= prefs.earliestStart { prefs.latestEnd = min(24 * 60, prefs.earliestStart + 60) }
            stored = prefs.json
        }
    }
}
