import Fluent
import Vapor

final class User: Model, Content, @unchecked Sendable {
	static let schema = "users"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "email")
	var email: String

	@Field(key: "password_hash")
	var passwordHash: String

	@Field(key: "display_name")
	var displayName: String?

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(id: UUID? = nil, email: String, passwordHash: String, displayName: String? = nil) {
		self.id = id
		self.email = email.lowercased()
		self.passwordHash = passwordHash
		self.displayName = displayName
	}
}
