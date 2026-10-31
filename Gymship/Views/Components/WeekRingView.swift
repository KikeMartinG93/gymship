import SwiftUI

/// The week as a dial: seven arcs, one per day, drawn as a single ring. A day
/// you've committed to fills in; a day that's actually locked in (two or more
/// people) fills solid. The centre counts your progress against the goal.
struct WeekRingView: View {
    @Environment(ThemeManager.self) private var theme

    let weekStart: Date
    /// Days (start-of-day) you've said "I'm in" to.
    let committed: Set<Date>
    /// Days whose workout is confirmed (a second person is in too).
    let locked: Set<Date>
    let goal: Int
    var selectedDay: Date?
    /// Turn these off for a purely decorative dial (e.g. onboarding).
    var showsCenter = true
    var showsLabels = true
    var onSelectDay: (Date) -> Void

    private let calendar = Calendar.current
    /// The dial is designed at 272pt; everything inside scales with its size.
    private static let designSize: CGFloat = 272

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var count: Int { committed.count }
    private var goalHit: Bool { count >= goal }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let k = size / Self.designSize
            let lineWidth = 34 * k
            let radius = (size - lineWidth) / 2
            let circumference = 2 * .pi * radius
            let inset = ((lineWidth + 9) / 2) / circumference

            ZStack {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    if showsLabels, calendar.isDateInToday(day) {
                        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                        // The segment's own silhouette, grown by a hair, then traced:
                        // a thin ring hugging today's arc, drawn beneath the arcs so
                        // it reads as an edge of the segment rather than a separate shape.
                        Circle()
                            .inset(by: lineWidth / 2)
                            .trim(from: Double(index) / 7 + inset, to: Double(index + 1) / 7 - inset)
                            .path(in: CGRect(x: 0, y: 0, width: size, height: size))
                            .strokedPath(StrokeStyle(lineWidth: (isSelected ? lineWidth + 6 : lineWidth) + 2.5, lineCap: .round))
                            .stroke(.white, lineWidth: 3)
                            .rotationEffect(.degrees(-90))
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }

                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                    // Inset by half the stroke so the arc is centred on `radius`,
                    // the same circle the day labels sit on.
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: Double(index) / 7 + inset, to: Double(index + 1) / 7 - inset)
                        .stroke(
                            fill(for: day),
                            style: StrokeStyle(lineWidth: isSelected ? lineWidth + 6 : lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                if showsCenter { center(scale: k) }

                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let angle = (Double(index) + 0.5) / 7 * 2 * .pi
                    dayLabel(day, scale: k, angle: angle, ringRadius: radius)
                        .opacity(showsLabels ? 1 : 0)
                        .allowsHitTesting(showsLabels)
                        .position(
                            x: size / 2 + radius * sin(angle),
                            y: size / 2 - radius * cos(angle)
                        )
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gymshipAnimation(Motion.ui, value: committed)
            .gymshipAnimation(Motion.ui, value: selectedDay)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: Centre

    private func center(scale k: CGFloat) -> some View {
        VStack(spacing: 2 * k) {
            Text("\(count)")
                .font(.display(64 * k))
                .gymshipNumericText(Double(count))
                .gymshipAnimation(value: count)
            Text("of \(goal) this week")
                .font(.system(size: 15 * k, weight: .semibold))
                .foregroundStyle(.secondary)
            if goalHit {
                Label("Goal hit", systemImage: "sparkles")
                    .font(.system(size: 12 * k, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .padding(.top, 4 * k)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .gymshipAnimation(value: goalHit)
    }

    // MARK: Days

    private func isCommitted(_ day: Date) -> Bool { committed.contains(calendar.startOfDay(for: day)) }
    private func isLocked(_ day: Date) -> Bool { locked.contains(calendar.startOfDay(for: day)) }

    private func fill(for day: Date) -> AnyShapeStyle {
        if isLocked(day) { return AnyShapeStyle(theme.accent) }
        if isCommitted(day) { return AnyShapeStyle(theme.accent.opacity(0.45)) }
        return AnyShapeStyle(.white.opacity(theme.highContrast ? 0.22 : 0.09))
    }

    private func dayLabel(_ day: Date, scale k: CGFloat, angle: Double, ringRadius: CGFloat) -> some View {
        let isToday = calendar.isDateInToday(day)
        let filled = isLocked(day)
        let ink: Color = filled ? theme.onAccent : .primary
        // Run the text along the ring, keeping it upright: labels on the
        // lower half read in the opposite direction, so flip them a half turn.
        let onTopHalf = cos(angle) >= 0
        let tilt = onTopHalf ? angle : angle - .pi
        let letter = day.formatted(.dateTime.weekday(.narrow))
        let number = day.formatted(.dateTime.day())

        return Button {
            onSelectDay(day)
        } label: {
            ArcText(
                text: "\(letter) \(number)",
                dimmedPrefix: letter.count,
                size: 12 * k,
                weight: .semibold,
                color: ink,
                radius: ringRadius,
                centerBelow: onTopHalf
            )
            .rotationEffect(.radians(tilt))
            .frame(width: 44 * k, height: 44 * k)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityValue(
            [isToday ? String(localized: "Today") : nil,
             isLocked(day) ? String(localized: "Workout locked in") : isCommitted(day) ? String(localized: "You're in") : String(localized: "Nothing planned")]
                .compactMap { $0 }.joined(separator: ", ")
        )
    }
}

/// A short string curved along the ring's own arc, so a label follows the
/// shape of the pill it sits on. Each character is placed on the rim of a
/// circle of `radius` and tilted to match; `centerBelow` says which side of
/// the text the circle's centre is on, so top and bottom labels both hug the ring.
private struct ArcText: View {
    let text: String
    var dimmedPrefix = 0
    let size: CGFloat
    let weight: Font.Weight
    var color: Color = .primary
    let radius: CGFloat
    var centerBelow = true

    private var widths: [CGFloat] {
        text.map { $0 == " " ? size * 0.32 : size * 0.62 }
    }

    var body: some View {
        let characters = Array(text)
        let widths = self.widths
        let total = widths.reduce(0, +)
        var offsets: [CGFloat] = []
        var run: CGFloat = -total / 2
        for w in widths { offsets.append(run + w / 2); run += w }

        return ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                let a = Double(offsets[index] / radius)
                let dx = radius * sin(a)
                let dy = radius * (1 - cos(a)) * (centerBelow ? 1 : -1)
                Text(String(character))
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(color)
                    .opacity(index < dimmedPrefix ? 0.7 : 1)
                    .rotationEffect(.radians(centerBelow ? a : -a))
                    .offset(x: dx, y: dy)
            }
        }
        .frame(width: total, height: size * 1.2)
    }
}
