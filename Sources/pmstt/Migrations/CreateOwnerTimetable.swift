import Fluent

struct CreateOwnerTimetable: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("owner_timetables")
			.id()
			.field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
			.field("subjects_data", .data, .required)
			.field("revision", .int, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "user_id")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("owner_timetables").delete()
	}
}
