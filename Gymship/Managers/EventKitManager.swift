import Foundation
import EventKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Owns all interaction with the user's device calendars: authorization,
/// listing calendars, per-calendar availability toggles, extracting busy
/// ranges, and writing confirmed workout slots to a dedicated calendar.
@Observable
@MainActor
final class EventKitManager {
    private let store = EKEventStore()

    private(set) var authorizationStatus: EKAuthorizationStatus
    private(set) var calendars: [GymCalendar] = []
    var availability: [String: CalendarAvailability] = [:] {
        didSet { persistAvailability() }
    }
    private(set) var busySlots: [BusySlot] = []
    /// Time blocks the user marked busy by hand (not derived from any calendar).
    private(set) var manualBusySlots: [BusySlot] = [] {
        didSet { persistManualBusySlots() }
    }
    /// Maps a workout proposal id (as a string) to the EventKit identifier of
    /// the event synced for it, so re-syncing updates rather than duplicates.
    private(set) var syncedEventIdentifiers: [String: String] = [:] {
        didSet { persistSyncedEventIdentifiers() }
    }
    var lastError: String?

    private static let availabilityDefaultsKey = "gymship.calendarAvailability"
    private static let manualBusySlotsDefaultsKey = "gymship.manualBusySlots"
    private static let syncedEventIdentifiersDefaultsKey = "gymship.syncedEventIdentifiers"
    private static let workoutCalendarTitle = "Gymship"

    init() {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        loadPersistedAvailability()
        loadPersistedManualBusySlots()
        loadPersistedSyncedEventIdentifiers()
    }

    // MARK: - Authorization

