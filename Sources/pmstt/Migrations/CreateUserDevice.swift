import Fluent

struct CreateUserDevice: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("user_devices")
			.id()
			.field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
			.field("installation_id", .string, .required)
			.field("platform", .string, .required)
			.field("apns_token", .string)
			.field("live_activity_push_to_start_token", .string)
			.field("last_seen_at", .datetime, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "installation_id")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("user_devices").delete()
	}
}
