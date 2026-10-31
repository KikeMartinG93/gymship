import SwiftUI
import FoundationModels

/// A chat with on-device Apple Intelligence that reads your schedule, your
/// crews' commitments and your preferences, and gives scheduling advice.
struct AgentView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(ThemeManager.self) private var theme

    @State private var chat = AgentChat()
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var suggestions: [String] {
        [
            String(localized: "When should I work out this week?"),
            String(localized: "Which crew session fits my schedule best?"),
            String(localized: "Am I on track for my weekly goal?"),
            String(localized: "Find me a solo slot that avoids my busy days."),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if chat.messages.isEmpty {
                        intro
                    }
                    ForEach(chat.messages) { message in
                        bubble(message)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaBar(edge: .bottom) { composer }
            .toolbar(inputFocused ? .hidden : .automatic, for: .tabBar)
        }
    }

    private var intro: some View {
        VStack(spacing: 18) {
            if !chat.isAvailable {
                EmptyStateView(
                    symbol: "sparkles",
                    title: String(localized: "Apple Intelligence is off"),
                    message: String(localized: "Turn on Apple Intelligence in Settings to chat with your scheduling agent.")
                )
                .glassCard(cornerRadius: 34)
            } else {
                EmptyStateView(
                    symbol: "sparkles",
                    title: String(localized: "Your scheduling agent"),
                    message: String(localized: "It sees your calendar, your crews' commitments and your preferences. Ask it anything about your week.")
                )
                if !inputFocused {
                    VStack(spacing: 10) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                send(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.system(.subheadline, weight: .medium))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                            .buttonStyle(.plain)
                            .glassSurface(Metrics.concentric(minimum: 22), interactive: true)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .gymshipAnimation(Motion.ui, value: inputFocused)
    }

    private func bubble(_ message: AgentChat.Message) -> some View {
        let mine = message.role == .user
        return HStack {
            if mine { Spacer(minLength: 48) }
            SwiftUI.Group {
                if message.text.isEmpty {
                    ProgressView()
                } else {
                    Text(message.text)
                        .foregroundStyle(mine ? theme.onAccent : .primary)
                }
            }
            .font(.system(.body))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                // User bubbles are static — glass is cheap once. Agent bubbles
                // grow on every stream tick; a solid fill stays at 60/120 without
                // a glass sampling pass per token.
                if mine {
                    Metrics.concentric(minimum: 22).fill(theme.accent)
                } else {
                    Metrics.concentric(minimum: 22).fill(theme.washStrong)
                }
            }
            if !mine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isResponding && chat.isAvailable
    }

    /// Capsule field on a solid plate so the keyboard and chips never show through.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about your week", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.body))
                .lineLimit(1...5)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send(input) }
                .disabled(!chat.isAvailable)

            Button {
                send(input)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? theme.onAccent : Color.secondary)
                    .frame(width: Metrics.circleButton, height: Metrics.circleButton)
                    .background(canSend ? theme.accent : theme.washStrong, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(theme.washStrong, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            if inputFocused {
                theme.baseColor.ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chat.isResponding else { return }
        input = ""
        let snapshot = ScheduleSnapshot.build(supabase: supabase, eventKit: eventKitManager)
        Task { await chat.send(trimmed, snapshot: snapshot) }
    }
}

// MARK: - Chat model

@Observable
@MainActor
final class AgentChat {
    struct Message: Identifiable {
        enum Role { case user, agent }
        let id = UUID()
        let role: Role
        var text: String
    }

    private(set) var messages: [Message] = []
    private(set) var isResponding = false

    private var session: LanguageModelSession?

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static var instructions: String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        return """
        You are Gymship's scheduling agent, helping one person plan workouts. Each message \
        includes a snapshot of their schedule, their friend crews' sessions and who has \
        committed, their weekly goal and their scheduling preferences. Base advice only on \
        that snapshot; never invent events. Respect their never-before/never-after hours and \
        rest days. Prefer times that already have friends committed. Be concise: two to five \
        short sentences, or a short list of specific times. Reply in the language with code \(language).
        """
    }

    func send(_ text: String, snapshot: String) async {
        guard isAvailable else { return }
        isResponding = true
        messages.append(Message(role: .user, text: text))
        messages.append(Message(role: .agent, text: ""))
        let index = messages.count - 1
        let prompt = "SCHEDULE SNAPSHOT\n\(snapshot)\n\nQUESTION\n\(text)"

        for attempt in 0..<2 {
            let session = self.session ?? LanguageModelSession(instructions: Self.instructions)
            self.session = session
            do {
                var latest = ""
                var lastFlush = Date.distantPast
                for try await partial in session.streamResponse(to: prompt) {
                    latest = partial.content
                    let now = Date()
                    if now.timeIntervalSince(lastFlush) >= 0.08 {
                        messages[index].text = latest
                        lastFlush = now
                    }
                }
                if messages[index].text != latest {
                    messages[index].text = latest
                }
                break
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize where attempt == 0 {
                self.session = nil
            } catch {
                messages[index].text = String(localized: "Sorry, I couldn't answer that. Try again in a moment.")
                self.session = nil
                break
            }
        }
        isResponding = false
    }
}

// MARK: - Schedule snapshot

@MainActor
enum ScheduleSnapshot {
    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func build(supabase: SupabaseService, eventKit: EventKitManager) -> String {
        let calendar = Calendar.current
        let now = Date()
        func range(_ s: Date, _ e: Date) -> String {
            "\(day.string(from: s)) \(time.string(from: s))–\(time.string(from: e))"
        }

        var lines: [String] = ["Now: \(day.string(from: now)) \(time.string(from: now))"]

        let prefs = WorkoutPreferences.current
        func clock(_ m: Int) -> String {
            String(format: "%d:%02d %@", (m / 60 + 11) % 12 + 1, m % 60, m < 720 ? "AM" : "PM")
        }
        var prefLine = "Preferences: "
        if prefs.limitsHours {
            prefLine += "never before \(clock(prefs.earliestStart)), never after \(clock(prefs.latestEnd))"
        } else {
            prefLine += "any hours"
        }
        if prefs.lean != .none { prefLine += ", prefers \(prefs.lean == .before ? "before" : "after") \(clock(prefs.leanMinutes))" }
        if prefs.usesRestDays, !prefs.restWeekdays.isEmpty {
            let names = prefs.restWeekdays.sorted().map { calendar.weekdaySymbols[$0 - 1] }
            prefLine += ", rest days: \(names.joined(separator: ", "))"
        }
        lines.append(prefLine)

        let goal = UserDefaults.standard.object(forKey: "gymship.weeklyGoal") as? Int ?? 3
        let week = EventKitManager.currentWeekInterval()
        let confirmed = supabase.myProposals.filter {
            week.contains($0.proposal.startsAt) && supabase.myResponses[$0.id] == .accepted
        }.count
        lines.append("Weekly goal: \(goal) workouts; \(confirmed) committed this week")

        let busy = EventKitManager.mergeIntervals(
            eventKit.busySlots.map { DateInterval(start: $0.start, end: $0.end) }
                .filter { $0.end > now }
                .sorted { $0.start < $1.start }
        )
        lines.append("Your busy blocks:")
        if busy.isEmpty { lines.append("- none") }
        for slot in busy.prefix(24) { lines.append("- \(range(slot.start, slot.end))") }

        lines.append("Crew sessions (yours and your friends'):")
        let upcoming = supabase.myProposals
            .filter { $0.proposal.endsAt > now }
            .sorted { $0.proposal.startsAt < $1.proposal.startsAt }
            .prefix(14)
        if upcoming.isEmpty { lines.append("- none") }
        for item in upcoming {
            let who = (supabase.commitments[item.id] ?? []).map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
            let mine = supabase.myResponses[item.id] == .accepted
            let locked = supabase.isConfirmedWorkout(item.id)
            lines.append("- \(item.groupName): \(item.proposal.title), \(range(item.proposal.startsAt, item.proposal.endsAt)); in: \(who.isEmpty ? "nobody" : who.joined(separator: ", ")); you \(mine ? "are in" : "have not joined")\(locked ? "; locked" : "")")
        }
        return lines.joined(separator: "\n")
    }
}
