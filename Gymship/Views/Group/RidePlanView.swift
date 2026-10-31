import SwiftUI
import MapKit
import CoreLocation

/// Ride coordination for a locked-in workout: where the gym is, who's driving
/// and who's getting picked up, and — the point of it all — when everyone
/// needs to leave.
struct RidePlanView: View {
    let group: Group
    let item: ProposalWithGroup

    @Environment(SupabaseService.self) private var supabase
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var currentGroup: Group

    @State private var gymAddressText = ""
    @State private var isEditingGym: Bool
    @State private var isSavingGymLocation = false

    @State private var myMode: RideMode = .driving
    @State private var selectedDriverId: UUID?
    @State private var startAddressText = ""
    @State private var isSavingRide = false

    private struct Timing {
        /// Total drive time for this person (including any pickup leg).
        let total: TimeInterval
        /// Drive time from their pickup point to the gym (passengers only).
        let pickupToGym: TimeInterval?
    }

    @State private var timingByUser: [UUID: Timing] = [:]
    @State private var etaErrorByUser: [UUID: String] = [:]
    @State private var isCalculatingETAs = false

    @State private var errorMessage: String?

    init(group: Group, item: ProposalWithGroup) {
        self.group = group
        self.item = item
        _currentGroup = State(initialValue: group)
        _gymAddressText = State(initialValue: group.gymAddress ?? "")
        _isEditingGym = State(initialValue: !group.hasGymLocation)
    }

    private var committedMembers: [Profile] {
        supabase.commitments[item.id] ?? []
    }

    private var otherCommittedMembers: [Profile] {
        committedMembers.filter { $0.id != supabase.currentUserId }
    }

    private var assignments: [RideAssignment] {
        supabase.rideAssignments[item.id] ?? []
    }

