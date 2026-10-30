import Foundation

/// The tester's guide: what Gymship is, and the flows worth trying. Shown
/// once after onboarding, and reachable any time from You — a friend added
/// as a TestFlight tester should be able to open the app and immediately
/// know what to poke at.
enum WhatToTest {
    struct Step: Identifiable {
        let symbol: String
        let title: String
        let detail: String

        var id: String { title }
    }

    static let intro = String(localized: "Gymship finds the free time you share with your crew and turns it into a workout — no group chat back-and-forth.")

    static let steps: [Step] = [
        Step(symbol: "calendar.badge.clock", title: String(localized: "Sync your calendar"),
             detail: String(localized: "In You → Availability, mark which calendars count as busy. Nothing about *why* you're busy ever leaves your phone.")),
        Step(symbol: "person.badge.plus", title: String(localized: "Start or join a crew"),
             detail: String(localized: "Make a crew and send your invite code, or join a friend's from You → Start or join a crew. Up to five people.")),
        Step(symbol: "checkmark.seal.fill", title: String(localized: "Say you're in"),
             detail: String(localized: "Once your crew's synced, tap a proposed session and hit I'm in. A second person joining locks the workout for everyone.")),
        Step(symbol: "car.fill", title: String(localized: "Plan the ride"),
             detail: String(localized: "On a locked session, tap Plan the ride to pick a driver and see when everyone should leave.")),
        Step(symbol: "target", title: String(localized: "Watch your week fill in"),
             detail: String(localized: "The Plan tab's dial tracks your weekly goal, and suggests solo sessions to fill the gaps your crew can't.")),
        Step(symbol: "circle.lefthalf.filled", title: String(localized: "Try high contrast & fonts"),
             detail: String(localized: "In You, flip High contrast for an all black-and-white look, or switch between rounded and standard type.")),
    ]

    static let feedbackNote = String(localized: "Found something broken or confusing? Shake your phone to send feedback straight from TestFlight — screenshots included.")
}
