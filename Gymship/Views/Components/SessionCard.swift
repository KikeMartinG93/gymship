import SwiftUI

// MARK: - Card

/// One proposed workout, laid out like a ticket: a date leaf, the time, who's
/// in, and a single call to action. When two or more people are in, it turns
/// into a "locked in" session, tinted with the accent, with a ride button.
struct SessionCard: View {
    @Environment(ThemeManager.self) private var theme

    let item: ProposalWithGroup
    let status: ResponseStatus
    var showGroupName = true
    var committed: [Profile] = []
    var isConfirmed = false
    let onRespond: (ResponseStatus) -> Void
    var onPlanRide: (() -> Void)?

    private var start: Date { item.proposal.startsAt }
    private var end: Date { item.proposal.endsAt }
    private var isIn: Bool { status == .accepted }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                dateLeaf

                VStack(alignment: .leading, spacing: 4) {
                    Text(timeRange)
                        .font(.display(.title3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    subtitle
                }

                Spacer(minLength: 0)

                if isConfirmed {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(.title2))
                        .foregroundStyle(theme.accent)
                        .symbolBounceIfAllowed(value: isConfirmed)
                }
            }

            HStack(spacing: 12) {
                if !committed.isEmpty {
                    AvatarStack(names: committed.map(\.name), size: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(crewNames)
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(1)
                    Text(crewStatus)
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                action
                    .fixedSize()
                    .layoutPriority(2)
            }

            if isConfirmed, let onPlanRide {
                Button(action: onPlanRide) {
                    Label("Plan the ride", systemImage: "car.fill")
                        .font(.display(.subheadline, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .glassButton()
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 30, tint: isConfirmed ? theme.accent.opacity(0.30) : nil)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: status)
        .sensoryFeedback(.success, trigger: isConfirmed)
    }

    // MARK: Pieces

    private var dateLeaf: some View {
        VStack(spacing: 0) {
            Text(start.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundStyle(theme.accent)
            Text(start.formatted(.dateTime.day()))
                .font(.display(26))
        }
        .frame(width: 54, height: 58)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var subtitle: some View {
        HStack(spacing: 6) {
            if item.proposal.isSuggested {
                Label("AI pick", systemImage: "sparkles")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(theme.accent)
            }
            Text(subtitleText)
                .foregroundStyle(.secondary)
        }
        .font(.system(.footnote, weight: .medium))
        .lineLimit(1)
    }

    private var subtitleText: String {
        var parts: [String] = []
        if showGroupName { parts.append(item.groupName) }
        if !item.proposal.isSuggested { parts.append(item.proposal.title) }
        parts.append(durationText)
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var action: some View {
        if isIn {
            Menu {
                Button("Step out", systemImage: "xmark", role: .destructive) { onRespond(.declined) }
            } label: {
                Label("In", systemImage: "checkmark")
                    .font(.display(.subheadline))
                    .padding(.horizontal, 4)
            }
            .glassButton()
        } else {
            Button("I'm in") { onRespond(.accepted) }
                .buttonStyle(PillButtonStyle())
        }
    }

    // MARK: Text

    private var timeRange: String {
        let startText = start.formatted(date: .omitted, time: .shortened)
        let endText = end.formatted(date: .omitted, time: .shortened)
        return "\(startText) – \(endText)"
    }

    private var durationText: String {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        if minutes % 60 == 0 { return String(localized: "\(minutes / 60) hr") }
        if minutes > 60 { return String(localized: "\(String(format: "%.1f", Double(minutes) / 60)) hr") }
        return String(localized: "\(minutes) min")
    }

    private var firstNames: [String] {
        committed.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
    }

    /// "Andrea", "Andrea & Sam", "Andrea, Sam +2" — always fits on one line.
    private var crewNames: String {
        switch firstNames.count {
        case 0: return String(localized: "Nobody yet")
        case 1: return firstNames[0]
        case 2: return "\(firstNames[0]) & \(firstNames[1])"
        default: return "\(firstNames[0]), \(firstNames[1]) +\(firstNames.count - 2)"
        }
    }

    private var crewStatus: String {
        switch (committed.count, isConfirmed) {
        case (0, _): return String(localized: "Be the first in")
        case (_, true): return String(localized: "Locked in")
        default: return String(localized: "One more locks it")
        }
    }
}

// MARK: - Shared behavior

/// Handles "I'm in" and the overlapping-workout conflict flow, plus which
/// sheets (conflict resolver, ride plan) are up. Shared by every screen that
/// shows sessions so the behavior is identical everywhere.
@Observable
@MainActor
final class SessionCoordinator {
    var conflict: ProposalConflict?
    var ridePlanItem: ProposalWithGroup?
    var errorMessage: String?

    private let supabase = SupabaseService.shared

    func respond(_ item: ProposalWithGroup, status: ResponseStatus) async {
        errorMessage = nil
        if status == .accepted, let existing = supabase.acceptedConflict(for: item) {
            conflict = ProposalConflict(candidate: item, existing: existing)
            return
        }
        do {
            try await supabase.respond(to: item.proposal, status: status)
            try await supabase.fetchCommitments(forProposalIds: [item.id])
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }

    func resolve(attend: ProposalWithGroup, skip: ProposalWithGroup) async {
        do {
            try await supabase.respond(to: skip.proposal, status: .declined)
            try await supabase.respond(to: attend.proposal, status: .accepted)
            try await supabase.fetchCommitments(forProposalIds: [skip.id, attend.id])
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }
}

/// A vertical stack of `SessionCard`s wired to the coordinator.
struct SessionListView: View {
    @Environment(SupabaseService.self) private var supabase
    @Bindable var coordinator: SessionCoordinator

    let items: [ProposalWithGroup]
    var showGroupName = true

    var body: some View {
        VStack(spacing: 14) {
            ForEach(items) { item in
                SessionCard(
                    item: item,
                    status: supabase.myResponses[item.id] ?? .pending,
                    showGroupName: showGroupName,
                    committed: supabase.commitments[item.id] ?? [],
                    isConfirmed: supabase.isConfirmedWorkout(item.id),
                    onRespond: { status in
                        Task { await coordinator.respond(item, status: status) }
                    },
                    onPlanRide: { coordinator.ridePlanItem = item }
                )
            }
        }
    }
}

/// Presents the conflict resolver and ride planner for a coordinator.
private struct SessionSheets: ViewModifier {
    @Environment(SupabaseService.self) private var supabase
    @Bindable var coordinator: SessionCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(item: $coordinator.conflict) { conflict in
                ConflictResolutionView(conflict: conflict) { attend, skip in
                    Task { await coordinator.resolve(attend: attend, skip: skip) }
                }
            }
            .sheet(item: $coordinator.ridePlanItem) { item in
                if let group = supabase.myGroups.first(where: { $0.id == item.proposal.groupId }) {
                    RidePlanView(group: group, item: item)
                }
            }
    }
}

extension View {
    func sessionSheets(_ coordinator: SessionCoordinator) -> some View {
        modifier(SessionSheets(coordinator: coordinator))
    }
}
