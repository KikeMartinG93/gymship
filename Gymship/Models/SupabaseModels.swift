import Foundation

// MARK: - Database row models (Codable, snake_case columns via CodingKeys)

/// Public @handle: 3–20 lowercase letters, numbers, or underscores.
enum GymshipHandle {
    static let minLength = 3
    static let maxLength = 20

    static func sanitize(_ raw: String) -> String {
        var result = ""
        result.reserveCapacity(min(raw.count, maxLength))
        for scalar in raw.lowercased().folding(options: .diacriticInsensitive, locale: .current).unicodeScalars {
            let isLetter = scalar.value >= 97 && scalar.value <= 122
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            if isLetter || isDigit || scalar == "_" {
                result.unicodeScalars.append(scalar)
                if result.count == maxLength { break }
            }
        }
        return result
    }

    static func isValid(_ handle: String) -> Bool {
        handle.count >= minLength && handle == sanitize(handle)
    }
}

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var handle: String
    var name: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, handle, name
        case createdAt = "created_at"
    }
}

struct Group: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var ownerId: UUID
    var inviteCode: String
    var createdAt: Date?
    var workoutDurationMinutes: Int
    var gymAddress: String?
    var gymLatitude: Double?
    var gymLongitude: Double?

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerId = "owner_id"
        case inviteCode = "invite_code"
        case createdAt = "created_at"
        case workoutDurationMinutes = "workout_duration_minutes"
        case gymAddress = "gym_address"
        case gymLatitude = "gym_latitude"
        case gymLongitude = "gym_longitude"
    }

    static let maxMembers = 5

    /// The lengths a group can propose workouts for: 1hr, 2hr, 2.5hr.
    static let allowedDurationsMinutes = [60, 120, 150]

    var hasGymLocation: Bool {
        gymLatitude != nil && gymLongitude != nil
    }
}

struct GroupMember: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let groupId: UUID
    let userId: UUID
    var joinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

/// A row in `busy_slots`, synced from a member's device-local `BusySlot`s.
struct BusySlotRow: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    let groupId: UUID?
    var startsAt: Date
    var endsAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case groupId = "group_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case updatedAt = "updated_at"
    }

    init(id: UUID = UUID(), userId: UUID, groupId: UUID?, startsAt: Date, endsAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.groupId = groupId
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Insert payloads (omit server-generated columns)

struct ProfileInsert: Codable, Sendable {
    let id: UUID
    let handle: String
    let name: String
}

struct GroupInsert: Codable, Sendable {
    let name: String
    let ownerId: UUID
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case name
        case ownerId = "owner_id"
        case inviteCode = "invite_code"
    }
}

struct GroupMemberInsert: Codable, Sendable {
    let groupId: UUID
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case userId = "user_id"
    }
}

struct BusySlotInsert: Codable, Sendable {
    let id: UUID
    let userId: UUID
    let groupId: UUID?
    let startsAt: Date
    let endsAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case groupId = "group_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }
}

// MARK: - Workout proposals & RSVPs

enum ResponseStatus: String, Codable, Sendable {
    case accepted
    case declined
    case pending
}

struct WorkoutProposal: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let groupId: UUID
    let createdBy: UUID
    var title: String
    var startsAt: Date
    var endsAt: Date
    var createdAt: Date?
    var isSuggested: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case createdBy = "created_by"
        case title
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case createdAt = "created_at"
        case isSuggested = "is_suggested"
    }

    var interval: DateInterval {
        DateInterval(start: startsAt, end: endsAt)
    }
}

struct WorkoutProposalInsert: Codable, Sendable {
    let groupId: UUID
    let createdBy: UUID
    let title: String
    let startsAt: Date
    let endsAt: Date
    let isSuggested: Bool

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case createdBy = "created_by"
        case title
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case isSuggested = "is_suggested"
    }
}

struct WorkoutResponse: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let proposalId: UUID
    let userId: UUID
    var status: ResponseStatus
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case proposalId = "proposal_id"
        case userId = "user_id"
        case status
        case updatedAt = "updated_at"
    }
}

struct WorkoutResponseUpsert: Codable, Sendable {
    let proposalId: UUID
    let userId: UUID
    let status: ResponseStatus

    enum CodingKeys: String, CodingKey {
        case proposalId = "proposal_id"
        case userId = "user_id"
        case status
    }
}

// MARK: - Ride coordination (ETA once a workout is committed to)

enum RideMode: String, Codable, Sendable {
    case driving
    case pickedUp = "picked_up"
}

struct RideAssignment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let proposalId: UUID
    let userId: UUID
    var mode: RideMode
    var driverId: UUID?
    var startAddress: String?
    var startLatitude: Double?
    var startLongitude: Double?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case proposalId = "proposal_id"
        case userId = "user_id"
        case mode
        case driverId = "driver_id"
        case startAddress = "start_address"
        case startLatitude = "start_latitude"
        case startLongitude = "start_longitude"
        case updatedAt = "updated_at"
    }

    var startCoordinate: (latitude: Double, longitude: Double)? {
        guard let startLatitude, let startLongitude else { return nil }
        return (startLatitude, startLongitude)
    }
}

struct RideAssignmentUpsert: Codable, Sendable {
    let proposalId: UUID
    let userId: UUID
    let mode: RideMode
    let driverId: UUID?
    let startAddress: String?
    let startLatitude: Double?
    let startLongitude: Double?

    enum CodingKeys: String, CodingKey {
        case proposalId = "proposal_id"
        case userId = "user_id"
        case mode
        case driverId = "driver_id"
        case startAddress = "start_address"
        case startLatitude = "start_latitude"
        case startLongitude = "start_longitude"
    }
}

/// A proposal enriched with its group's name, used wherever proposals from
/// multiple groups are shown together (e.g. the Groups tab).
struct ProposalWithGroup: Identifiable, Hashable, Sendable {
    let proposal: WorkoutProposal
    let groupName: String

    var id: UUID { proposal.id }
}
