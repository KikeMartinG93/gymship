import Foundation
import FoundationModels

/// Computes free workout windows for a group from its members' synced busy
/// slots, then uses on-device Apple Intelligence to pick the single best
/// window per day — falling back to a deterministic heuristic when Apple
/// Intelligence isn't available on this device (older hardware, the feature
/// disabled in Settings, the model still downloading, Low Power Mode, or a
/// serious thermal state).
enum WorkoutSlotFinder {
    struct Candidate: Hashable {
        let day: Date
        let interval: DateInterval
    }

    struct Pick {
        let candidate: Candidate
        /// A short one-sentence reason, only present when Apple Intelligence
        /// made the choice.
        let reason: String?
    }

    /// For every day in `range`, finds free windows at least `duration` long
    /// that don't overlap any interval in `busySlots`, clipped to the
    /// user's allowed hours, skipping their rest days.
    static func freeCandidates(
        in range: DateInterval,
        duration: TimeInterval,
        busySlots: [DateInterval],
        preferences: WorkoutPreferences = .current,
        calendar: Calendar = .current
    ) -> [Date: [Candidate]] {
        var byDay: [Date: [Candidate]] = [:]
        var day = calendar.startOfDay(for: range.start)

        while day < range.end {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? range.end }

            guard !preferences.effectiveRestWeekdays.contains(calendar.component(.weekday, from: day)),
                  let dayStart = calendar.date(byAdding: .minute, value: preferences.effectiveEarliestStart, to: day),
                  let dayEnd = calendar.date(byAdding: .minute, value: preferences.effectiveLatestEnd, to: day),
                  dayEnd > dayStart else {
                continue
            }
            let window = DateInterval(start: dayStart, end: dayEnd)

            let dayBusy = busySlots
                .compactMap { $0.intersection(with: window) }
                .sorted { $0.start < $1.start }
            let merged = EventKitManager.mergeIntervals(dayBusy)

            var candidates: [Candidate] = []
            var cursor = dayStart
            for busy in merged {
                if busy.start.timeIntervalSince(cursor) >= duration {
                    candidates.append(Candidate(day: day, interval: DateInterval(start: cursor, duration: duration)))
                }
                cursor = max(cursor, busy.end)
            }
            if dayEnd.timeIntervalSince(cursor) >= duration {
                candidates.append(Candidate(day: day, interval: DateInterval(start: cursor, duration: duration)))
            }

            if !candidates.isEmpty {
                byDay[day] = candidates
            }
        }

        return byDay
    }

    /// Picks the best candidate for each day, preferring Apple Intelligence
    /// when it's available on this device and falling back to a heuristic
    /// (early morning or evening) otherwise. At most two on-device model
    /// sessions run at once so a thin iPhone Air doesn't thermal-throttle.
    static func pickBestPerDay(
        candidatesByDay: [Date: [Candidate]],
        preferences: WorkoutPreferences = .current
    ) async -> [Date: Pick] {
        let days = candidatesByDay.filter { !$0.value.isEmpty }
        let useAI = shouldUseAppleIntelligence
        var index = 0
        let items = Array(days)

        return await withTaskGroup(of: (Date, Pick).self) { group in
            func enqueueNext() {
                guard index < items.count else { return }
                let (day, candidates) = items[index]
                index += 1
                group.addTask {
                    if useAI, let aiPick = await Self.pickWithAppleIntelligence(candidates: candidates, preferences: preferences) {
                        return (day, aiPick)
                    }
                    return (day, Pick(candidate: heuristicPick(candidates, preferences: preferences), reason: nil))
                }
            }

            for _ in 0..<min(2, items.count) {
                enqueueNext()
            }

            var picks: [Date: Pick] = [:]
            for await (day, pick) in group {
                picks[day] = pick
                enqueueNext()
            }
            return picks
        }
    }

    /// Best-effort deterministic choice: prefer an early-morning (6–9am) or
    /// evening (5–8pm) start, otherwise the earliest free window.
    private static func heuristicPick(_ candidates: [Candidate], preferences: WorkoutPreferences) -> Candidate {
        let calendar = Calendar.current
        func minute(_ c: Candidate) -> Int {
            calendar.component(.hour, from: c.interval.start) * 60 + calendar.component(.minute, from: c.interval.start)
        }
        if preferences.lean != .none, let leaned = candidates.first(where: { preferences.prefers(startMinute: minute($0)) }) {
            return leaned
        }
        let preferred = candidates.first { candidate in
            let hour = calendar.component(.hour, from: candidate.interval.start)
            return (6...9).contains(hour) || (17...20).contains(hour)
        }
        return preferred ?? candidates[0]
    }

    private static var shouldUseAppleIntelligence: Bool {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return false }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return false
        default: break
        }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static func pickWithAppleIntelligence(candidates: [Candidate], preferences: WorkoutPreferences) async -> Pick? {
        let list = candidates.enumerated()
            .map {
                let start = $0.element.interval.start.formatted(date: .omitted, time: .shortened)
                let end = $0.element.interval.end.formatted(date: .omitted, time: .shortened)
                return "\($0.offset): \(start) – \(end)"
            }
            .joined(separator: "\n")

        var instructions = """
        You help a small workout group pick the most convenient shared time from a short \
        list of free windows on one day. Favor common workout times — early morning \
        (6–9am) or evening (5–8pm) — over the middle of the day, unless those aren't options.
        """
        if preferences.lean != .none {
            let time = String(format: "%d:%02d", (preferences.leanMinutes / 60 + 11) % 12 + 1, preferences.leanMinutes % 60)
            instructions += " Strongly prefer windows starting \(preferences.lean == .before ? "before" : "after") \(time) \(preferences.leanMinutes < 720 ? "AM" : "PM") when one is available."
        }
        let session = LanguageModelSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: "Candidate workout windows today:\n\(list)\n\nPick the single best one.",
                generating: SlotPick.self
            )
            guard candidates.indices.contains(response.content.index) else { return nil }
            return Pick(candidate: candidates[response.content.index], reason: response.content.reason)
        } catch {
            return nil
        }
    }
}

@Generable
private struct SlotPick {
    @Guide(description: "Zero-based index into the provided candidate list, selecting the single best workout window.")
    let index: Int
    @Guide(description: "A short, friendly one-sentence reason this time works well for the group.")
    let reason: String
}
