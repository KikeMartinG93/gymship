import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(SupabaseService.self) private var supabase
    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// The newest TestFlight build whose notes this device has already shown.
    @AppStorage("gymship.lastSeenBuild") private var lastSeenBuild = 0
    /// Whether this device has already seen the tester's guide.
    @AppStorage("gymship.hasSeenWhatToTest") private var hasSeenWhatToTest = false
    @State private var pendingReleases: [ReleaseNotes.Release] = []
    @State private var isShowingWhatToTest = false
    @State private var isShowingWhatsNew = false

    var body: some View {
        ZStack {
            GymshipBackground()

            if appState.isOnboarded {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(theme.appearance.preferredColorScheme)
        .gymshipAnimation(Motion.screen, value: appState.isOnboarded)
        .onAppear { theme.sync(from: colorScheme) }
        .onChange(of: colorScheme) { theme.sync(from: colorScheme) }
        .onChange(of: theme.appearance) { theme.sync(from: colorScheme) }
        .fullScreenCover(isPresented: $isShowingWhatToTest) {
            WhatToTestView {
                hasSeenWhatToTest = true
                isShowingWhatToTest = false
                checkWhatsNew()
            }
        }
        .fullScreenCover(isPresented: $isShowingWhatsNew, onDismiss: {
            lastSeenBuild = ReleaseNotes.currentBuild
            pendingReleases = []
        }) {
            WhatsNewView(releases: pendingReleases) {
                lastSeenBuild = ReleaseNotes.currentBuild
                isShowingWhatsNew = false
            }
        }
        .onChange(of: appState.isOnboarded) { checkFirstRunSplashes() }
        .task {
            checkFirstRunSplashes()
            await supabase.restoreSession()
        }
    }

    /// Right after onboarding, a fresh tester sees the guide first; What's
    /// new only follows once that's dismissed (or immediately, if they've
    /// already seen it on this device).
    private func checkFirstRunSplashes() {
        guard appState.isOnboarded else {
            lastSeenBuild = ReleaseNotes.currentBuild
            return
        }
        if !hasSeenWhatToTest {
            isShowingWhatToTest = true
        } else {
            checkWhatsNew()
        }
    }

    /// Shows the notes for any builds newer than the last one seen — but never
    /// on a fresh install, where onboarding is the introduction.
    private func checkWhatsNew() {
        guard appState.isOnboarded else { return }
        let unseen = ReleaseNotes.unseen(since: lastSeenBuild)
        if !unseen.isEmpty {
            pendingReleases = unseen
            isShowingWhatsNew = true
        }
    }
}

enum AppTab: Hashable {
    case plan, crews, agent, you
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(SupabaseService.self) private var supabase
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            Tab("Plan", systemImage: "calendar.day.timeline.left", value: AppTab.plan, role: .prominent) {
                PlanView()
            }
            Tab("Crews", systemImage: "person.3.fill", value: AppTab.crews) {
                GroupsListView()
            }
            Tab("Agent", systemImage: "sparkles", value: AppTab.agent) {
                AgentView()
            }
            Tab("You", systemImage: "person.crop.circle.fill", value: AppTab.you) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: nextUp != nil && !theme.highContrast) {
            if let nextUp {
                NextUpAccessory(item: nextUp) { appState.selectedTab = .plan }
            }
        }
    }

    /// The soonest upcoming workout you've said you're in for.
    private var nextUp: ProposalWithGroup? {
        supabase.myProposals
            .filter { $0.proposal.startsAt > Date() && supabase.myResponses[$0.id] == .accepted }
            .min { $0.proposal.startsAt < $1.proposal.startsAt }
    }
}

/// The floating strip above the tab bar: what's next, and when.
private struct NextUpAccessory: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(SupabaseService.self) private var supabase
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    let item: ProposalWithGroup
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: supabase.isConfirmedWorkout(item.id) ? "checkmark.seal.fill" : "figure.strengthtraining.traditional")
                    .foregroundStyle(theme.accent)
                if placement == .inline {
                    Text(item.proposal.startsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.display(.subheadline, .semibold))
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Next up · \(item.groupName)")
                            .font(.system(.caption))
                            .foregroundStyle(.secondary)
                        Text(item.proposal.startsAt.formatted(.dateTime.weekday(.wide).hour().minute()))
                            .font(.display(.subheadline, .semibold))
                    }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text(item.proposal.startsAt, style: .relative)
                            .font(.system(.footnote).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
