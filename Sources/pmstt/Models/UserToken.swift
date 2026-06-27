import Fluent
import Vapor

final class UserToken: Model, Content, @unchecked Sendable {
	static let schema = "user_tokens"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "token_hash")
	var tokenHash: String

	@Parent(key: "user_id")
	var user: User

	@Field(key: "expires_at")
	var expiresAt: Date

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	init() {}

	init(id: UUID? = nil, tokenHash: String, userID: User.IDValue, expiresAt: Date) {
		self.id = id
		self.tokenHash = tokenHash
		self.$user.id = userID
		self.expiresAt = expiresAt
	}
}
