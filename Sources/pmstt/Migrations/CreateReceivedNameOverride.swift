import Fluent

struct CreateReceivedNameOverride: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("received_name_overrides")
			.id()
			.field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
			.field("pass_serial_number", .string, .required)
			.field("display_name", .string, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "user_id", "pass_serial_number")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("received_name_overrides").delete()
	}
}
