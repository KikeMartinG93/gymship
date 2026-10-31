import SwiftUI

/// Start a crew, or join one with an invite code — one field, one switch.
struct GroupJoinCreateView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(\.dismiss) private var dismiss

    var onJoined: ((Group) -> Void)?

    private enum Mode: String, CaseIterable, Identifiable {
        case create = "Start a crew"
        case join = "Join a crew"
        var id: String { rawValue }

        var label: String {
            switch self {
            case .create: String(localized: "Start a crew")
            case .join: String(localized: "Join a crew")
            }
        }
    }

    @State private var mode: Mode = .create
    @State private var groupName = ""
    @State private var inviteCode = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isBusy && (mode == .create ? !groupName.isEmpty : !inviteCode.isEmpty)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                SegmentedChoice(
                    title: String(localized: "Mode"),
                    selection: $mode,
                    options: Mode.allCases.map { ($0, $0.label) }
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(mode == .create ? "Name your crew" : "Enter the invite code")
                        .font(.display(30))
                    Text(mode == .create
                         ? "You'll get an invite code to share with up to four friends."
                         : "Ask a friend for their crew's code — it's on their Crews tab.")
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
}

                if mode == .create {
                    TextField("Crew name", text: $groupName)
                        .glassTextFieldStyle()
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                } else {
                    TextField("Invite code", text: $inviteCode)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .glassTextFieldStyle()
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }

                if let errorMessage {
                    InlineMessage(text: errorMessage, isError: true)
                }

                Spacer()

                Button {
                    Task { await submit() }
                } label: {
                    if isBusy { ProgressView() } else { Text(mode == .create ? "Create crew" : "Join crew") }
                }
                .buttonStyle(GymshipButtonStyle())
                .disabled(!canSubmit)
            }
            .padding(Metrics.gutter)
            .gymshipAnimation(value: mode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                .flatInHighContrast()
            }
        }
        .presentationDetents([.medium, .large])
        .highContrastSheetBackground()
    }

    private func submit() async {
        guard canSubmit else { return }
        isBusy = true
        errorMessage = nil
        do {
            let group: Group
            switch mode {
            case .create: group = try await supabase.createGroup(name: groupName)
            case .join: group = try await supabase.joinGroup(withInviteCode: inviteCode)
            }
            onJoined?(group)
            dismiss()
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        isBusy = false
    }
}