    private func assignment(for userId: UUID) -> RideAssignment? {
        assignments.first { $0.userId == userId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if currentGroup.hasGymLocation {
                        mapCard
                    }

                    gymSection

                    if currentGroup.hasGymLocation {
                        myRideSection
                        leaveTimesSection
                    }

                    if let errorMessage {
                        InlineMessage(text: errorMessage, isError: true)
                    }
                }
                .padding(Metrics.gutter)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
                .flatInHighContrast()
            }
            .task { await loadExisting() }
        }
        .presentationDetents([.large])
        .highContrastSheetBackground()
    }

    // MARK: Map

    private var mapCard: some View {
        Map(initialPosition: .automatic) {
            if let lat = currentGroup.gymLatitude, let lon = currentGroup.gymLongitude {
                Marker("Gym", systemImage: "dumbbell.fill", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    .tint(theme.accent)
            }
            ForEach(committedMembers) { member in
                if let start = assignment(for: member.id)?.startCoordinate {
                    Marker(
                        member.name.split(separator: " ").first.map(String.init) ?? member.name,
                        coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)
                    )
                    .tint(.white)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .frame(height: 210)
        .clipShape(Metrics.concentric(minimum: 30))
        .overlay(Metrics.concentric(minimum: 30).stroke(.white.opacity(0.15), lineWidth: 1))
        .allowsHitTesting(false)
    }

    // MARK: Gym

    private var gymSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Gym"), subtitle: String(localized: "Shared by the whole crew"))

            if isEditingGym {
                VStack(spacing: 12) {
                    TextField("Gym address", text: $gymAddressText)
                        .textContentType(.fullStreetAddress)
                        .glassTextFieldStyle()

                    Button {
                        Task { await saveGymLocation() }
                    } label: {
                        if isSavingGymLocation { ProgressView() } else { Text("Save location") }
                    }
                    .buttonStyle(GymshipButtonStyle())
                    .disabled(isSavingGymLocation || gymAddressText.isEmpty)
                }
            } else {
                HStack(spacing: 14) {
                    IconTile(symbol: "mappin.and.ellipse", color: theme.accent)
                    Text(currentGroup.gymAddress ?? gymAddressText)
                        .font(.system(.subheadline, weight: .medium))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Edit") { isEditingGym = true }
                        .glassButton()
                }
                .padding(14)
                .glassCard(cornerRadius: 24)
            }
        }
    }

    // MARK: My ride

    private var myRideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Your ride"))

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    modeTile(.driving, symbol: "car.fill", title: String(localized: "I'm driving"))
                    modeTile(.pickedUp, symbol: "figure.wave", title: String(localized: "Need a ride"))
                }

                if myMode == .pickedUp {
                    if otherCommittedMembers.isEmpty {
                        Text("No one else is in yet, so there's no one to ride with.")
                            .font(.system(.footnote))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Who's picking you up?")
                                .font(.display(.subheadline, .semibold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(otherCommittedMembers) { member in
                                        driverChoice(member)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                            }
                            .scrollEdgeEffectStyle(.soft, for: .all)
                            .scrollClipDisabled()
                        }
                    }
                }

                TextField(myMode == .driving ? "Where are you leaving from?" : "Pickup address", text: $startAddressText)
                    .textContentType(.fullStreetAddress)
                    .glassTextFieldStyle()

                Button {
                    Task { await saveMyRide() }
                } label: {
                    if isSavingRide { ProgressView() } else { Text("Save my ride") }
                }
                .buttonStyle(GymshipButtonStyle())
                .disabled(isSavingRide || startAddressText.isEmpty || (myMode == .pickedUp && selectedDriverId == nil))
            }
            .padding(18)
            .glassCard(cornerRadius: 30)
        }
    }

    private func modeTile(_ mode: RideMode, symbol: String, title: String) -> some View {
        let selected = myMode == mode
        let disabled = mode == .pickedUp && otherCommittedMembers.isEmpty
        return Button {
            Motion.run { myMode = mode }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(.title2))
                Text(title)
                    .font(.display(.subheadline, .semibold))
            }
            .foregroundStyle(selected && !theme.highContrast ? theme.onAccent : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            // In High Contrast, `glassSurface` already gives a selected tile
            // its own soft, emphasized fill via `tint` — no need for a
            // separate hard-edged white block on top.
            .glassSurface(
                Metrics.concentric(minimum: 22),
                tint: selected ? theme.accent : nil,
                interactive: true
            )
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .sensoryFeedback(.selection, trigger: myMode)
    }

    private func driverChoice(_ member: Profile) -> some View {
        let selected = selectedDriverId == member.id
        return Button {
            Motion.run { selectedDriverId = member.id }
        } label: {
            VStack(spacing: 8) {
                Avatar(name: member.name, size: 52, ring: selected ? theme.accent : nil)
                Text(member.name.split(separator: " ").first.map(String.init) ?? member.name)
                    .font(.system(.footnote, weight: selected ? .bold : .medium))
                    .lineLimit(1)
            }
            .frame(width: 66)
        }
        .buttonStyle(.plain)
    }

    // MARK: Leave times

    private var leaveTimesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Leave times"), subtitle: String(localized: "For the \(item.proposal.startsAt.formatted(date: .omitted, time: .shortened)) start")) {
                Button {
                    Task { await calculateETAs() }
                } label: {
                    if isCalculatingETAs {
                        ProgressView()
                    } else {
                        Label("Calculate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(.footnote, weight: .semibold))
                    }
                }
                .disabled(isCalculatingETAs)
            }

            VStack(spacing: 0) {
                ForEach(Array(committedMembers.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { RowDivider().padding(.leading, 78) }
                    memberRow(member)
                }
            }
            .glassCard(cornerRadius: 30)
        }
    }

    private func memberRow(_ member: Profile) -> some View {
        let plan = assignment(for: member.id)
        let timing = timingByUser[member.id]

        return HStack(spacing: 14) {
            Avatar(name: member.name, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(member.name)
                    .font(.display(.subheadline, .semibold))
                Text(rideDescription(for: member, plan: plan))
                    .font(.system(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let error = etaErrorByUser[member.id] {
                    Text(error)
                        .font(.system(.footnote))
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)

            if let timing, let plan {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.formatDuration(timing.total))
                        .font(.display(.title3))
                    Text(timeLabel(plan: plan, timing: timing))
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .padding(16)
    }

    private func timeLabel(plan: RideAssignment, timing: Timing) -> String {
        let start = item.proposal.startsAt
        switch plan.mode {
        case .driving:
            return String(localized: "Leave \(start.addingTimeInterval(-timing.total).formatted(date: .omitted, time: .shortened))")
        case .pickedUp:
            let pickup = start.addingTimeInterval(-(timing.pickupToGym ?? timing.total))
            return String(localized: "Ready \(pickup.formatted(date: .omitted, time: .shortened))")
        }
    }

    private func rideDescription(for member: Profile, plan: RideAssignment?) -> String {
        guard let plan else { return String(localized: "Hasn't set a ride yet") }
        switch plan.mode {
        case .driving:
            let from = plan.startAddress ?? String(localized: "an unknown address")
            return String(localized: "Driving from \(from)")
        case .pickedUp:
            let driverName = committedMembers.first { $0.id == plan.driverId }?.name.split(separator: " ").first.map(String.init) ?? String(localized: "someone")
            let from = plan.startAddress ?? String(localized: "an unknown address")
            return String(localized: "\(driverName) picks up at \(from)")
        }
    }

    // MARK: Logic

    private func loadExisting() async {
        do {
            try await supabase.fetchRideAssignments(forProposalIds: [item.id])
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        if let userId = supabase.currentUserId, let mine = assignment(for: userId) {
            myMode = mine.mode
            selectedDriverId = mine.driverId
            startAddressText = mine.startAddress ?? ""
        }
        if currentGroup.hasGymLocation, !ProcessInfo.processInfo.isLowPowerModeEnabled {
            await calculateETAs()
        }
    }

    private func saveGymLocation() async {
        isSavingGymLocation = true
        errorMessage = nil
        do {
            let coordinate = try await ETACalculator.geocode(address: gymAddressText)
            try await supabase.updateGymLocation(
                groupId: group.id,
                address: gymAddressText,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            if let refreshed = supabase.myGroups.first(where: { $0.id == group.id }) {
                currentGroup = refreshed
            }
            isEditingGym = false
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        isSavingGymLocation = false
    }

    private func saveMyRide() async {
        isSavingRide = true
        errorMessage = nil
        do {
            let coordinate = try await ETACalculator.geocode(address: startAddressText)
            try await supabase.setRideAssignment(
                proposalId: item.id,
                mode: myMode,
                driverId: selectedDriverId,
                startAddress: startAddressText,
                startLatitude: coordinate.latitude,
                startLongitude: coordinate.longitude
            )
            await calculateETAs()
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        isSavingRide = false
    }

    private enum ETAPlanError: LocalizedError {
        case missingStart
        case waitingOnDriver

        var errorDescription: String? {
            switch self {
            case .missingStart: return String(localized: "No starting address set.")
            case .waitingOnDriver: return String(localized: "Waiting on the driver's starting address.")
            }
        }
    }

    /// Looks up each committed member's ride, then resolves ETAs two at a time
    /// so a crew of five doesn't fire ten MapKit direction requests at once on
    /// a thermally tight iPhone Air.
    private func calculateETAs() async {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            errorMessage = String(localized: "Your iPhone is cooling down — try ETAs again in a minute.")
            return
        default: break
        }
        guard let gymLatitude = currentGroup.gymLatitude, let gymLongitude = currentGroup.gymLongitude else {
            errorMessage = String(localized: "Set the gym location first.")
            return
        }
        let gym = CLLocationCoordinate2D(latitude: gymLatitude, longitude: gymLongitude)

        isCalculatingETAs = true
        errorMessage = nil
        timingByUser = [:]
        etaErrorByUser = [:]
        defer { isCalculatingETAs = false }

        // Snapshot what each member needs before fanning out, so the
        // concurrent tasks below don't have to touch `self`.
        let plansByMember: [(id: UUID, plan: RideAssignment)] = committedMembers.compactMap { member in
            assignment(for: member.id).map { (member.id, $0) }
        }
        let plansByUserId = Dictionary(uniqueKeysWithValues: assignments.map { ($0.userId, $0) })

        await withTaskGroup(of: (UUID, Result<Timing, Error>).self) { group in
            var next = 0
            func enqueue() {
                guard next < plansByMember.count else { return }
                let (memberId, plan) = plansByMember[next]
                next += 1
                group.addTask {
                    do {
                        switch plan.mode {
                        case .driving:
                            guard let start = plan.startCoordinate else {
                                return (memberId, .failure(ETAPlanError.missingStart))
                            }
                            let origin = CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)
                            let total = try await ETACalculator.travelTime(from: origin, to: gym)
                            return (memberId, .success(Timing(total: total, pickupToGym: nil)))

                        case .pickedUp:
                            guard let driverId = plan.driverId, let driverPlan = plansByUserId[driverId],
                                  let driverStart = driverPlan.startCoordinate, let pickup = plan.startCoordinate else {
                                return (memberId, .failure(ETAPlanError.waitingOnDriver))
                            }
                            let driverOrigin = CLLocationCoordinate2D(latitude: driverStart.latitude, longitude: driverStart.longitude)
                            let pickupPoint = CLLocationCoordinate2D(latitude: pickup.latitude, longitude: pickup.longitude)
                            async let leg1 = ETACalculator.travelTime(from: driverOrigin, to: pickupPoint)
                            async let leg2 = ETACalculator.travelTime(from: pickupPoint, to: gym)
                            let (l1, l2) = try await (leg1, leg2)
                            return (memberId, .success(Timing(total: l1 + l2, pickupToGym: l2)))
                        }
                    } catch {
                        return (memberId, .failure(error))
                    }
                }
            }

            for _ in 0..<min(2, plansByMember.count) { enqueue() }

            for await (memberId, result) in group {
                switch result {
                case .success(let timing):
                    timingByUser[memberId] = timing
                case .failure(let error):
                    if !error.isCancellation { etaErrorByUser[memberId] = error.localizedDescription }
                }
                enqueue()
            }
        }
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return String(localized: "\(minutes) min") }
        return String(localized: "\(minutes / 60)h \(minutes % 60)m")
    }
}
