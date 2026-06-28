import Foundation
import Vapor

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
