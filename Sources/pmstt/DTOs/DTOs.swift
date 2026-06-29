import Foundation
import Vapor

extension KeyedDecodingContainer {
	func decodeIfPresent<T: Decodable>(
		_ type: T.Type,
		forKey key: Key,
		default defaultValue: T
	) throws -> T {
		try decodeIfPresent(type, forKey: key) ?? defaultValue
	}
}

struct RegisterRequest: Content {
	let email: String
	let password: String
	let displayName: String?
}

struct LoginRequest: Content {
	let email: String
	let password: String
}

struct RefreshRequest: Content {
	let refreshToken: String
}

struct AppleSignInRequest: Content {
	let identityToken: String
	let displayName: String?
}

struct TokenResponse: Content {
	let accessToken: String
	let refreshToken: String
	let user: UserAccountResponse
}

struct UserAccountResponse: Content {
	let id: UUID
	let email: String?
	let displayName: String
	let createdAt: Date?
}

struct UpdateAccountRequest: Content {
	let displayName: String?
	let email: String?
}

struct UpdateSettingsRequest: Content {
	var liveActivitiesEnabled: Bool
	var liveActivityStartTime: TimeOfDay
	var liveActivityEndTime: TimeOfDay
	var liveActivityWeekdays: Set<SchoolWeekday>
	var showBreaksInLiveActivity: Bool
	var showNextSubjectInLiveActivity: Bool
	var widgetShowsReceivedTimetables: Bool
	var spotlightIndexingEnabled: Bool
	var siriAccessEnabled: Bool
	var notificationsEnabled: Bool

	static let `default` = UpdateSettingsRequest(
		liveActivitiesEnabled: true,
		liveActivityStartTime: TimeOfDay(hour: 8, minute: 0),
		liveActivityEndTime: TimeOfDay(hour: 15, minute: 40),
		liveActivityWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
		showBreaksInLiveActivity: true,
		showNextSubjectInLiveActivity: true,
		widgetShowsReceivedTimetables: true,
		spotlightIndexingEnabled: true,
		siriAccessEnabled: true,
		notificationsEnabled: false
	)

	var accountSettings: AccountSettings {
		AccountSettings(
			liveActivitiesEnabled: liveActivitiesEnabled,
			liveActivityStartTime: liveActivityStartTime,
			liveActivityEndTime: liveActivityEndTime,
			liveActivityWeekdays: liveActivityWeekdays,
			showBreaksInLiveActivity: showBreaksInLiveActivity,
			showNextSubjectInLiveActivity: showNextSubjectInLiveActivity,
			widgetShowsReceivedTimetables: widgetShowsReceivedTimetables,
			spotlightIndexingEnabled: spotlightIndexingEnabled,
			siriAccessEnabled: siriAccessEnabled,
			notificationsEnabled: notificationsEnabled
		)
	}
}

extension UpdateSettingsRequest {
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let defaults = Self.default

		liveActivitiesEnabled = try container.decodeIfPresent(
			Bool.self,
			forKey: .liveActivitiesEnabled,
			default: defaults.liveActivitiesEnabled
		)
		liveActivityStartTime = try container.decodeIfPresent(TimeOfDay.self, forKey: .liveActivityStartTime, default: defaults.liveActivityStartTime)
		liveActivityEndTime = try container.decodeIfPresent(TimeOfDay.self, forKey: .liveActivityEndTime, default: defaults.liveActivityEndTime)
		liveActivityWeekdays = try container.decodeIfPresent(Set<SchoolWeekday>.self, forKey: .liveActivityWeekdays, default: defaults.liveActivityWeekdays)
		showBreaksInLiveActivity = try container.decodeIfPresent(Bool.self, forKey: .showBreaksInLiveActivity, default: defaults.showBreaksInLiveActivity)
		showNextSubjectInLiveActivity = try container.decodeIfPresent(Bool.self, forKey: .showNextSubjectInLiveActivity, default: defaults.showNextSubjectInLiveActivity)
		widgetShowsReceivedTimetables = try container.decodeIfPresent(Bool.self, forKey: .widgetShowsReceivedTimetables, default: defaults.widgetShowsReceivedTimetables)
		spotlightIndexingEnabled = try container.decodeIfPresent(Bool.self, forKey: .spotlightIndexingEnabled, default: defaults.spotlightIndexingEnabled)
		siriAccessEnabled = try container.decodeIfPresent(Bool.self, forKey: .siriAccessEnabled, default: defaults.siriAccessEnabled)
		notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled, default: defaults.notificationsEnabled)
	}
}

struct TimetableSlotDTO: Content, Hashable {
	let day: Int
	let session: Int
}

struct TimetableColorDTO: Content {
	let r: Double
	let g: Double
	let b: Double
	let a: Double
}

struct TimetableSubjectDTO: Content {
	let id: String
	let symbol: String
	let colour: TimetableColorDTO
	let slots: [TimetableSlotDTO]
}

struct OwnerTimetableUpdateRequest: Content {
	let subjects: [TimetableSubjectDTO]
	let expectedRevision: Int?
}

struct OwnerTimetableResponse: Content {
	let subjects: [TimetableSubjectDTO]
	let revision: Int
	let updatedAt: Date?
}

struct ReceivedPassMirrorDTO: Content {
	let id: String
	let issuerAccountID: String
	let sourceKind: SourceKind
	let signedDisplayName: String
	let authorDisplayName: String?
	let subjects: [TimetableSubjectDTO]
	let receivedAt: Date
	let passUpdatedAt: Date
	let isDeleted: Bool
	let walletRevision: Int
}

struct ReceivedProjectionUpdateRequest: Content {
	let timetables: [ReceivedPassMirrorDTO]
	let walletRevision: Int
}

struct ReceivedNameOverrideResponse: Content {
	let serialNumber: String
	let displayName: String
}

struct UpdateReceivedNameOverrideRequest: Content {
	let displayName: String
}

struct ReportUserRequest: Content {
	let reportedAccountID: String
}
