import SwiftUI

/// One crew: who's in it (and who's synced), the shared workout length, the
/// AI-suggested slots, and anything the crew proposed by hand.
struct GroupDetailView: View {
    let group: Group

    @Environment(SupabaseService.self) private var supabase
    @Environment(ThemeManager.self) private var theme

    @State private var coordinator = SessionCoordinator()

    @State private var currentGroup: Group
    @State private var isShowingPropose = false
    @State private var isFindingBestTimes = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    init(group: Group) {
        self.group = group
        _currentGroup = State(initialValue: group)
    }

    private var sessions: [ProposalWithGroup] {
        supabase.myProposals
            .filter { $0.proposal.groupId == group.id }
            .sorted { $0.proposal.startsAt < $1.proposal.startsAt }
    }

    private var submittedMemberIds: Set<UUID> {
        Set(supabase.groupBusySlots.map(\.userId))
    }

    private var allMembersSubmitted: Bool {
        !supabase.groupMembers.isEmpty && supabase.groupMembers.allSatisfy { submittedMemberIds.contains($0.id) }
    }

    /// Crewmates who still need to open the app and push busy slots — not you.
    private var membersNeedingSync: [Profile] {
        supabase.groupMembers.filter {
            !submittedMemberIds.contains($0.id) && $0.id != supabase.currentUserId
        }
    }

    private var nudgeFirstNames: [String] {
        membersNeedingSync.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
    }

    private var nudgeMessage: String {
        let names = nudgeFirstNames.formatted(.list(type: .and))
        return String(localized: "Hey \(names) — open Gymship and sync your calendar so we can pick a time for \"\(group.name)\".")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                crewCard
                syncSection
                    .padding(.top, 28)
                sessionsSection
                    // Nudge sits on the Sessions row — pull it a touch closer to the
                    // waiting card so the new trailing control doesn't float.
                    .padding(.top, membersNeedingSync.isEmpty ? 28 : 20)

                if let message = errorMessage ?? coordinator.errorMessage {
                    InlineMessage(text: message, isError: true)
                        .padding(.top, 28)
                }
                if let infoMessage {
                    InlineMessage(text: infoMessage)
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Propose a workout", systemImage: "plus") { isShowingPropose = true }
            }
                .flatInHighContrast()
        }
        .sheet(isPresented: $isShowingPropose) {
            ProposeWorkoutSheet(groupId: group.id, defaultMinutes: currentGroup.workoutDurationMinutes)
        }
        .sessionSheets(coordinator)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: Crew

