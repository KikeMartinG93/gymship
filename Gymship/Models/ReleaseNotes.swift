import Foundation

/// What changed in each TestFlight build, shown once after an update.
///
/// **Adding a release:** append a `Release` for the new build number *before*
/// uploading it to TestFlight, describing what's different from the previous
/// TestFlight build. Someone who skips a build sees every release they missed.
enum ReleaseNotes {
    enum Kind {
        case new, improved, fixed

        var label: String {
            switch self {
            case .new: String(localized: "New")
            case .improved: String(localized: "Better")
            case .fixed: String(localized: "Fixed")
            }
        }
    }

    struct Item: Identifiable {
        let kind: Kind
        let symbol: String
        let title: String
        let detail: String

        var id: String { title }
    }

    struct Release: Identifiable {
        /// `CFBundleVersion` of the build this describes.
        let build: Int
        /// `CFBundleShortVersionString`.
        let version: String
        let headline: String
        let items: [Item]

        var id: Int { build }
        var versionLabel: String { "\(version) (\(build))" }
    }

    /// Oldest first. Keep every release: people update at different times.
    static let releases: [Release] = [
        Release(
            build: 4,
            version: "1.1.0",
            headline: String(localized: "A whole new look"),
            items: [
                Item(kind: .new, symbol: "calendar.day.timeline.left", title: String(localized: "The week dial"),
                     detail: String(localized: "Your Plan tab is now a dial. Each day fills in when you say you're in, and glows once the workout is locked.")),
                Item(kind: .new, symbol: "figure.strengthtraining.traditional", title: String(localized: "One-tap “I'm in”"),
                     detail: String(localized: "Sessions are tickets now. Tap I'm in, and when a second person joins, the workout locks.")),
                Item(kind: .new, symbol: "car.fill", title: String(localized: "Leave times"),
                     detail: String(localized: "The ride planner shows a map and tells everyone when to leave, or when to be ready for pickup.")),
                Item(kind: .new, symbol: "applelogo", title: String(localized: "Sign in with Apple"),
                     detail: String(localized: "No more Google sign-in. One tap with Apple, and no password.")),
                Item(kind: .improved, symbol: "sparkles", title: String(localized: "Liquid Glass"),
                     detail: String(localized: "New glass surfaces, rounded type throughout, and a color background that slowly drifts. Needs iOS 26.")),
                Item(kind: .improved, symbol: "person.3.fill", title: String(localized: "Crews you can share"),
                     detail: String(localized: "Send your invite code straight from the crew screen.")),
                Item(kind: .fixed, symbol: "wrench.and.screwdriver.fill", title: String(localized: "Launch crash on iOS 27"),
                     detail: String(localized: "The app no longer closes itself on launch on iOS 27.")),
            ]
        ),
        Release(
            build: 5,
            version: "1.1.1",
            headline: String(localized: "Cleaner, and higher contrast"),
            items: [
                Item(kind: .new, symbol: "circle.lefthalf.filled", title: String(localized: "High contrast mode"),
                     detail: String(localized: "Turn it on in You. Pure black and white, with no glass anywhere except the tab bar.")),
                Item(kind: .new, symbol: "textformat", title: String(localized: "Font choice"),
                     detail: String(localized: "Switch between SF Pro Rounded and the standard system font in You.")),
                Item(kind: .new, symbol: "megaphone.fill", title: String(localized: "What's new"),
                     detail: String(localized: "This screen. You'll see it after every update, and you can reopen it any time from You.")),
                Item(kind: .improved, symbol: "circle.circle", title: String(localized: "Today on the dial"),
                     detail: String(localized: "Today is now marked with an outline around its segment instead of a circle behind the number.")),
                Item(kind: .improved, symbol: "circle.dashed", title: String(localized: "A calmer Plan tab"),
                     detail: String(localized: "The week dial floats on the background instead of sitting in a card, with more room around it.")),
                Item(kind: .improved, symbol: "rectangle.stack.fill", title: String(localized: "Roomier session cards"),
                     detail: String(localized: "Who's in and whether it's locked now read at a glance, and the “In” button stops getting squeezed.")),
                Item(kind: .fixed, symbol: "calendar.circle.fill", title: String(localized: "Week dial numbers"),
                     detail: String(localized: "The day numbers now sit inside their segments instead of hanging off the edge.")),
                Item(kind: .fixed, symbol: "exclamationmark.triangle.fill", title: String(localized: "Phantom error banner"),
                     detail: String(localized: "The red “cancellation error” message no longer pops up when a refresh is interrupted.")),
            ]
        ),
        Release(
            build: 6,
            version: "1.1.2",
            headline: String(localized: "Faster, and easier on the eyes"),
            items: [
                Item(kind: .new, symbol: "checklist", title: String(localized: "What to test"),
                     detail: String(localized: "A tester's guide to Gymship, shown once after onboarding and reachable any time from You — with a one-tap way to invite a friend.")),
                Item(kind: .improved, symbol: "circle.lefthalf.filled", title: String(localized: "A softer high contrast"),
                     detail: String(localized: "Less stark: soft tonal surfaces and the system's own switches, instead of hard white outlines and glowing edges.")),
                Item(kind: .improved, symbol: "sparkles", title: String(localized: "Faster AI suggestions"),
                     detail: String(localized: "Solo and crew workout suggestions for the week now compute all at once instead of one day at a time.")),
                Item(kind: .improved, symbol: "car.fill", title: String(localized: "Quicker ride planning"),
                     detail: String(localized: "Everyone's ETA calculates at the same time now, instead of waiting on each person in turn.")),
                Item(kind: .improved, symbol: "square.and.pencil", title: String(localized: "Refined proportions"),
                     detail: String(localized: "A pass over spacing and sizing across the app so it feels more like it was designed by Apple, on every screen size.")),
                Item(kind: .fixed, symbol: "calendar", title: String(localized: "Calendar list"),
                     detail: String(localized: "Birthdays and Holidays no longer show up in the list of calendars you can mark busy.")),
                Item(kind: .fixed, symbol: "checkmark.circle.fill", title: String(localized: "False error on “I'm in”"),
                     detail: String(localized: "Accepting a workout no longer shows an error banner if a background step hiccups — your RSVP still goes through.")),
            ]
        ),
        Release(
            build: 7,
            version: "1.1.2",
            headline: String(localized: "Now in Spanish"),
            items: [
                Item(kind: .new, symbol: "globe", title: String(localized: "Spanish translation"),
                     detail: String(localized: "Gymship now speaks Spanish. It follows your iPhone's language automatically.")),
                Item(kind: .improved, symbol: "textformat", title: String(localized: "Consistent capitalization"),
                     detail: String(localized: "Buttons, titles and alerts now use the same sentence-style capitalization everywhere.")),
                Item(kind: .improved, symbol: "circle.dashed", title: String(localized: "Curved day labels"),
                     detail: String(localized: "The weekday letters and numbers on the week dial now bend gently with the ring.")),
            ]
        ),
        Release(
            build: 8,
            version: "1.1.2",
            headline: String(localized: "Scheduling that fits you"),
            items: [
                Item(kind: .new, symbol: "slider.horizontal.3", title: String(localized: "Preferences"),
                     detail: String(localized: "In You, set hours workouts never go outside of, a preferred time like before 9am or after 10pm, and rest days.")),
            ]
        ),
        Release(
            build: 9,
            version: "1.1.2",
            headline: String(localized: "Meet your agent"),
            items: [
                Item(kind: .new, symbol: "sparkles", title: String(localized: "Agent"),
                     detail: String(localized: "A new tab: chat with Apple Intelligence about your week. It sees your calendar, your crews' commitments and your preferences.")),
                Item(kind: .improved, symbol: "circle.dashed", title: String(localized: "A bigger week dial"),
                     detail: String(localized: "The dial on the Plan tab is larger, with roomier spacing and larger week arrows.")),
                Item(kind: .fixed, symbol: "textformat", title: String(localized: "Screen titles"),
                     detail: String(localized: "Good morning, Crews and You headers now always show.")),
            ]
        ),
        Release(
            build: 10,
            version: "1.1.2",
            headline: String(localized: "A cleaner top"),
            items: [
                Item(kind: .improved, symbol: "rectangle.topthird.inset.filled", title: String(localized: "No more headers"),
                     detail: String(localized: "Screen titles are gone everywhere, so content starts right at the top."))
            ]
        ),
        Release(
            build: 11,
            version: "1.1.2",
            headline: String(localized: "Labels that follow the ring"),
            items: [
                Item(kind: .improved, symbol: "circle.dashed", title: String(localized: "Dial labels"),
                     detail: String(localized: "Each day now reads on one line, like “M 21”, smaller, and curves along its segment of the week dial."))
            ]
        ),
        Release(
            build: 12,
            version: "1.2.0",
            headline: String(localized: "Built for iPhone Air"),
            items: [
                Item(kind: .improved, symbol: "iphone", title: String(localized: "iOS 27 look"),
                     detail: String(localized: "Surfaces follow the phone's corners, Liquid Glass stays on controls, and content dissolves softly under the island and tab bar.")),
                Item(kind: .improved, symbol: "battery.100", title: String(localized: "Easier on the battery"),
                     detail: String(localized: "The background settles instead of animating forever, and suggestions pause in Low Power Mode so iPhone Air can last the day.")),
                Item(kind: .improved, symbol: "sparkles", title: String(localized: "Calmer intelligence"),
                     detail: String(localized: "Workout suggestions wait until you ask or pull to refresh, instead of running every time you open a crew.")),
            ]
        ),
        Release(
            build: 13,
            version: "1.2.1",
            headline: String(localized: "Sign in with Google"),
            items: [
                Item(kind: .new, symbol: "person.crop.circle.badge.checkmark", title: String(localized: "Sign in with Google"),
                     detail: String(localized: "Sideloaded builds can't use Sign in with Apple, so you create a profile with Google instead.")),
            ]
        ),
    ]

    /// Newest first — the order people want to read them in.
    static var all: [Release] { releases.reversed() }

    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// Releases newer than `lastSeen`, up to and including this build, newest first.
    static func unseen(since lastSeen: Int, currentBuild: Int = currentBuild) -> [Release] {
        all.filter { $0.build > lastSeen && $0.build <= currentBuild }
    }
}
