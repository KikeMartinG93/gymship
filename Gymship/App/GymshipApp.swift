import SwiftUI

@main
struct GymshipApp: App {
    @State private var appState = AppState()
    @State private var theme = ThemeManager.shared
    @State private var power = PowerState()

    init() {
        Typography.applyToUIKitChrome(rounded: ThemeManager.shared.usesRoundedFont)
        #if DEBUG
        if CommandLine.arguments.contains("-GymshipDemo") {
            UserDefaults.standard.set(true, forKey: "gymship.isOnboarded")
            MainActor.assumeIsolated { SupabaseService.shared.loadDemoData() }
        }
        // Lets the live font switch be checked without touch input.
        if CommandLine.arguments.contains("-GymshipAutoToggleFont") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                ThemeManager.shared.usesRoundedFont.toggle()
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(appState.eventKitManager)
                .environment(appState.supabaseService)
                .environment(theme)
                .environment(power)
                .environment(\.isLowPowerModeEnabled, power.isLowPowerModeEnabled)
                .tint(theme.accent)
                .fontDesign(Typography.design(rounded: theme.usesRoundedFont))
                // UIKit-drawn chrome only picks up a new font on a fresh bar,
                // so a change rebuilds the interface (the tab is preserved).
                .id(theme.usesRoundedFont)
        }
    }
}
