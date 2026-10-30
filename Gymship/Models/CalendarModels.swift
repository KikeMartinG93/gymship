import Foundation
import EventKit

/// A lightweight, `Sendable` wrapper around `EKCalendar` for use in views and
/// across actor boundaries (EKCalendar itself is not Sendable).
struct GymCalendar: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let colorHex: String
    let sourceTitle: String

    init(ekCalendar: EKCalendar) {
        self.id = ekCalendar.calendarIdentifier
        self.title = ekCalendar.title
        self.colorHex = ekCalendar.cgColor.hexString
        self.sourceTitle = ekCalendar.source?.title ?? String(localized: "Unknown")
    }
}

/// User's chosen availability for a given calendar, persisted locally.
enum CalendarAvailability: String, Codable {
    case available
    case unavailable
}

/// A busy time range extracted from the user's "Unavailable" calendars.
struct BusySlot: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let start: Date
    let end: Date

    init(id: UUID = UUID(), start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }

    var interval: DateInterval {
        DateInterval(start: start, end: end)
    }
}

/// A confirmed workout slot the app writes to the dedicated Workout calendar.
struct WorkoutSlot: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let start: Date
    let end: Date
    var notes: String?

    init(id: UUID = UUID(), title: String, start: Date, end: Date, notes: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
    }
}

import CoreGraphics

extension CGColor {
    /// Best-effort hex conversion for storing/displaying calendar colors.
    var hexString: String {
        guard let components = self.components, components.count >= 3 else {
            return "#8E8E93"
        }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
