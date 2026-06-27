import Fluent

struct CreateUser: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("users")
			.id()
			.field("email", .string)
			.field("password_hash", .string)
			.field("apple_subject", .string)
			.field("display_name", .string, .required)
			.field("self_pass_serial_number", .string, .required)
			.field("settings_data", .data, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "email")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("users").delete()
	}
}
