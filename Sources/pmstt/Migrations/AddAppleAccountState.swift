import Fluent

struct AddAppleAccountState: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("users")
			.field("apple_email_forwarding_enabled", .bool)
			.field("apple_authorization_revoked_at", .datetime)
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("users")
			.deleteField("apple_email_forwarding_enabled")
			.deleteField("apple_authorization_revoked_at")
			.update()
	}
}
