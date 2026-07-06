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

struct WatchSessionRequest: Content {
	let installationID: String
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
	var notificationsEnabled: Bool
	var broadcastNotificationsEnabled: Bool
	var notificationLeadTime: NotificationLeadTime

	static let `default` = UpdateSettingsRequest(
		liveActivitiesEnabled: true,
		notificationsEnabled: true,
		broadcastNotificationsEnabled: true,
		notificationLeadTime: .zero
	)

	var accountSettings: AccountSettings {
		AccountSettings(
			liveActivitiesEnabled: liveActivitiesEnabled,
			notificationsEnabled: notificationsEnabled,
			broadcastNotificationsEnabled: broadcastNotificationsEnabled,
			notificationLeadTime: notificationLeadTime
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
		notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled, default: defaults.notificationsEnabled)
		broadcastNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .broadcastNotificationsEnabled, default: defaults.broadcastNotificationsEnabled)
		notificationLeadTime = try container.decodeIfPresent(NotificationLeadTime.self, forKey: .notificationLeadTime, default: defaults.notificationLeadTime)
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
	let subjects: [TimetableSubjectDTO]
	let revision: Int
	let updatedAt: Date?
	let isSearchable: Bool
}

struct TimetableSearchResult: Content {
	let id: UUID
	let title: String
	let authorAccountID: UUID
	let authorDisplayName: String
	let sourceKind: SourceKind
	let confidence: Double
}

struct TimetableDetailResponse: Content {
	let id: UUID
	let title: String
	let authorAccountID: UUID
	let authorDisplayName: String
	let sourceKind: SourceKind
	let subjects: [TimetableSubjectDTO]
	let subjectCount: Int
	let weeklyLessonCount: Int
	let updatedAt: Date?
	let activeInstallCount: Int
	let isSearchable: Bool
	let canEdit: Bool
}

struct AuthoredTimetableUpdateRequest: Content {
	let title: String
	let subjects: [TimetableSubjectDTO]
	let isSearchable: Bool
}

typealias AuthoredTimetableCreateRequest = AuthoredTimetableUpdateRequest

struct WalletRegistrationRequest: Content {
	let pushToken: String
}

struct WalletSerialNumbersResponse: Content {
	let serialNumbers: [String]
	let lastUpdated: String
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
	let contentRevision: Int
	let isDeleted: Bool
	let isShareable: Bool
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

struct RegisterUserDeviceRequest: Content {
	let installationID: String
	let platform: String
	let apnsToken: String
	/// `true` when the token was obtained from a debug/sandbox build (APNs sandbox endpoint).
	let isDebug: Bool
}

struct RemoveUserDeviceRequest: Content {
	let installationID: String
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
	let subtitle: String
	let body: String
}

struct BroadcastNotificationResponse: Content {
	let eligibleDeviceCount: Int
	let deliveredDeviceCount: Int
	let invalidatedDeviceCount: Int
	let failedDeviceCount: Int
}
