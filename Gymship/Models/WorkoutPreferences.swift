import Foundation

/// Personal scheduling rules: hard limits the app never schedules outside of,
/// a soft lean toward mornings or evenings, and days that are always off.
struct WorkoutPreferences: Codable, Equatable {
    enum Lean: String, Codable, CaseIterable {
        case none, before, after
    }

    enum CodingKeys: String, CodingKey {
        case earliestStart, latestEnd, lean, leanMinutes, restWeekdays, limitsHours, usesRestDays
    }

    static let storageKey = "gymship.workoutPreferences"

    /// Minutes after midnight. Used when `limitsHours` is on.
    var earliestStart = 6 * 60
    var latestEnd = 22 * 60
    var lean = Lean.none
    var leanMinutes = 9 * 60
    /// `Calendar` weekday numbers (1 = Sunday). Used when `usesRestDays` is on.
    var restWeekdays: Set<Int> = []
    /// When off, suggestions can land at any hour.
    var limitsHours = true
    /// When off, no weekday is treated as rest.
    var usesRestDays = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        earliestStart = try c.decodeIfPresent(Int.self, forKey: .earliestStart) ?? 6 * 60
        latestEnd = try c.decodeIfPresent(Int.self, forKey: .latestEnd) ?? 22 * 60
        lean = try c.decodeIfPresent(Lean.self, forKey: .lean) ?? .none
        leanMinutes = try c.decodeIfPresent(Int.self, forKey: .leanMinutes) ?? 9 * 60
        restWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .restWeekdays) ?? []
        limitsHours = try c.decodeIfPresent(Bool.self, forKey: .limitsHours) ?? true
        usesRestDays = try c.decodeIfPresent(Bool.self, forKey: .usesRestDays) ?? !restWeekdays.isEmpty
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(earliestStart, forKey: .earliestStart)
        try c.encode(latestEnd, forKey: .latestEnd)
        try c.encode(lean, forKey: .lean)
        try c.encode(leanMinutes, forKey: .leanMinutes)
        try c.encode(restWeekdays, forKey: .restWeekdays)
        try c.encode(limitsHours, forKey: .limitsHours)
        try c.encode(usesRestDays, forKey: .usesRestDays)
    }

    static var current: WorkoutPreferences {
        guard let json = UserDefaults.standard.string(forKey: storageKey) else { return WorkoutPreferences() }
        return decode(json)
    }

    static func decode(_ json: String) -> WorkoutPreferences {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(WorkoutPreferences.self, from: data) else {
            return WorkoutPreferences()
        }
        return value
    }

    var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    var effectiveEarliestStart: Int { limitsHours ? earliestStart : 0 }
    var effectiveLatestEnd: Int { limitsHours ? latestEnd : 24 * 60 }
    var effectiveRestWeekdays: Set<Int> { usesRestDays ? restWeekdays : [] }

    func prefers(startMinute: Int) -> Bool {
        switch lean {
        case .none: false
        case .before: startMinute < leanMinutes
        case .after: startMinute >= leanMinutes
        }
    }
}
