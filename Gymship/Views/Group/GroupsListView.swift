import SwiftUI

/// Your crews: one big card each, with what's next for that crew.
struct GroupsListView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(ThemeManager.self) private var theme

    @State private var isShowingJoinCreate = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if supabase.myGroups.isEmpty {
                        EmptyStateView(
                            symbol: "person.3.sequence.fill",
                            title: String(localized: "Find your crew"),
                            message: String(localized: "Start a crew or join a friend's with their invite code. Gymship finds the time you're all free.")
                        ) {
                            Button("Start or join a crew") { isShowingJoinCreate = true }
                                .buttonStyle(GymshipButtonStyle())
                                .padding(.top, 4)
                        }
                        .glassCard(cornerRadius: 34)
                    } else {
                        ForEach(supabase.myGroups) { group in
                            NavigationLink {
                                GroupDetailView(group: group)
                            } label: {
                                CrewCard(group: group, next: nextSession(for: group))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let errorMessage {
                        InlineMessage(text: errorMessage, isError: true)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 32)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New crew", systemImage: "plus") { isShowingJoinCreate = true }
                }
                .flatInHighContrast()
            }
            .sheet(isPresented: $isShowingJoinCreate) {
                GroupJoinCreateView { _ in
                    Task { await refresh() }
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    private func nextSession(for group: Group) -> ProposalWithGroup? {
        supabase.myProposals
            .filter { $0.proposal.groupId == group.id && $0.proposal.startsAt > Date() }
            .min { $0.proposal.startsAt < $1.proposal.startsAt }
    }

    private func refresh() async {
        do {
            try await supabase.refreshHomeData()
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }
}

private struct CrewCard: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(ThemeManager.self) private var theme

    let group: Group
    let next: ProposalWithGroup?

    var body: some View {
        HStack(spacing: 16) {
            crest

            VStack(alignment: .leading, spacing: 6) {
                Text(group.name)
                    .font(.display(.title3))
                    .lineLimit(1)

                if let next {
                    HStack(spacing: 6) {
                        Image(systemName: supabase.isConfirmedWorkout(next.id) ? "checkmark.seal.fill" : "clock")
                            .foregroundStyle(theme.accent)
                        Text("Next · \(next.proposal.startsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    }
                    .font(.system(.footnote, weight: .medium))
                } else {
                    Text("No sessions yet")
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                }

                Text(group.inviteCode)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .glassCard(cornerRadius: 30)
    }

    /// A big rounded monogram, painted from the selected theme.
    private var crest: some View {
        let shift = Avatar.hueShift(for: group.name)
        let fills = theme.iconFill(shift: shift)
        return Text(Avatar.initials(for: group.name))
            .font(.display(24))
            .foregroundStyle(theme.ink(on: fills[0]))
            .frame(width: 60, height: 60)
            .background(
                theme.iconGradient(shift: shift),
                in: Metrics.concentric(minimum: 18)
            )
            .overlay(Metrics.concentric(minimum: 18).stroke(.white.opacity(0.25), lineWidth: 1))
    }
}