    private var crewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(group.name)
                .font(.display(.title2))
                .lineLimit(1)
            HStack {
                Text("\(supabase.groupMembers.count) of \(Group.maxMembers) members")
                    .font(.display(.subheadline, .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ShareLink(
                    item: String(localized: "Join my Gymship crew \"\(group.name)\" — invite code \(group.inviteCode)")
                ) {
                    Label(group.inviteCode, systemImage: "square.and.arrow.up")
                        .font(.system(.footnote, design: .monospaced, weight: .bold))
                }
                .glassButton()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(supabase.groupMembers) { member in
                        let synced = submittedMemberIds.contains(member.id)
                        VStack(spacing: 8) {
                            Avatar(name: member.name, size: 56, ring: synced ? .green : nil)
                            Text(member.name.split(separator: " ").first.map(String.init) ?? member.name)
                                .font(.system(.footnote, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(width: 64)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .scrollClipDisabled()

            HStack {
                Label("Session length", systemImage: "timer")
                    .font(.display(.subheadline, .semibold))
                Spacer()
                SegmentedChoice(
                    title: String(localized: "Length"),
                    selection: durationBinding,
                    options: [(60, String(localized: "1 hr")), (120, String(localized: "2 hr")), (150, String(localized: "2.5 hr"))]
                )
                .frame(maxWidth: 190)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 30)
    }

    // MARK: Sync + find

    private var syncSection: some View {
        VStack(spacing: 12) {
            if allMembersSubmitted {
                Button {
                    Task { await findBestTimes(showsFeedback: true) }
                } label: {
                    if isFindingBestTimes {
                        ProgressView()
                    } else {
                        Label("Find best times", systemImage: "sparkles")
                    }
                }
                .buttonStyle(GymshipButtonStyle())
                .disabled(isFindingBestTimes)

                Text("Everyone's synced. Apple Intelligence picks a \(currentGroup.workoutDurationMinutes.formattedDuration) slot for each free day.")
                    .font(.system(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                let waitingOn = supabase.groupMembers
                    .filter { !submittedMemberIds.contains($0.id) }
                    .map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "hourglass")
                        .font(.system(.title3))
                        .foregroundStyle(theme.accent)
                        .padding(.top, 1)
                    Text(waitingOn.isEmpty
                         ? "Syncing everyone's calendars…"
                         : "Waiting on \(waitingOn.formatted(.list(type: .and))) to open Gymship and sync their calendar.")
                        .font(.system(.subheadline))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .glassCard(cornerRadius: 24)
            }
        }
    }

    // MARK: Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: membersNeedingSync.isEmpty ? 12 : 14) {
            SectionHeader(
                title: String(localized: "Sessions"),
                subtitle: String(localized: "Two people in locks a workout")
            ) {
                if !membersNeedingSync.isEmpty {
                    ShareLink(item: nudgeMessage) {
                        Label("Nudge", systemImage: "bell.badge")
                            .font(.system(.footnote, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .glassButton()
                    .accessibilityHint(Text("Sends a reminder to \(nudgeFirstNames.formatted(.list(type: .and))) to sync their calendar"))
                }
            }

            if sessions.isEmpty {
                HintTile(symbol: "sparkles", text: String(localized: "No sessions yet. Find best times, or tap + to propose your own."))
            } else {
                SessionListView(coordinator: coordinator, items: sessions, showGroupName: false)
            }
        }
    }

    // MARK: Logic

    private var durationBinding: Binding<Int> {
        Binding(
            get: { currentGroup.workoutDurationMinutes },
            set: { newValue in
                currentGroup.workoutDurationMinutes = newValue
                Task {
                    try? await supabase.updateGroupDuration(groupId: group.id, minutes: newValue)
                }
            }
        )
    }

    private func refresh() async {
        do {
            try await supabase.fetchGroupMembers(groupId: group.id)
            try await supabase.fetchGroupBusySlots(groupId: group.id)
            try await supabase.refreshMyProposals()
            try await supabase.fetchCommitments(forProposalIds: sessions.map(\.id))
            if let refreshed = supabase.myGroups.first(where: { $0.id == group.id }) {
                currentGroup = refreshed
            }
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }

    private func findBestTimes(showsFeedback: Bool) async {
        isFindingBestTimes = true
        errorMessage = nil
        infoMessage = nil
        do {
            try await supabase.fetchGroupBusySlots(groupId: group.id)
            let busyIntervals = supabase.groupBusySlots.map { DateInterval(start: $0.startsAt, end: $0.endsAt) }
            let weekRange = EventKitManager.currentWeekInterval()
            let duration = TimeInterval(currentGroup.workoutDurationMinutes * 60)

            var candidatesByDay = WorkoutSlotFinder.freeCandidates(in: weekRange, duration: duration, busySlots: busyIntervals)
            let hadAnyFreeTime = !candidatesByDay.isEmpty

            // Days that already have a suggestion don't need Apple
            // Intelligence run on them again — this is called on every pull-
            // to-refresh once everyone's synced, so skipping them up front
            // (rather than discarding their picks afterward) keeps a refresh
            // that finds nothing new from spinning up on-device model calls.
            let existingSuggestedDays = Set(
                sessions.filter { $0.proposal.isSuggested }.map { Calendar.current.startOfDay(for: $0.proposal.startsAt) }
            )
            for day in existingSuggestedDays {
                candidatesByDay.removeValue(forKey: day)
            }

            let newPicks = await WorkoutSlotFinder.pickBestPerDay(candidatesByDay: candidatesByDay)

            for (_, pick) in newPicks.sorted(by: { $0.key < $1.key }) {
                // If another member's device already suggested this day, the
                // insert is rejected rather than adding a second, possibly
                // different suggestion — the crew converges on one slot.
                try await supabase.createSuggestedProposal(
                    groupId: group.id,
                    title: String(localized: "Suggested workout"),
                    startsAt: pick.candidate.interval.start,
                    endsAt: pick.candidate.interval.end
                )
            }

            try await supabase.refreshMyProposals()

            if showsFeedback {
                if !hadAnyFreeTime {
                    infoMessage = String(localized: "No shared free time of that length was found this week.")
                } else if newPicks.isEmpty {
                    infoMessage = String(localized: "You're up to date — no new days to suggest.")
                }
            }
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        isFindingBestTimes = false
    }
}

// MARK: - Propose sheet

private struct ProposeWorkoutSheet: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(\.dismiss) private var dismiss

    let groupId: UUID
    let defaultMinutes: Int

    @State private var title = String(localized: "Workout")
    @State private var startDate = Date().addingTimeInterval(3600)
    @State private var minutes: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(groupId: UUID, defaultMinutes: Int) {
        self.groupId = groupId
        self.defaultMinutes = defaultMinutes
        _minutes = State(initialValue: defaultMinutes)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text("Propose a workout")
                    .font(.display(30))

                TextField("What are you doing?", text: $title)
                    .glassTextFieldStyle()

                DatePicker("Starts", selection: $startDate, in: Date()...)
                    .font(.display(.subheadline, .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassCard(cornerRadius: 18)

                SegmentedChoice(
                    title: String(localized: "Duration"),
                    selection: $minutes,
                    options: [(30, String(localized: "30 min")), (60, String(localized: "1 hr")), (90, String(localized: "1.5 hr")), (120, String(localized: "2 hr"))]
                )

                if let errorMessage {
                    InlineMessage(text: errorMessage, isError: true)
                }

                Spacer()

                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Propose") }
                }
                .buttonStyle(GymshipButtonStyle())
                .disabled(isSaving || title.isEmpty)
            }
            .padding(Metrics.gutter)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                .flatInHighContrast()
            }
        }
        .presentationDetents([.large])
        .highContrastSheetBackground()
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            try await supabase.createProposal(
                groupId: groupId,
                title: title,
                startsAt: startDate,
                endsAt: startDate.addingTimeInterval(TimeInterval(minutes * 60))
            )
            try await supabase.refreshMyProposals()
            dismiss()
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        isSaving = false
    }
}

private extension Int {
    /// Formats a minute count like `120` as "2 hr".
    var formattedDuration: String {
        let hours = Double(self) / 60
        if hours == hours.rounded() {
            return String(localized: "\(Int(hours)) hr")
        }
        let formatted = String(format: "%.1f", hours)
        return String(localized: "\(formatted) hr")
    }
}
