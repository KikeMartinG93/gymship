import SwiftUI

/// Availability: how much of your week is free, which calendars count as
/// busy, and time you've blocked by hand.
struct CalendarSetupView: View {
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(SupabaseService.self) private var supabase
    @Environment(ThemeManager.self) private var theme

    @State private var isShowingAddBusyBlock = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if !eventKitManager.isAuthorized {
                    PermissionCard(
                        symbol: "calendar.badge.exclamationmark",
                        title: String(localized: "Calendar access needed"),
                        message: String(localized: "Gymship reads when you're busy so your crew can find time that works."),
                        buttonTitle: String(localized: "Allow calendar access")
                    ) {
                        Task { await eventKitManager.requestAccess() }
                    }
                } else {
                    weekCard
                    calendarsSection
                    manualSection
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if eventKitManager.isAuthorized {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Block time", systemImage: "plus") { isShowingAddBusyBlock = true }
                }
                .flatInHighContrast()
            }
        }
        .sheet(isPresented: $isShowingAddBusyBlock) {
            AddBusyBlockSheet { start, end in
                await eventKitManager.addManualBusySlot(start: start, end: end)
                await syncBusyToGroups()
            }
        }
        .task {
            if eventKitManager.isAuthorized { await refreshAll() }
        }
        .refreshable { await refreshAll() }
    }

    // MARK: This week

    /// Waking hours (6am–10pm) are what count as "available to work out".
    private static let wakingRange = 6...22

    private var weekStart: Date { EventKitManager.currentWeekInterval().start }

    private var busyHoursByDay: [Double] {
        let calendar = Calendar.current
        let merged = eventKitManager.busySlots.map { DateInterval(start: $0.start, end: $0.end) }
        return (0..<7).map { offset -> Double in
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: weekStart),
                let from = calendar.date(bySettingHour: Self.wakingRange.lowerBound, minute: 0, second: 0, of: day),
                let to = calendar.date(bySettingHour: Self.wakingRange.upperBound, minute: 0, second: 0, of: day)
            else { return 0 }
            let window = DateInterval(start: from, end: to)
            return merged.reduce(0) { total, slot in
                total + (slot.intersection(with: window)?.duration ?? 0) / 3600
            }
        }
    }

    private var weekCard: some View {
        let hours = busyHoursByDay
        let windowHours = Double(Self.wakingRange.count)
        let free = max(0, windowHours * 7 - hours.reduce(0, +))

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(free.rounded()))")
                    .font(.display(48))
                    .gymshipNumericText(Double(free))
                Text("free hours\nthis week")
                    .font(.display(.subheadline, .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<7, id: \.self) { index in
                    dayBar(index: index, busy: hours[index], of: windowHours)
                }
            }
            .frame(height: 96)
        }
        .padding(20)
        .glassCard(cornerRadius: 32)
        .gymshipAnimation(value: free)
    }

    private func dayBar(index: Int, busy: Double, of total: Double) -> some View {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
        let fraction = min(1, busy / total)
        let isToday = calendar.isDateInToday(day)

        return VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Capsule().fill(theme.emptyTrack)
                    Capsule()
                        .fill(theme.accent.opacity(0.9))
                        .frame(height: max(10, proxy.size.height * fraction))
                        .opacity(fraction > 0 ? 1 : 0)
                }
            }
            Text(day.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isToday ? theme.accent : .secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide)))
        .accessibilityValue(String(localized: "\(Int(busy.rounded())) busy hours"))
    }

    // MARK: Calendars

    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Calendars"), subtitle: String(localized: "Switch on the ones that mean you're busy"))

            if eventKitManager.calendars.isEmpty {
                HintTile(symbol: "calendar", text: String(localized: "No calendars found."))
            } else {
                GlassGroup {
                    ForEach(Array(eventKitManager.calendars.enumerated()), id: \.element.id) { index, calendar in
                        if index > 0 { RowDivider().padding(.leading, 40) }
                        CalendarRow(
                            calendar: calendar,
                            availability: eventKitManager.availability[calendar.id] ?? .unavailable
                        ) { newValue in
                            eventKitManager.setAvailability(newValue, for: calendar.id)
                            Task { await refreshAll() }
                        }
                    }
                }
            }
        }
    }

    // MARK: Manual blocks

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Blocked by you"), subtitle: String(localized: "Time your calendars don't cover"))

            if eventKitManager.manualBusySlots.isEmpty {
                HintTile(symbol: "hand.raised", text: String(localized: "Nothing blocked. Tap + to block off time."))
            } else {
                GlassGroup {
                    ForEach(Array(eventKitManager.manualBusySlots.enumerated()), id: \.element.id) { index, slot in
                        if index > 0 { RowDivider().padding(.leading, 16) }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.start.formatted(.dateTime.weekday(.wide).month().day()))
                                    .font(.system(.body, weight: .medium))
                                Text("\(slot.start.formatted(date: .omitted, time: .shortened)) – \(slot.end.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(.footnote))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", systemImage: "xmark.circle.fill") {
                                Task {
                                    await eventKitManager.removeManualBusySlot(id: slot.id)
                                    await syncBusyToGroups()
                                }
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: Logic

    private func refreshAll() async {
        await eventKitManager.refreshCalendars()
        await eventKitManager.refreshBusySlotsForCurrentWeek()
        await syncBusyToGroups()
    }

    /// Pushes the current busy slots to every group the user belongs to.
    /// Runs automatically on launch/refresh and after any edit, so there's no
    /// separate "sync" step for the user.
    private func syncBusyToGroups() async {
        try? await supabase.syncBusySlotsToAllGroups(eventKitManager.busySlots)
    }
}

// MARK: - Add block sheet

private struct AddBusyBlockSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (Date, Date) async -> Void

    @State private var start = Date().addingTimeInterval(3600)
    @State private var end = Date().addingTimeInterval(7200)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text("Block time")
                    .font(.display(30))

                VStack(spacing: 0) {
                    DatePicker("Starts", selection: $start)
                        .padding(16)
                    RowDivider().padding(.leading, 16)
                    DatePicker("Ends", selection: $end, in: start...)
                        .padding(16)
                }
                .font(.display(.subheadline, .semibold))
                .glassCard(cornerRadius: 24)

                Spacer()

                Button("Mark unavailable") {
                    Task {
                        await onSave(start, end)
                        dismiss()
                    }
                }
                .buttonStyle(GymshipButtonStyle())
            }
            .padding(Metrics.gutter)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                .flatInHighContrast()
            }
        }
        .presentationDetents([.medium])
        .highContrastSheetBackground()
    }
}
