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
	let user: UserProfileResponse
}

struct UserProfileResponse: Content {
	let id: UUID
	let email: String?
	let displayName: String
	let createdAt: Date?
}

struct UpdateProfileRequest: Content {
	let displayName: String?
	let email: String?
}

struct UpdateSettingsRequest: Content {
	var liveActivitiesEnabled: Bool

	static let `default` = UpdateSettingsRequest(
		liveActivitiesEnabled: true
	)
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
	let sourceKind: String
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
