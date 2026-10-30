import AuthenticationServices
import Foundation
import Observation
import Supabase

/// Thin, app-facing wrapper around the Supabase Swift SDK: auth, profile,
/// groups, busy-slot sync, workout proposals/RSVPs, and Realtime subscriptions.
@Observable
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private(set) var currentUserId: UUID?
    private(set) var profile: Profile?

    /// Every group the signed-in user is a member of.
    private(set) var myGroups: [Group] = []

    /// Upcoming proposals across all of `myGroups`, newest-starting first.
    private(set) var myProposals: [ProposalWithGroup] = []

    /// The current user's own RSVP status per proposal id.
    private(set) var myResponses: [UUID: ResponseStatus] = [:]

    private(set) var groupMembers: [Profile] = []
    private(set) var groupBusySlots: [BusySlotRow] = []

    /// Who has committed (accepted) to each proposal, keyed by proposal id.
    /// A proposal only becomes a real "Committed Workout" once at least two
    /// people show up here.
    private(set) var commitments: [UUID: [Profile]] = [:]

    /// Each committed member's ride plan for a proposal, keyed by proposal id.
    private(set) var rideAssignments: [UUID: [RideAssignment]] = [:]

    var lastError: String?

    /// Coalesces the Plan/Crews home fetch so flipping tabs doesn't fire three
    /// identical round-trips at once.
    @ObservationIgnored private var inFlightHomeRefresh: Task<Void, Error>?

    #if DEBUG
    /// Set by `-GymshipDemo`: serves canned data so the UI can be reviewed
    /// in the simulator without signing in. Never compiled into release builds.
    private(set) var isDemo = false
    #endif

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

    private init() {
        client = SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.anonKey)
    }

    // MARK: - Auth (Google)

    /// Restores a previously-established session if one exists, and loads the user's profile.
    func restoreSession() async {
        guard let session = try? await client.auth.session else { return }
        currentUserId = session.user.id
        _ = try? await fetchProfile()
    }

    /// Signs out of Supabase and clears every bit of in-memory app state,
    /// as if the app had just been freshly installed. Used by Settings'
    /// "Reset to Factory Defaults" (testing only) — this does not delete
    /// anything from the backend, only this device's local session/state.
    func resetLocalState() async {
        try? await client.auth.signOut()
        currentUserId = nil
        profile = nil
        myGroups = []
        myProposals = []
        myResponses = [:]
        groupMembers = []
        groupBusySlots = []
        commitments = [:]
        lastError = nil
    }

    /// Opens Google via `ASWebAuthenticationSession`, exchanges the result for a
    /// Supabase session, then loads or creates a profile. Works on sideloaded
    /// builds — unlike Sign in with Apple, this is not an Apple-gated entitlement.
    @discardableResult
    func signInWithGoogle() async throws -> Session {
        let session = try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: SupabaseConfig.redirectURL
        ) { webSession in
            webSession.prefersEphemeralWebBrowserSession = false
        }
        currentUserId = session.user.id
        try await ensureProfile(from: session)
        return session
    }

    /// Loads the existing profile or creates one, auto-generating a unique handle.
    private func ensureProfile(from session: Session) async throws {
        if try await fetchProfile() != nil { return }

        var resolvedName: String?
        let metadata = session.user.userMetadata
        resolvedName = metadata["full_name"]?.stringValue ?? metadata["name"]?.stringValue
        if resolvedName == nil || resolvedName?.isEmpty == true {
            if let email = session.user.email, !email.hasSuffix("privaterelay.appleid.com") {
                resolvedName = email.split(separator: "@").first.map(String.init)
            }
        }
        if resolvedName == nil || resolvedName?.isEmpty == true {
            resolvedName = String(localized: "Athlete")
        }

        let handle = try await generateUniqueHandle(from: resolvedName!)
        try await createProfile(handle: handle, name: resolvedName!)
    }

    /// Picks an available `[a-z0-9]{3,20}` handle stem derived from `name`,
    /// appending a numeric suffix if it's already taken.
    private func generateUniqueHandle(from name: String) async throws -> String {
        let folded = name
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
        var stem = String(String.UnicodeScalarView(folded).prefix(16))
        if stem.count < 3 { stem = "athlete" }

        var candidate = stem
        var attempt = 0
        while try await findProfile(byHandle: candidate) != nil {
            attempt += 1
            let suffix = String(attempt)
            candidate = String(stem.prefix(max(3, 16 - suffix.count))) + suffix
        }
        return candidate
    }

    // MARK: - Profile

    func createProfile(handle: String, name: String) async throws {
        guard let userId = currentUserId else { throw SupabaseServiceError.notSignedIn }
        let normalizedHandle = handle.lowercased()
        if try await findProfile(byHandle: normalizedHandle) != nil {
            throw SupabaseServiceError.handleTaken
        }
        let insert = ProfileInsert(id: userId, handle: normalizedHandle, name: name)
        do {
            let saved: Profile = try await client
                .from("profiles")
                .insert(insert)
                .select()
                .single()
                .execute()
                .value
            self.profile = saved
        } catch {
            if let postgrestError = error as? PostgrestError, postgrestError.code == "23505" {
                throw SupabaseServiceError.handleTaken
            }
            throw error
        }
    }

    /// Updates the current user's profile name and/or handle. Throws
    /// `.handleTaken` if the new handle is already used by someone else.
    func updateProfile(handle: String, name: String) async throws {
        guard let userId = currentUserId else { throw SupabaseServiceError.notSignedIn }
        let normalizedHandle = handle.lowercased()
        if let existing = try await findProfile(byHandle: normalizedHandle), existing.id != userId {
            throw SupabaseServiceError.handleTaken
        }
        struct ProfileUpdate: Encodable { let handle: String; let name: String }
        do {
            let saved: Profile = try await client
                .from("profiles")
                .update(ProfileUpdate(handle: normalizedHandle, name: name))
                .eq("id", value: userId)
                .select()
                .single()
                .execute()
                .value
            self.profile = saved
        } catch {
            if let postgrestError = error as? PostgrestError, postgrestError.code == "23505" {
                throw SupabaseServiceError.handleTaken
            }
            throw error
        }
    }

    func fetchProfile() async throws -> Profile? {
        guard let userId = currentUserId else { return nil }
        let result: [Profile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .execute()
            .value
        self.profile = result.first
        return result.first
    }

    /// Looks up a profile by @handle, used when adding members to a group.
    func findProfile(byHandle handle: String) async throws -> Profile? {
        let result: [Profile] = try await client
            .from("profiles")
            .select()
            .eq("handle", value: handle.lowercased())
            .execute()
            .value
        return result.first
    }

    // MARK: - Groups

    /// Creates a new group owned by the current user (max 5 members enforced
    /// server-side; see `Docs/supabase_schema.sql`).
    @discardableResult
    func createGroup(name: String) async throws -> Group {
        guard let userId = currentUserId else { throw SupabaseServiceError.notSignedIn }
        let insert = GroupInsert(name: name, ownerId: userId, inviteCode: Self.generateInviteCode())
        let group: Group = try await client
            .from("groups")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value

        try await joinGroup(groupId: group.id)
        try await fetchMyGroups()
        return group
    }

    /// Joins an existing group using its invite code. Enforces the 5-member
    /// cap by checking current membership count before inserting.
    @discardableResult
    func joinGroup(withInviteCode inviteCode: String) async throws -> Group {
        let matches: [Group] = try await client
            .from("groups")
            .select()
            .eq("invite_code", value: inviteCode.uppercased())
            .execute()
            .value

        guard let group = matches.first else { throw SupabaseServiceError.groupNotFound }

        let members: [GroupMember] = try await client
            .from("group_members")
            .select()
            .eq("group_id", value: group.id)
            .execute()
            .value

        guard members.count < Group.maxMembers else { throw SupabaseServiceError.groupFull }

        try await joinGroup(groupId: group.id)
        try await fetchMyGroups()
        return group
    }

    private func joinGroup(groupId: UUID) async throws {
        guard let userId = currentUserId else { throw SupabaseServiceError.notSignedIn }
        let insert = GroupMemberInsert(groupId: groupId, userId: userId)
        try await client
            .from("group_members")
            .insert(insert)
            .execute()
    }

    /// Refreshes `myGroups` with every group the signed-in user belongs to.
    @discardableResult
    func fetchMyGroups() async throws -> [Group] {
        #if DEBUG
        if isDemo { return myGroups }
        #endif
        guard let userId = currentUserId else { return [] }
        struct MembershipRow: Codable {
            let groups: Group
        }
        let rows: [MembershipRow] = try await client
            .from("group_members")
            .select("groups(*)")
            .eq("user_id", value: userId)
            .execute()
            .value
        let groups = rows.map(\.groups).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.myGroups = groups
        return groups
    }

    /// Groups, proposals, and commitments in one coalesced pass so Plan and
    /// Crews don't each fire the same three requests when you flip tabs.
    func refreshHomeData() async throws {
        if let inFlight = inFlightHomeRefresh {
            try await inFlight.value
            return
        }
        let task = Task { @MainActor in
            try await fetchMyGroups()
            try await refreshMyProposals()
            try await fetchCommitments(forProposalIds: myProposals.map(\.id))
        }
        inFlightHomeRefresh = task
        defer { inFlightHomeRefresh = nil }
        try await task.value
    }

    @discardableResult
    func fetchGroupMembers(groupId: UUID) async throws -> [Profile] {
        #if DEBUG
        if isDemo { return groupMembers }
        #endif
        struct MemberProfileRow: Codable {
            let profiles: Profile
        }
        let rows: [MemberProfileRow] = try await client
            .from("group_members")
            .select("profiles(*)")
            .eq("group_id", value: groupId)
            .execute()
            .value
        let members = rows.map(\.profiles)
        self.groupMembers = members
        return members
    }

    /// Updates a group's default workout length (60/120/150 minutes), used
    /// by the Apple Intelligence slot finder.
    func updateGroupDuration(groupId: UUID, minutes: Int) async throws {
        struct DurationUpdate: Encodable { let workout_duration_minutes: Int }
        try await client
            .from("groups")
            .update(DurationUpdate(workout_duration_minutes: minutes))
            .eq("id", value: groupId)
            .execute()

        if let index = myGroups.firstIndex(where: { $0.id == groupId }) {
            myGroups[index].workoutDurationMinutes = minutes
        }
    }

    /// Sets (or updates) a group's gym location, geocoded client-side. Used
    /// as the destination for everyone's ETA once a workout is committed to.
    func updateGymLocation(groupId: UUID, address: String, latitude: Double, longitude: Double) async throws {
        struct GymLocationUpdate: Encodable {
            let gym_address: String
            let gym_latitude: Double
            let gym_longitude: Double
        }
        try await client
            .from("groups")
            .update(GymLocationUpdate(gym_address: address, gym_latitude: latitude, gym_longitude: longitude))
            .eq("id", value: groupId)
            .execute()

        if let index = myGroups.firstIndex(where: { $0.id == groupId }) {
            myGroups[index].gymAddress = address
            myGroups[index].gymLatitude = latitude
            myGroups[index].gymLongitude = longitude
        }
    }

    private static func generateInviteCode(length: Int = 6) -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    // MARK: - Busy slot sync

    /// Replaces the device's locally-extracted busy slots for a single group,
    /// so different groups can be synced with (potentially) different
    /// availability. Call once per group the user wants to update.
    /// Syncs the given busy slots to every group the user is a member of.
    /// Called automatically whenever the device's busy slots change, so
    /// there's no per-group "sync" step for the user to remember.
    func syncBusySlotsToAllGroups(_ slots: [BusySlot]) async throws {
        try await fetchMyGroups()
        for group in myGroups {
            try await syncBusySlots(slots, toGroup: group.id)
        }
    }

    func syncBusySlots(_ slots: [BusySlot], toGroup groupId: UUID) async throws {
        guard let userId = currentUserId else { throw SupabaseServiceError.notSignedIn }

        try await client
            .from("busy_slots")
            .delete()
            .eq("user_id", value: userId)
            .eq("group_id", value: groupId)
            .execute()

        guard !slots.isEmpty else { return }

        let inserts = slots.map {
            BusySlotInsert(id: $0.id, userId: userId, groupId: groupId, startsAt: $0.start, endsAt: $0.end)
        }
        try await client
            .from("busy_slots")
            .insert(inserts)
            .execute()
    }

    @discardableResult
    func fetchGroupBusySlots(groupId: UUID) async throws -> [BusySlotRow] {
        #if DEBUG
        if isDemo { return groupBusySlots }
        #endif
        let rows: [BusySlotRow] = try await client
            .from("busy_slots")
            .select()
            .eq("group_id", value: groupId)
            .execute()
            .value
        self.groupBusySlots = rows
        return rows
    }

    /// Marks the given time range busy for the user in every group *other*
    /// than `excludingGroupId` — used when a workout proposal is accepted so
    /// other groups see that time as unavailable.
    func markBusy(startsAt: Date, endsAt: Date, excludingGroupId: UUID) async throws {
        guard let userId = currentUserId else { throw SupabaseServiceError.notSignedIn }
        let others = myGroups.map(\.id).filter { $0 != excludingGroupId }
        guard !others.isEmpty else { return }
        let inserts = others.map {
            BusySlotInsert(id: UUID(), userId: userId, groupId: $0, startsAt: startsAt, endsAt: endsAt)
        }
        try await client.from("busy_slots").insert(inserts).execute()
    }

    /// Undoes `markBusy` for the same time range, e.g. when an acceptance is
    /// later declined or replaced by a conflicting choice.
    func clearBusy(startsAt: Date, endsAt: Date, excludingGroupId: UUID) async throws {
        guard let userId = currentUserId else { throw SupabaseServiceError.notSignedIn }
        let others = myGroups.map(\.id).filter { $0 != excludingGroupId }
        guard !others.isEmpty else { return }
        try await client
            .from("busy_slots")
            .delete()
            .eq("user_id", value: userId)
            .eq("starts_at", value: startsAt)
            .eq("ends_at", value: endsAt)
            .in("group_id", values: others)
            .execute()
    }

    // MARK: - Workout proposals & RSVPs

    /// Proposes a workout slot to a group. Manual proposals auto-accept the
    /// proposer; Apple-Intelligence-suggested ones are left pending for every
    /// member (including whoever triggered the search) to accept or decline.
    @discardableResult
    func createProposal(
        groupId: UUID,
        title: String,
        startsAt: Date,
        endsAt: Date,
        isSuggested: Bool = false
    ) async throws -> WorkoutProposal {
        guard let userId = currentUserId else { throw SupabaseServiceError.notSignedIn }
        let insert = WorkoutProposalInsert(
            groupId: groupId,
            createdBy: userId,
            title: title,
            startsAt: startsAt,
            endsAt: endsAt,
            isSuggested: isSuggested
        )
        let proposal: WorkoutProposal = try await client
            .from("workout_proposals")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value

        if !isSuggested {
            try await respond(to: proposal, status: .accepted, checkConflicts: false)
        }
        return proposal
    }

    /// Creates an Apple-Intelligence-suggested proposal for a day that
    /// doesn't have one yet. A unique index (`group_id`, day) means that if
    /// another member's device already inserted a suggestion for that same
    /// day, this insert is rejected (Postgres 23505) rather than creating a
    /// second, possibly-different suggestion — so the whole group converges
    /// on a single slot per day regardless of whose device computed it
    /// first. Returns `false` (not an error) when that happens.
    @discardableResult
    func createSuggestedProposal(groupId: UUID, title: String, startsAt: Date, endsAt: Date) async throws -> Bool {
        do {
            try await createProposal(groupId: groupId, title: title, startsAt: startsAt, endsAt: endsAt, isSuggested: true)
            return true
        } catch let error as PostgrestError where error.code == "23505" {
            return false
        }
    }

    func fetchProposals(groupId: UUID) async throws -> [WorkoutProposal] {
        let rows: [WorkoutProposal] = try await client
            .from("workout_proposals")
            .select()
            .eq("group_id", value: groupId)
            .gte("ends_at", value: Date())
            .order("starts_at", ascending: true)
            .execute()
            .value
        return rows
    }

    /// Proposals for a group within an explicit date range — unlike
    /// `fetchProposals(groupId:)`, which only returns upcoming ones, this
    /// also reaches into the past. Used to power the weekly history view.
    func fetchProposals(groupId: UUID, in range: DateInterval) async throws -> [WorkoutProposal] {
        let rows: [WorkoutProposal] = try await client
            .from("workout_proposals")
            .select()
            .eq("group_id", value: groupId)
            .gte("starts_at", value: range.start)
            .lt("starts_at", value: range.end)
            .order("starts_at", ascending: true)
            .execute()
            .value
        return rows
    }

    /// The calendar days within `range` (any range — past, current, or
    /// upcoming) that this user has personally committed (accepted) to a
    /// workout on, across every group. Unlike `myProposals`/`myResponses`,
    /// this isn't limited to upcoming proposals, so it also covers history —
    /// every proposal/response row is kept indefinitely, so past weeks stay
    /// available (up to however far back `range` reaches).
    func fetchMyCommittedDays(in range: DateInterval, calendar: Calendar = .current) async throws -> Set<Date> {
        #if DEBUG
        if isDemo {
            return Set(
                myProposals
                    .filter { myResponses[$0.id] == .accepted && range.contains($0.proposal.startsAt) }
                    .map { calendar.startOfDay(for: $0.proposal.startsAt) }
            )
        }
        #endif
        guard let userId = currentUserId else { return [] }

        var proposals: [WorkoutProposal] = []
        for group in myGroups {
            proposals.append(contentsOf: try await fetchProposals(groupId: group.id, in: range))
        }
        guard !proposals.isEmpty else { return [] }

        let ids = proposals.map(\.id)
        let responses: [WorkoutResponse] = try await client
            .from("workout_responses")
            .select()
            .eq("user_id", value: userId)
            .eq("status", value: ResponseStatus.accepted.rawValue)
            .in("proposal_id", values: ids)
            .execute()
            .value

        let acceptedIds = Set(responses.map(\.proposalId))
        let days = proposals
            .filter { acceptedIds.contains($0.id) }
            .map { calendar.startOfDay(for: $0.startsAt) }
        return Set(days)
    }

    /// Refreshes `myProposals` (upcoming, across all `myGroups`) and
    /// `myResponses` (this user's RSVP per proposal).
    func refreshMyProposals() async throws {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let userId = currentUserId else { return }

        var combined: [ProposalWithGroup] = []
        for group in myGroups {
            let proposals = try await fetchProposals(groupId: group.id)
            combined.append(contentsOf: proposals.map { ProposalWithGroup(proposal: $0, groupName: group.name) })
        }
        combined.sort { $0.proposal.startsAt < $1.proposal.startsAt }
        self.myProposals = combined

        guard !combined.isEmpty else {
            self.myResponses = [:]
            return
        }
        let ids = combined.map(\.id)
        let responses: [WorkoutResponse] = try await client
            .from("workout_responses")
            .select()
            .eq("user_id", value: userId)
            .in("proposal_id", values: ids)
            .execute()
            .value
        self.myResponses = Dictionary(uniqueKeysWithValues: responses.map { ($0.proposalId, $0.status) })
    }

    /// Records this user's RSVP for a proposal. Accepting also marks the
    /// slot busy in every other group; declining a previously-accepted slot
    /// clears that cross-group busy mark.
    func respond(to proposal: WorkoutProposal, status: ResponseStatus, checkConflicts: Bool = true) async throws {
        guard let userId = currentUserId else { throw SupabaseServiceError.notSignedIn }
        let wasAccepted = myResponses[proposal.id] == .accepted

        let upsert = WorkoutResponseUpsert(proposalId: proposal.id, userId: userId, status: status)
        try await client
            .from("workout_responses")
            .upsert(upsert, onConflict: "proposal_id,user_id")
            .execute()

        myResponses[proposal.id] = status

        // The RSVP itself already succeeded at this point; marking the slot
        // busy in the user's *other* groups is a courtesy for those groups'
        // conflict detection, not something that should turn a successful
        // "I'm in" into a visible error if, say, the network hiccups here.
        if status == .accepted, !wasAccepted {
            try? await markBusy(startsAt: proposal.startsAt, endsAt: proposal.endsAt, excludingGroupId: proposal.groupId)
        } else if status != .accepted, wasAccepted {
            try? await clearBusy(startsAt: proposal.startsAt, endsAt: proposal.endsAt, excludingGroupId: proposal.groupId)
        }
    }

    /// Finds an already-accepted proposal (other than `candidate`) whose time
    /// range overlaps it — used to prompt "which one will you attend?" when
    /// two groups propose overlapping workouts.
    func acceptedConflict(for candidate: ProposalWithGroup) -> ProposalWithGroup? {
        myProposals.first {
            $0.id != candidate.id
                && myResponses[$0.id] == .accepted
                && $0.proposal.interval.intersects(candidate.proposal.interval)
        }
    }

    /// Fetches who has committed to each of the given proposals in one
    /// batch, populating `commitments`. Called whenever a group's or the
    /// user's proposal list is refreshed, so every member sees the same
    /// up-to-date commitment roster.
    func fetchCommitments(forProposalIds proposalIds: [UUID]) async throws {
        #if DEBUG
        if isDemo { return }
        #endif
        guard !proposalIds.isEmpty else { return }
        struct ResponseProfileRow: Codable {
            let proposalId: UUID
            let profiles: Profile

            enum CodingKeys: String, CodingKey {
                case proposalId = "proposal_id"
                case profiles
            }
        }
        let rows: [ResponseProfileRow] = try await client
            .from("workout_responses")
            .select("proposal_id, profiles(*)")
            .in("proposal_id", values: proposalIds)
            .eq("status", value: ResponseStatus.accepted.rawValue)
            .execute()
            .value

        // Merge into the shared dict rather than replacing it, so a fetch
        // scoped to one group's proposals doesn't wipe out what other views
        // already know about other groups' proposals.
        var grouped: [UUID: [Profile]] = Dictionary(uniqueKeysWithValues: proposalIds.map { ($0, []) })
        for row in rows {
            grouped[row.proposalId, default: []].append(row.profiles)
        }
        for (id, profiles) in grouped {
            commitments[id] = profiles
        }
    }

    func commitCount(for proposalId: UUID) -> Int {
        commitments[proposalId]?.count ?? 0
    }

    /// A proposal only becomes a real "Committed Workout" once at least two
    /// people have committed to the same slot.
    func isConfirmedWorkout(_ proposalId: UUID) -> Bool {
        commitCount(for: proposalId) >= 2
    }

    // MARK: - Ride coordination

    /// Fetches every ride assignment for the given proposals in one batch,
    /// merging into `rideAssignments` (same merge-not-replace pattern as
    /// `fetchCommitments`, so this stays safe to call from any scope).
    func fetchRideAssignments(forProposalIds proposalIds: [UUID]) async throws {
        #if DEBUG
        if isDemo { return }
        #endif
        guard !proposalIds.isEmpty else { return }
        let rows: [RideAssignment] = try await client
            .from("ride_assignments")
            .select()
            .in("proposal_id", values: proposalIds)
            .execute()
            .value

        var grouped: [UUID: [RideAssignment]] = Dictionary(uniqueKeysWithValues: proposalIds.map { ($0, []) })
        for row in rows {
            grouped[row.proposalId, default: []].append(row)
        }
        for (id, assignments) in grouped {
            rideAssignments[id] = assignments
        }
    }

    /// Sets the current user's ride plan for a proposal: driving themselves
    /// from `startAddress`, or getting picked up by `driverId` from it.
    func setRideAssignment(
        proposalId: UUID,
        mode: RideMode,
        driverId: UUID?,
        startAddress: String,
        startLatitude: Double,
        startLongitude: Double
    ) async throws {
        guard let userId = currentUserId else { throw SupabaseServiceError.notSignedIn }
        let upsert = RideAssignmentUpsert(
            proposalId: proposalId,
            userId: userId,
            mode: mode,
            driverId: mode == .pickedUp ? driverId : nil,
            startAddress: startAddress,
            startLatitude: startLatitude,
            startLongitude: startLongitude
        )
        try await client
            .from("ride_assignments")
            .upsert(upsert, onConflict: "proposal_id,user_id")
            .execute()

        try await fetchRideAssignments(forProposalIds: [proposalId])
    }

    /// Only the members who accepted — the roster that should be treated as
    /// "confirmed" and synced/written to the calendar for this proposal.
    func fetchAcceptedParticipants(proposalId: UUID) async throws -> [Profile] {
        struct ResponseProfileRow: Codable {
            let profiles: Profile
        }
        let rows: [ResponseProfileRow] = try await client
            .from("workout_responses")
            .select("profiles(*)")
            .eq("proposal_id", value: proposalId)
            .eq("status", value: ResponseStatus.accepted.rawValue)
            .execute()
            .value
        return rows.map(\.profiles)
    }

    // MARK: - Realtime

    /// Subscribes to INSERT/UPDATE/DELETE changes on `busy_slots` for the
    /// given group and keeps `groupBusySlots` up to date live.
    func subscribeToGroupRealtime(groupId: UUID) {
        realtimeTask?.cancel()
        // Take the previous channel with us so switching crews (or
        // re-subscribing) doesn't leak a live subscription on the server —
        // cancelling the task alone stops us listening, but never tells
        // Supabase to actually close the socket's channel.
        let previousChannel = realtimeChannel
        realtimeChannel = nil
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            if let previousChannel { await previousChannel.unsubscribe() }
            guard !Task.isCancelled else { return }
            let channel = self.client.channel("group-\(groupId.uuidString)")
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "busy_slots",
                filter: "group_id=eq.\(groupId.uuidString)"
            )
            await channel.subscribe()
            self.realtimeChannel = channel

            for await _ in changes {
                if let refreshed = try? await self.fetchGroupBusySlots(groupId: groupId) {
                    self.groupBusySlots = refreshed
                }
            }
        }
    }

    func unsubscribeFromRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let channel = realtimeChannel {
            await channel.unsubscribe()
        }
        realtimeChannel = nil
    }
}

