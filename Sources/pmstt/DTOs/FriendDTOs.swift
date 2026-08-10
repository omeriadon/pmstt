import Vapor

enum FriendRelationshipState: String, Content {
	case pendingOutgoing
	case pendingIncoming
	case friends
}

struct FriendProfileDTO: Content {
	let userID: UUID
	let displayName: String
	let email: String
	let appearanceData: Data?
	let appearance: ProfileAppearanceDTO
	let photo: ProfilePhotoMetadataDTO?
	let badges: [ProfileBadgeDTO]
	let revision: Int
}

struct FriendSummaryDTO: Content {
	let relationshipID: UUID
	let friend: FriendProfileDTO
	let state: FriendRelationshipState
	let requestedAt: Date
	let acceptedAt: Date?
	let timetable: FriendTimetableDTO?
	let locationStatus: LocationStatusItem?
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
	let averageArrivalSecondsSinceMidnight: Double?
	let locationNotificationPreferences: Set<LocationNotificationPreference>
}

struct FriendLocationNotificationPreferencesRequest: Content {
	let preferences: Set<LocationNotificationPreference>
}

struct FriendSearchResultDTO: Content {
	let profile: FriendProfileDTO
	let relationship: FriendRelationshipState?
}

struct CreateFriendRequest: Content {
	let userID: UUID
}

struct FriendshipDateChangeRequestDTO: Content {
	let requestedDate: Date
}

struct FriendProfileAppearanceUpdateRequest: Content {
	let appearance: ProfileAppearanceDTO
	let baseRevision: Int?
}
