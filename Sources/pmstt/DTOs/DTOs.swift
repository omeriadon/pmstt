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

struct ClientIdentity: Codable, Sendable {
	let platform: ClientPlatform.RawValue
	let installationID: String
}

struct RegisterRequest: Content {
	let email: String
	let password: String
	let displayName: String?
	let platform: ClientPlatform.RawValue
	let installationID: String
}

struct LoginRequest: Content {
	let email: String
	let password: String
	let platform: ClientPlatform.RawValue
	let installationID: String
}

struct RefreshRequest: Content {
	let refreshToken: String
}

struct TokenResponse: Content {
	let accessToken: String
	let refreshToken: String
	let user: UserAccountResponse
}

struct WatchSessionRequest: Content {
	let installationID: String
}

struct UserAccountResponse: Content {
	let id: UUID
	let email: String?
	let displayName: String
	let createdAt: Date?
	let authority: AccountAuthority
	let appearance: ProfileAppearanceDTO
	let photo: ProfilePhotoMetadataDTO?
	let badges: [ProfileBadgeDTO]
	let revision: Int
}

struct UpdateAccountRequest: Content {
	let displayName: String?
	let email: String?
	let baseRevision: Int?
}

struct UpdateSettingsRequest: Content {
	var liveActivitiesEnabled: Bool
	var highlightsCurrentDay: Bool
	var appFontDesign: AppFontDesign
	var notificationsEnabled: Bool
	var broadcastNotificationsEnabled: Bool
	var notificationLeadTimes: Set<NotificationLeadTime>
	var breakToPeriodNotificationLeadTimes: Set<NotificationLeadTime>
	var eventNotificationSchedules: Set<EventNotificationSchedule>
	var calendarEventAutoDeleteDays: Int
	var serverRevision: Int?

	static let `default` = UpdateSettingsRequest(
		liveActivitiesEnabled: true,
		highlightsCurrentDay: true,
		appFontDesign: .monospaced,
		notificationsEnabled: true,
		broadcastNotificationsEnabled: true,
		notificationLeadTimes: [.zero],
		breakToPeriodNotificationLeadTimes: [.zero],
		eventNotificationSchedules: [],
		calendarEventAutoDeleteDays: 0,
		serverRevision: nil
	)

	var accountSettings: AccountSettings {
		AccountSettings(
			liveActivitiesEnabled: liveActivitiesEnabled,
			highlightsCurrentDay: highlightsCurrentDay,
			appFontDesign: appFontDesign,
			notificationsEnabled: notificationsEnabled,
			broadcastNotificationsEnabled: broadcastNotificationsEnabled,
			notificationLeadTimes: notificationLeadTimes,
			breakToPeriodNotificationLeadTimes: breakToPeriodNotificationLeadTimes,
			eventNotificationSchedules: eventNotificationSchedules,
			calendarEventAutoDeleteDays: calendarEventAutoDeleteDays,
			serverRevision: serverRevision ?? 0
		)
	}
}

struct NotificationSettingsUpdateRequest: Content {
	let notificationsEnabled: Bool
	let broadcastNotificationsEnabled: Bool
	let notificationLeadTimes: Set<NotificationLeadTime>
	let breakToPeriodNotificationLeadTimes: Set<NotificationLeadTime>
	let eventNotificationSchedules: Set<EventNotificationSchedule>
	let serverRevision: Int?
}

extension NotificationSettingsUpdateRequest {
	private enum LegacyCodingKeys: String, CodingKey {
		case notificationLeadTime
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
		broadcastNotificationsEnabled = try container.decode(Bool.self, forKey: .broadcastNotificationsEnabled)
		if let leadTimes = try container.decodeIfPresent(Set<NotificationLeadTime>.self, forKey: .notificationLeadTimes) {
			notificationLeadTimes = leadTimes
		} else if let legacyLeadTime = try decoder.container(keyedBy: LegacyCodingKeys.self).decodeIfPresent(NotificationLeadTime.self, forKey: .notificationLeadTime) {
			notificationLeadTimes = [legacyLeadTime]
		} else {
			notificationLeadTimes = AccountSettings.default.notificationLeadTimes
		}
		breakToPeriodNotificationLeadTimes = try container.decodeIfPresent(Set<NotificationLeadTime>.self, forKey: .breakToPeriodNotificationLeadTimes) ?? AccountSettings.default.breakToPeriodNotificationLeadTimes
		eventNotificationSchedules = try container.decodeIfPresent(Set<EventNotificationSchedule>.self, forKey: .eventNotificationSchedules) ?? AccountSettings.default.eventNotificationSchedules
		serverRevision = try container.decodeIfPresent(Int.self, forKey: .serverRevision)
	}
}

extension UpdateSettingsRequest {
	private enum LegacyCodingKeys: String, CodingKey {
		case notificationLeadTime
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let defaults = Self.default

