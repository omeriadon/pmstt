import Vapor

enum FriendRelationshipState: String, Content {
	case pendingOutgoing
	case pendingIncoming
	case friends
}

struct FriendProfileDTO: Content {
	let userID: UUID
	let displayName: String
	let email: String?
	let appearanceData: Data?
}

struct FriendSummaryDTO: Content {
	let relationshipID: UUID
	let friend: FriendProfileDTO
	let state: FriendRelationshipState
	let requestedAt: Date
	let acceptedAt: Date?
	let timetable: FriendTimetableDTO?
}

struct FriendTimetableDTO: Content {
	let title: String
	let subjects: [TimetableSubjectDTO]
	let updatedAt: Date?
}

struct FriendDetailDTO: Content {
	let relationshipID: UUID
	let friend: FriendProfileDTO
	let acceptedAt: Date
	let timetable: FriendTimetableDTO?
}

struct FriendSearchResultDTO: Content {
	let profile: FriendProfileDTO
	let relationship: FriendRelationshipState?
}

struct CreateFriendRequest: Content {
	let schoolEmail: String
}

struct FriendProfileAppearanceUpdateRequest: Content {
	let appearanceData: Data
}
