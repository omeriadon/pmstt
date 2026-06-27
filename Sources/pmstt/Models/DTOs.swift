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

struct TokenResponse: Content {
	let accessToken: String
	let refreshToken: String
	let user: UserProfileResponse
}

struct UserProfileResponse: Content {
	let id: UUID
	let email: String
	let displayName: String?
	let createdAt: Date?
}

struct UpdateProfileRequest: Content {
	let displayName: String?
	let email: String?
}