		liveActivitiesEnabled = try container.decodeIfPresent(
			Bool.self,
			forKey: .liveActivitiesEnabled,
			default: defaults.liveActivitiesEnabled
		)
		highlightsCurrentDay = try container.decodeIfPresent(Bool.self, forKey: .highlightsCurrentDay, default: defaults.highlightsCurrentDay)
		appFontDesign = try container.decodeIfPresent(AppFontDesign.self, forKey: .appFontDesign, default: defaults.appFontDesign)
		notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled, default: defaults.notificationsEnabled)
		broadcastNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .broadcastNotificationsEnabled, default: defaults.broadcastNotificationsEnabled)
		if let leadTimes = try container.decodeIfPresent(Set<NotificationLeadTime>.self, forKey: .notificationLeadTimes) {
			notificationLeadTimes = leadTimes
		} else if let legacyLeadTime = try decoder.container(keyedBy: LegacyCodingKeys.self).decodeIfPresent(NotificationLeadTime.self, forKey: .notificationLeadTime) {
			notificationLeadTimes = [legacyLeadTime]
		} else {
			notificationLeadTimes = defaults.notificationLeadTimes
		}
		breakToPeriodNotificationLeadTimes = try container.decodeIfPresent(Set<NotificationLeadTime>.self, forKey: .breakToPeriodNotificationLeadTimes) ?? defaults.breakToPeriodNotificationLeadTimes
		eventNotificationSchedules = try container.decodeIfPresent(Set<EventNotificationSchedule>.self, forKey: .eventNotificationSchedules) ?? defaults.eventNotificationSchedules
		calendarEventAutoDeleteDays = try container.decodeIfPresent(Int.self, forKey: .calendarEventAutoDeleteDays) ?? defaults.calendarEventAutoDeleteDays
		serverRevision = try container.decodeIfPresent(Int.self, forKey: .serverRevision)
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

enum TimetableClassroomDTO: Content, Hashable {
	case room(building: Building, floor: Floor?, number: Int)
	case unknown(rawLocation: String)

	enum Building: String, Content, Hashable {
		case mills
		case andrews
		case beasley
		case gardham
		case embletonMusicCentre
		case stokes

		var displayName: String {
			switch self {
				case .mills: "Mills"
				case .andrews: "Andrews"
				case .beasley: "Beasley"
				case .gardham: "Gardham"
				case .embletonMusicCentre: "Embleton Music Centre"
				case .stokes: "Stokes"
			}
		}
	}

	enum Floor: String, Content, Hashable {
		case upper
		case lower

		var displayName: String {
			rawValue.capitalized
		}
	}

	var displayName: String {
		switch self {
			case let .room(building, floor, number):
				if let floor {
					"\(building.displayName), \(floor.displayName), \(number)"
				} else {
					"\(building.displayName), \(number)"
				}
			case let .unknown(rawLocation): rawLocation
		}
	}
}

enum TimetableTeacherDTO: Content, Hashable {
	case named(lastName: String)
	case unknown(rawNotes: String)

	var displayName: String {
		switch self {
			case let .named(lastName): "Teacher: \(lastName)"
			case let .unknown(rawNotes): rawNotes
		}
	}
}

struct TimetableSubjectDTO: Content {
	let id: String
	let symbol: String
	let colour: TimetableColorDTO
	let slots: [TimetableSlotDTO]
	let classroom: TimetableClassroomDTO
	let teacher: TimetableTeacherDTO

	init(
		id: String,
		symbol: String,
		colour: TimetableColorDTO,
		slots: [TimetableSlotDTO],
		classroom: TimetableClassroomDTO,
		teacher: TimetableTeacherDTO
	) {
		self.id = id
		self.symbol = symbol
		self.colour = colour
		self.slots = slots
		self.classroom = classroom
		self.teacher = teacher
	}

	private enum CodingKeys: String, CodingKey {
		case id, symbol, colour, slots, classroom, teacher
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		symbol = try container.decode(String.self, forKey: .symbol)
		colour = try container.decode(TimetableColorDTO.self, forKey: .colour)
		slots = try container.decode([TimetableSlotDTO].self, forKey: .slots)
		classroom = try container.decodeIfPresent(TimetableClassroomDTO.self, forKey: .classroom) ?? .unknown(rawLocation: "Test classroom")
		teacher = try container.decodeIfPresent(TimetableTeacherDTO.self, forKey: .teacher) ?? .unknown(rawNotes: "Teacher: Test")
	}
}

struct OwnerTimetableUpdateRequest: Content {
	let subjects: [TimetableSubjectDTO]
	let expectedRevision: Int?
	let isSearchable: Bool?
}

struct OwnerTimetableVisibilityUpdateRequest: Content {
	let isSearchable: Bool
}

struct OwnerTimetableResponse: Content {
	let id: UUID?
	let subjects: [TimetableSubjectDTO]
	let revision: Int
	let updatedAt: Date?
	let isSearchable: Bool
}

struct ReportUserRequest: Content {
	let reportedAccountID: String
}

struct FeedbackRequest: Content {
	let category: String
	let message: String
}

struct RegisterUserDeviceRequest: Content {
	let installationID: String
	let platform: String
	let osMajorVersion: Int? = nil
	let apnsToken: String
	/// `true` when the token was obtained from a debug/sandbox build (APNs sandbox endpoint).
	let isDebug: Bool
}

struct RemoveUserDeviceRequest: Content {
	let installationID: String
	let platform: String
}

struct UserDeviceResponse: Content {
	let installationID: String
	let platform: String
	let isDebug: Bool
	let lastSeenAt: Date
}

struct TestNotificationResponse: Content {
	let deliveredDeviceCount: Int
}

struct BroadcastNotificationRequest: Content {
	let title: String
	let subtitle: String?
	let body: String?
}

struct BroadcastNotificationResponse: Content {
	let id: UUID
	let eligibleDeviceCount: Int
	let deliveredDeviceCount: Int
	let invalidatedDeviceCount: Int
	let failedDeviceCount: Int
}
