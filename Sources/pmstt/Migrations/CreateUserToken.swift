import Fluent

struct CreateUserToken: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("user_tokens")
			.id()
			.field("token_hash", .string, .required)
			.field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
			.field("expires_at", .datetime, .required)
			.field("created_at", .datetime)
			.unique(on: "token_hash")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("user_tokens").delete()
	}
}