    /// Requests full calendar access. Must be called before any calendar reads/writes.
    /// Requires `NSCalendarsFullAccessUsageDescription` in Info.plist.
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            if granted {
                await refreshCalendars()
            }
            return granted
        } catch {
            lastError = "Calendar access request failed: \(error.localizedDescription)"
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return false
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    // MARK: - Calendars

    /// Fetches all active (non-birthday, non-subscribed-read-only-hidden) calendars for events.
    func refreshCalendars() async {
        guard isAuthorized else { return }
        let ekCalendars = store.calendars(for: .event).filter { $0.type != .birthday }
        let mapped = ekCalendars
            .filter { $0.title != Self.workoutCalendarTitle }
            .map { GymCalendar(ekCalendar: $0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        self.calendars = mapped

        // Default any newly-seen calendar to "unavailable" (busy) so it's
        // conservatively excluded from workout scheduling until the user opts in.
        for cal in mapped where availability[cal.id] == nil {
            availability[cal.id] = .unavailable
        }
    }

    /// Toggles a calendar between Available and Unavailable.
    func setAvailability(_ value: CalendarAvailability, for calendarId: String) {
        availability[calendarId] = value
    }

    private func persistAvailability() {
        let raw = availability.mapValues { $0.rawValue }
        UserDefaults.standard.set(raw, forKey: Self.availabilityDefaultsKey)
    }

    private func loadPersistedAvailability() {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.availabilityDefaultsKey) as? [String: String] else {
            return
        }
        availability = raw.compactMapValues { CalendarAvailability(rawValue: $0) }
    }

    // MARK: - Busy slot extraction

    /// Extracts merged busy `DateInterval`s for the current week (Mon-Sun, using
    /// the user's calendar) from all calendars marked Unavailable.
    func refreshBusySlotsForCurrentWeek() async {
        guard isAuthorized else { return }
        let week = Self.currentWeekInterval()
        let unavailableCalendarIds = Set(availability.filter { $0.value == .unavailable }.keys)
        let ekCalendars = store.calendars(for: .event).filter { unavailableCalendarIds.contains($0.calendarIdentifier) }

        var rawIntervals: [DateInterval] = []
        if !ekCalendars.isEmpty {
            let predicate = store.predicateForEvents(withStart: week.start, end: week.end, calendars: ekCalendars)
            let events = store.events(matching: predicate).filter { !$0.isAllDay }
            rawIntervals = events.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        }

        let manualInWeek = manualBusySlots.map(\.interval).filter { $0.intersects(week) }
        rawIntervals.append(contentsOf: manualInWeek)

        let merged = Self.mergeIntervals(rawIntervals)
        busySlots = merged.map { BusySlot(start: $0.start, end: $0.end) }
    }

    // MARK: - Manual busy blocks

    /// Adds a hand-picked busy time block and refreshes the merged busy slots.
    func addManualBusySlot(start: Date, end: Date) async {
        manualBusySlots.append(BusySlot(start: start, end: end))
        manualBusySlots.sort { $0.start < $1.start }
        await refreshBusySlotsForCurrentWeek()
    }

    /// Removes a manually-added busy block by id and refreshes the merged busy slots.
    func removeManualBusySlot(id: UUID) async {
        manualBusySlots.removeAll { $0.id == id }
        await refreshBusySlotsForCurrentWeek()
    }

    private func persistManualBusySlots() {
        guard let data = try? JSONEncoder().encode(manualBusySlots) else { return }
        UserDefaults.standard.set(data, forKey: Self.manualBusySlotsDefaultsKey)
    }

    private func loadPersistedManualBusySlots() {
        guard let data = UserDefaults.standard.data(forKey: Self.manualBusySlotsDefaultsKey),
              let decoded = try? JSONDecoder().decode([BusySlot].self, from: data) else {
            return
        }
        manualBusySlots = decoded
    }

    /// Merges overlapping/adjacent intervals into a minimal sorted set.
    nonisolated static func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = [sorted[0]]

        for interval in sorted.dropFirst() {
            guard let last = merged.last else { merged.append(interval); continue }
            if interval.start <= last.end {
                let newEnd = max(last.end, interval.end)
                merged[merged.count - 1] = DateInterval(start: last.start, end: newEnd)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// Sunday-to-Saturday interval containing "now" — a new week starts
    /// every Sunday — in the user's current calendar/timezone.
    static func currentWeekInterval(calendar: Calendar = .current, now: Date = Date()) -> DateInterval {
        var cal = calendar
        cal.firstWeekday = 1 // Sunday
        let startOfToday = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: startOfToday) // 1 = Sunday ... 7 = Saturday
        let daysSinceSunday = weekday - 1
        let sunday = cal.date(byAdding: .day, value: -daysSinceSunday, to: startOfToday)!
        let nextSunday = cal.date(byAdding: .day, value: 7, to: sunday)!
        return DateInterval(start: sunday, end: nextSunday)
    }

    // MARK: - Workout calendar writes

    /// One workout to reconcile into the dedicated "Gymship" calendar.
    struct ScheduledWorkout {
        let proposalId: UUID
        let title: String
        let start: Date
        let end: Date
    }

    /// Reconciles the dedicated "Gymship" calendar with the given accepted
    /// workouts: creates/updates an event per item, and removes events for
    /// proposals that were previously synced but are no longer accepted.
    func syncWorkoutSchedule(_ items: [ScheduledWorkout]) async throws {
        guard isAuthorized else { throw EventKitManagerError.notAuthorized }
        let calendar = try workoutCalendar()
        var mapping = syncedEventIdentifiers
        let currentKeys = Set(items.map { $0.proposalId.uuidString })

        for (key, eventId) in syncedEventIdentifiers where !currentKeys.contains(key) {
            if let event = store.event(withIdentifier: eventId) {
                try? store.remove(event, span: .thisEvent, commit: true)
            }
            mapping.removeValue(forKey: key)
        }

        for item in items {
            let key = item.proposalId.uuidString
            if let existingId = mapping[key], let event = store.event(withIdentifier: existingId) {
                event.title = item.title
                event.startDate = item.start
                event.endDate = item.end
                event.calendar = calendar
                try store.save(event, span: .thisEvent, commit: true)
            } else {
                let event = EKEvent(eventStore: store)
                event.title = item.title
                event.startDate = item.start
                event.endDate = item.end
                event.calendar = calendar
                try store.save(event, span: .thisEvent, commit: true)
                mapping[key] = event.eventIdentifier
            }
        }

        syncedEventIdentifiers = mapping
    }

    private func persistSyncedEventIdentifiers() {
        UserDefaults.standard.set(syncedEventIdentifiers, forKey: Self.syncedEventIdentifiersDefaultsKey)
    }

    private func loadPersistedSyncedEventIdentifiers() {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.syncedEventIdentifiersDefaultsKey) as? [String: String] else {
            return
        }
        syncedEventIdentifiers = raw
    }

    /// Finds (or creates on first use) the dedicated local "Gymship" calendar.
    private func workoutCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.workoutCalendarTitle }) {
            return existing
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.workoutCalendarTitle
        calendar.cgColor = UIColor.systemPurple.cgColor

        guard let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first else {
            throw EventKitManagerError.noCalendarSource
        }
        calendar.source = source

        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    /// Writes a confirmed workout slot as an event on the dedicated Workout calendar.
    @discardableResult
    func writeWorkoutSlot(_ slot: WorkoutSlot) async throws -> String {
        guard isAuthorized else { throw EventKitManagerError.notAuthorized }

        let calendar = try workoutCalendar()
        let event = EKEvent(eventStore: store)
        event.title = slot.title
        event.startDate = slot.start
        event.endDate = slot.end
        event.notes = slot.notes
        event.calendar = calendar

        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    /// Removes a previously-written workout event by its EventKit identifier.
    func removeWorkoutSlot(eventIdentifier: String) throws {
        guard let event = store.event(withIdentifier: eventIdentifier) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    // MARK: - Reset

    /// Clears every locally-persisted preference (calendar availability,
    /// manual busy blocks, synced-event bookkeeping) back to defaults. Used
    /// by Settings' "Reset to Factory Defaults" (testing only) — this does
    /// not touch the device's actual calendars or events, only this app's
    /// own local state.
    func resetLocalState() {
        availability = [:]
        manualBusySlots = []
        syncedEventIdentifiers = [:]
        busySlots = []
    }
}

enum EventKitManagerError: LocalizedError {
    case notAuthorized
    case noCalendarSource

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return String(localized: "Calendar access has not been granted.")
        case .noCalendarSource:
            return String(localized: "No calendar source is available to create the Workout calendar.")
        }
    }
}