enum SupabaseServiceError: LocalizedError {
    case notSignedIn
    case groupNotFound
    case groupFull
    case handleTaken

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return String(localized: "You're not signed in yet.")
        case .groupNotFound: return String(localized: "No group matches that invite code.")
        case .groupFull: return String(localized: "This group already has the maximum of \(Group.maxMembers) members.")
        case .handleTaken: return String(localized: "That @handle is already taken. Try another one.")
        }
    }
}

#if DEBUG
extension SupabaseService {
    /// Seeds two crews, a handful of sessions (one locked, some pending) and
    /// their rosters. Launch with `-GymshipDemo` to use it.
    func loadDemoData() {
        isDemo = true

        let me = Profile(id: UUID(), handle: "enrique", name: "Enrique Martin", createdAt: nil)
        let andrea = Profile(id: UUID(), handle: "andrea", name: "Andrea Reyes", createdAt: nil)
        let kike = Profile(id: UUID(), handle: "kike", name: "Kike Martin", createdAt: nil)
        let sam = Profile(id: UUID(), handle: "sam", name: "Sam Okafor", createdAt: nil)

        currentUserId = me.id
        profile = me

        let iron = Group(
            id: UUID(), name: "Iron Sundays", ownerId: me.id, inviteCode: "IRON42", createdAt: nil,
            workoutDurationMinutes: 120, gymAddress: "500 Market St, San Francisco", gymLatitude: 37.7935, gymLongitude: -122.3963
        )
        let dawn = Group(
            id: UUID(), name: "Dawn Patrol", ownerId: sam.id, inviteCode: "DAWN07", createdAt: nil,
            workoutDurationMinutes: 60, gymAddress: nil, gymLatitude: nil, gymLongitude: nil
        )
        myGroups = [dawn, iron]
        groupMembers = [me, andrea, kike]

        let calendar = Calendar.current
        func slot(_ dayOffset: Int, _ hour: Int, _ minute: Int, minutes: Int) -> (Date, Date) {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date()))!
            let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            return (start, start.addingTimeInterval(TimeInterval(minutes * 60)))
        }
        func proposal(_ group: Group, _ title: String, _ when: (Date, Date), suggested: Bool) -> WorkoutProposal {
            WorkoutProposal(id: UUID(), groupId: group.id, createdBy: me.id, title: title, startsAt: when.0, endsAt: when.1, createdAt: nil, isSuggested: suggested)
        }

        let locked = proposal(iron, "Suggested workout", slot(1, 18, 30, minutes: 120), suggested: true)
        let pending = proposal(iron, "Suggested workout", slot(2, 7, 0, minutes: 120), suggested: true)
        let manual = proposal(iron, "Leg day", slot(3, 12, 15, minutes: 60), suggested: false)
        let dawnLocked = proposal(dawn, "Suggested workout", slot(4, 6, 0, minutes: 60), suggested: true)

        myProposals = [locked, pending, manual, dawnLocked].map {
            ProposalWithGroup(proposal: $0, groupName: $0.groupId == iron.id ? iron.name : dawn.name)
        }
        myResponses = [locked.id: .accepted, dawnLocked.id: .accepted]
        commitments = [
            locked.id: [me, andrea],
            pending.id: [kike],
            manual.id: [],
            dawnLocked.id: [me, sam, kike],
        ]

        let week = EventKitManager.currentWeekInterval()
        groupBusySlots = [me, andrea, sam].map {
            BusySlotRow(userId: $0.id, groupId: iron.id, startsAt: week.start, endsAt: week.start.addingTimeInterval(3600))
        }
    }
}
#endif

extension Error {
    /// True when a request was cancelled (the screen went away, or a newer
    /// refresh replaced it). That's expected and never worth showing the user.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        if let webAuth = self as? ASWebAuthenticationSessionError, webAuth.code == .canceledLogin {
            return true
        }
        return false
    }
}
