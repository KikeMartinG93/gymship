import SwiftUI

/// Top-level app state tying together the EventKit and Supabase layers.
@Observable
@MainActor
final class AppState {
    let eventKitManager = EventKitManager()
    let supabaseService = SupabaseService.shared

    /// Lives here (not in the tab view) so it survives an interface rebuild.
    var selectedTab: AppTab = .plan

    var isOnboarded: Bool = UserDefaults.standard.bool(forKey: "gymship.isOnboarded") {
        didSet {
            UserDefaults.standard.set(isOnboarded, forKey: "gymship.isOnboarded")
        }
    }
}
