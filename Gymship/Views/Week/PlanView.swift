import SwiftUI

/// Home: the week as a dial, the sessions in it, and solo slots suggested
/// from your own free time. Browse back a year, or ahead one week.
struct PlanView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(ThemeManager.self) private var theme

    @AppStorage(WorkoutPreferences.storageKey) private var preferencesJSON = ""
    @AppStorage("gymship.weeklyGoal") private var weeklyGoal: Int = 3
    @AppStorage("gymship.weeklySoloDurationMinutes") private var durationMinutes: Int = 60

    @State private var coordinator = SessionCoordinator()

    /// 0 = this week, negative = weeks ago (to -52), 1 = next week.
    @State private var weekOffset = 0
    @State private var committedDays: Set<Date> = []
    @State private var selectedDay: Date?

    @State private var confirmedCount = 0
    @State private var suggestions: [WorkoutSlotFinder.Candidate] = []
    @State private var addedCandidates: Set<WorkoutSlotFinder.Candidate> = []
    @State private var isComputing = false

    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var errorMessage: String?

    /// The in-flight week/solo-suggestions refresh, if any. Tracked so
    /// tapping through several weeks quickly cancels the stale ones instead
    /// of letting an old response race in and clobber the current week.
    @State private var refreshTask: Task<Void, Never>?
    /// Solo AI runs on first appear and on pull-to-refresh / preference
    /// changes — not every time you flip back to Plan.
    @State private var didComputeSolo = false

    private static let maxWeeksBack = 52

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    if !eventKitManager.isAuthorized {
                        PermissionCard(
                            symbol: "calendar.badge.exclamationmark",
                            title: String(localized: "Let Gymship see your calendar"),
                            message: String(localized: "It only reads when you're busy, so your crew can find time that works for everyone."),
                            buttonTitle: String(localized: "Allow calendar access")
                        ) {
                            Task { await eventKitManager.requestAccess() }
                        }
                    } else {
                        heroCard
                        sessionsSection
                        if weekOffset == 0 { soloSection }
                    }

                    if let message = errorMessage ?? coordinator.errorMessage {
                        InlineMessage(text: message, isError: true)
                    }
                    if let syncMessage {
                        InlineMessage(text: syncMessage)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 32)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationBarTitleDisplayMode(.inline)
            .sessionSheets(coordinator)
            .task { await loadAll(includingSolo: !didComputeSolo) }
            .refreshable { await loadAll(includingSolo: true) }
            .onChange(of: weekOffset) {
                selectedDay = nil
                refresh { await loadWeek(); await recompute() }
            }
            .onChange(of: preferencesJSON) { refresh { await recompute() } }
            .onChange(of: weeklyGoal) { refresh { await recompute() } }
            .onChange(of: durationMinutes) { refresh { await recompute() } }
            .onChange(of: supabase.myResponses) {
                refresh { await loadWeek() }
            }
        }
    }

    // MARK: Header

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 { return String(localized: "Good night") }
        if hour < 12 { return String(localized: "Good morning") }
        if hour < 17 { return String(localized: "Good afternoon") }
        return String(localized: "Good evening")
    }

    private var subtitle: String {
        let date = Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard let first = supabase.profile?.name.split(separator: " ").first else { return date }
        return "\(first) · \(date)"
    }

    // MARK: Hero

    private var weekStart: Date {
        let base = EventKitManager.currentWeekInterval().start
        return Calendar.current.date(byAdding: .day, value: weekOffset * 7, to: base) ?? base
    }

    private var weekInterval: DateInterval {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return DateInterval(start: weekStart, end: end)
    }

    private var weekTitle: String {
        switch weekOffset {
        case 0: String(localized: "This week")
        case 1: String(localized: "Next week")
        case -1: String(localized: "Last week")
        default: String(localized: "\(-weekOffset) weeks ago")
        }
    }

    private var lockedDays: Set<Date> {
        // Past weeks only ever contain workouts that really happened.
        if weekOffset < 0 { return committedDays }
        let calendar = Calendar.current
        return Set(
            supabase.myProposals
                .filter { supabase.myResponses[$0.id] == .accepted && supabase.isConfirmedWorkout($0.id) }
                .map { calendar.startOfDay(for: $0.proposal.startsAt) }
        )
        .intersection(committedDays)
    }

    private var heroCard: some View {
        VStack(spacing: 26) {
            HStack {
                Button {
                    Motion.run { weekOffset -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .glassButton(circle: true)
                .buttonBorderShape(.circle)
                .disabled(weekOffset <= -Self.maxWeeksBack)

                Spacer()

                VStack(spacing: 1) {
                    Text(weekTitle)
                        .font(.display(.headline))
                    Text((weekInterval.start ..< weekInterval.end.addingTimeInterval(-1)).formatted(.interval.month(.abbreviated).day()))
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                }
                .gymshipAnimation(value: weekOffset)

                Spacer()

                Button {
                    Motion.run { weekOffset += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .glassButton(circle: true)
                .buttonBorderShape(.circle)
                .disabled(weekOffset >= 1)
            }

            WeekRingView(
                weekStart: weekStart,
                committed: committedDays,
                locked: lockedDays,
                goal: weeklyGoal,
                selectedDay: selectedDay
            ) { day in
                Motion.run {
                    selectedDay = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } == true ? nil : day
                }
            }
            .frame(maxWidth: 344)

            HStack {
                Label("Weekly goal", systemImage: "target")
                    .font(.display(.body, .semibold))
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        weeklyGoal = max(1, weeklyGoal - 1)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .glassButton(circle: true)
                    .buttonBorderShape(.circle)
                    .disabled(weeklyGoal <= 1)

                    Text("\(weeklyGoal)×")
                        .font(.display(.title3))
                        .frame(minWidth: 34)
                        .gymshipNumericText(Double(weeklyGoal))

                    Button {
                        weeklyGoal = min(7, weeklyGoal + 1)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .glassButton(circle: true)
                    .buttonBorderShape(.circle)
                    .disabled(weeklyGoal >= 7)
                }
                .gymshipAnimation(value: weeklyGoal)
            }
            .padding(.leading, 20)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 36)
        }
        .sensoryFeedback(.selection, trigger: weekOffset)
        .sensoryFeedback(.selection, trigger: weeklyGoal)
    }

    // MARK: Sessions

    private var sessions: [ProposalWithGroup] {
        let calendar = Calendar.current
        return supabase.myProposals
            .filter { weekInterval.contains($0.proposal.startsAt) }
            .filter { item in selectedDay.map { calendar.isDate(item.proposal.startsAt, inSameDayAs: $0) } ?? true }
            .sorted { $0.proposal.startsAt < $1.proposal.startsAt }
    }

    private var hasLockedSessions: Bool {
        supabase.myProposals.contains {
            supabase.myResponses[$0.id] == .accepted && supabase.isConfirmedWorkout($0.id)
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: selectedDay.map { $0.formatted(.dateTime.weekday(.wide).day()) } ?? String(localized: "Sessions"),
                subtitle: selectedDay == nil ? String(localized: "Say you're in — two people locks it") : nil
            ) {
                if selectedDay != nil {
                    Button("Show all") { Motion.run { selectedDay = nil } }
                        .font(.system(.footnote, weight: .semibold))
                } else if hasLockedSessions {
                    Button {
                        Task { await syncSchedule() }
                    } label: {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Label("Add to calendar", systemImage: "calendar.badge.plus")
                                .font(.system(.footnote, weight: .semibold))
                        }
                    }
                    .disabled(isSyncing)
                }
            }

            if sessions.isEmpty {
                HintTile(
                    symbol: weekOffset < 0 ? "clock.arrow.circlepath" : "person.3",
                    text: weekOffset < 0
                        ? String(localized: "Past sessions aren't kept — the dial shows the days you trained.")
                        : String(localized: "Nothing proposed yet. Open a crew and find a time.")
                )
            } else {
                SessionListView(coordinator: coordinator, items: sessions)
            }
        }
    }

    // MARK: Solo

    private var soloSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Solo slots"), subtitle: String(localized: "Picked from your own free time")) {
                Menu {
                    Picker("Length", selection: $durationMinutes) {
                        Text("1 hr").tag(60)
                        Text("1.5 hrs").tag(90)
                        Text("2 hrs").tag(120)
                    }
                } label: {
                    Label(durationLabel, systemImage: "timer")
                        .font(.system(.footnote, weight: .semibold))
                }
            }

            if confirmedCount >= weeklyGoal {
                HintTile(symbol: "sparkles", text: String(localized: "You've hit your goal this week. Nice work."))
            } else if isComputing && suggestions.isEmpty {
                HintTile(symbol: "hourglass", text: String(localized: "Looking through your week…"))
            } else if suggestions.isEmpty {
                HintTile(symbol: "moon.zzz", text: String(localized: "No free block that long is left this week."))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            ForEach(suggestions, id: \.self) { candidate in
                                soloChip(candidate)
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
                .padding(.horizontal, -Metrics.gutter)
                .scrollClipDisabled()
            }
        }
    }

    private var durationLabel: String {
        durationMinutes % 60 == 0
            ? String(localized: "\(durationMinutes / 60) hr")
            : String(localized: "\(Double(durationMinutes) / 60) hr")
    }

    private func soloChip(_ candidate: WorkoutSlotFinder.Candidate) -> some View {
        let added = addedCandidates.contains(candidate)
        let start = candidate.interval.start
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(start.formatted(.dateTime.weekday(.abbreviated).day()).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(theme.accent)
                Text(start.formatted(date: .omitted, time: .shortened))
                    .font(.display(.title2))
            }
            Button {
                Task { await addToCalendar(candidate) }
            } label: {
                Label(added ? String(localized: "Added") : String(localized: "Add"), systemImage: added ? "checkmark" : "plus")
                    .font(.display(.footnote, .semibold))
                    .frame(maxWidth: .infinity)
            }
            .glassButton()
            .disabled(added)
        }
        .padding(16)
        .frame(width: 156)
        .glassSurface(Metrics.concentric(minimum: 26))
        .sensoryFeedback(.success, trigger: added)
    }

    // MARK: Loading

    private func loadAll(includingSolo: Bool) async {
        errorMessage = nil
        do {
            try await supabase.refreshHomeData()
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        await loadWeek()
        if includingSolo {
            await recompute()
            didComputeSolo = true
        }
    }

    /// Cancels any in-flight refresh and starts a new one — so flicking
    /// through several weeks quickly can't let a stale response land after a
    /// newer one and clobber what's on screen.
    private func refresh(_ work: @escaping () async -> Void) {
        refreshTask?.cancel()
        refreshTask = Task { await work() }
    }

    private func loadWeek() async {
        do {
            committedDays = try await supabase.fetchMyCommittedDays(in: weekInterval)
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        refreshConfirmedCount()
    }

    /// Updates the dial's count without rerunning Apple Intelligence.
    private func refreshConfirmedCount() {
        guard weekOffset == 0 else { return }
        let weekRange = EventKitManager.currentWeekInterval()
        confirmedCount = supabase.myProposals.filter {
            weekRange.contains($0.proposal.startsAt)
                && supabase.myResponses[$0.id] == .accepted
                && supabase.isConfirmedWorkout($0.id)
        }.count
        if confirmedCount >= weeklyGoal { suggestions = [] }
    }

    /// Recomputes solo suggestions for the current week (busy time is only
    /// read for this week — the solo section itself only ever shows for
    /// `weekOffset == 0`, so there's nothing to compute while browsing other
    /// weeks).
    private func recompute() async {
        guard eventKitManager.isAuthorized, weekOffset == 0 else { return }
        guard !Task.isCancelled else { return }
        isComputing = true
        defer { isComputing = false }

        let weekRange = EventKitManager.currentWeekInterval()
        let confirmedThisWeek = supabase.myProposals.filter {
            weekRange.contains($0.proposal.startsAt)
                && supabase.myResponses[$0.id] == .accepted
                && supabase.isConfirmedWorkout($0.id)
        }
        confirmedCount = confirmedThisWeek.count

        let remaining = max(0, weeklyGoal - confirmedCount)
        guard remaining > 0 else {
            suggestions = []
            return
        }

        await eventKitManager.refreshBusySlotsForCurrentWeek()
        let busyIntervals = eventKitManager.busySlots.map { DateInterval(start: $0.start, end: $0.end) }
        let occupiedDays = Set(confirmedThisWeek.map { Calendar.current.startOfDay(for: $0.proposal.startsAt) })

        var candidatesByDay = WorkoutSlotFinder.freeCandidates(
            in: weekRange,
            duration: TimeInterval(durationMinutes * 60),
            busySlots: busyIntervals
        )
        for day in occupiedDays {
            candidatesByDay.removeValue(forKey: day)
        }

        let picks = await WorkoutSlotFinder.pickBestPerDay(candidatesByDay: candidatesByDay)
        guard !Task.isCancelled else { return }
        suggestions = picks
            .sorted { $0.key < $1.key }
            .prefix(remaining)
            .map(\.value.candidate)
    }

    // MARK: Actions

    private func addToCalendar(_ candidate: WorkoutSlotFinder.Candidate) async {
        do {
            try await eventKitManager.writeWorkoutSlot(
                WorkoutSlot(title: String(localized: "Solo workout"), start: candidate.interval.start, end: candidate.interval.end)
            )
            addedCandidates.insert(candidate)
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }

    /// Writes every locked-in workout to the dedicated Gymship calendar.
    private func syncSchedule() async {
        isSyncing = true
        syncMessage = nil
        errorMessage = nil
        defer { isSyncing = false }
        do {
            let confirmed = supabase.myProposals.filter {
                supabase.myResponses[$0.id] == .accepted && supabase.isConfirmedWorkout($0.id)
            }
            let items = confirmed.map {
                EventKitManager.ScheduledWorkout(
                    proposalId: $0.id,
                    title: String(localized: "Workout with \($0.groupName)"),
                    start: $0.proposal.startsAt,
                    end: $0.proposal.endsAt
                )
            }
            try await eventKitManager.syncWorkoutSchedule(items)
            syncMessage = String(localized: "Added ^[\(confirmed.count) workout](inflect: true) to your Gymship calendar.")
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }
}
