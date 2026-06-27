import Fluent

struct CreatePassRecord: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("pass_records")
			.id()
			.field("serial_number", .string, .required)
			.field("issuer_account_id", .string, .required)
			.field("source_kind", .string, .required)
			.field("authored_timetable_id", .uuid, .references("authored_timetables", "id", onDelete: .setNull))
			.field("revision", .int, .required)
			.field("authentication_token_hash", .string, .required)
			.field("is_deleted", .bool, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "serial_number")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("pass_records").delete()
	}
}
