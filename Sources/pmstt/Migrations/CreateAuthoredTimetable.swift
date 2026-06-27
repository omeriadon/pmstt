import Fluent

struct CreateAuthoredTimetable: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("authored_timetables")
			.id()
			.field("author_user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
			.field("subject_display_name", .string, .required)
			.field("pass_serial_number", .string, .required)
			.field("subjects_data", .data, .required)
			.field("revision", .int, .required)
			.field("is_deleted", .bool, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "pass_serial_number")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("authored_timetables").delete()
	}
}
