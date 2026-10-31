import SwiftUI

/// Pairs two overlapping proposals so a conflict sheet can be presented with
/// `.sheet(item:)`.
struct ProposalConflict: Identifiable {
    let candidate: ProposalWithGroup
    let existing: ProposalWithGroup

    var id: UUID { candidate.id }
}

/// Shown when saying "I'm in" would overlap a workout you already accepted
/// elsewhere — pick which one you're actually going to.
struct ConflictResolutionView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let conflict: ProposalConflict
    let onChoose: (_ attend: ProposalWithGroup, _ skip: ProposalWithGroup) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("Double booked")
                        .font(.display(30))
                    Text("These two overlap. Which one are you going to?")
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                option(conflict.existing, isCurrent: true) {
                    onChoose(conflict.existing, conflict.candidate)
                    dismiss()
                }

                Text("or")
                    .font(.display(.footnote, .semibold))
                    .foregroundStyle(.secondary)

                option(conflict.candidate, isCurrent: false) {
                    onChoose(conflict.candidate, conflict.existing)
                    dismiss()
                }

                Spacer(minLength: 0)
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
        .presentationDetents([.medium])
        .highContrastSheetBackground()
    }

    private func option(_ item: ProposalWithGroup, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text(item.proposal.startsAt.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(theme.accent)
                    Text(item.proposal.startsAt.formatted(.dateTime.day()))
                        .font(.display(26))
                }
                .frame(width: 54, height: 58)
                .background(theme.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.groupName)
                        .font(.display(.headline))
                    Text("\(item.proposal.startsAt.formatted(date: .omitted, time: .shortened)) – \(item.proposal.endsAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Text("Going")
                        .font(.system(.caption, weight: .bold))
                        .glassPill(tint: .green)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 26, tint: isCurrent ? theme.accent.opacity(0.22) : nil)
        }
        .buttonStyle(.plain)
    }
}
