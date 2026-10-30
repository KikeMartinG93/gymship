import Foundation

/// Personal scheduling rules: hard limits the app never schedules outside of,
/// a soft lean toward mornings or evenings, and days that are always off.
struct WorkoutPreferences: Codable, Equatable {
    enum Lean: String, Codable, CaseIterable {
        case none, before, after
    }

    static let storageKey = "gymship.workoutPreferences"

    /// Minutes after midnight.
    var earliestStart = 6 * 60
    var latestEnd = 22 * 60
    var lean = Lean.none
    var leanMinutes = 9 * 60
    /// `Calendar` weekday numbers (1 = Sunday) that never get a workout.
    var restWeekdays: Set<Int> = []

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

    func prefers(startMinute: Int) -> Bool {
        switch lean {
        case .none: false
        case .before: startMinute < leanMinutes
        case .after: startMinute >= leanMinutes
        }
    }
}
