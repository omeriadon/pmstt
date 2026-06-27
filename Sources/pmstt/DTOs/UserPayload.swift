import JWT
import Vapor

struct UserPayload: JWTPayload, Authenticatable {
	let sub: UUID
	let email: String?
	let exp: ExpirationClaim

	func verify(using algorithm: some JWTAlgorithm) async throws {
		try exp.verifyNotExpired()
	}
}
