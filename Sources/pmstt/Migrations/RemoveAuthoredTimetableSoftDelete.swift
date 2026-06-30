import Fluent

struct RemoveAuthoredTimetableSoftDelete: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("authored_timetables").deleteField("is_deleted").update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("authored_timetables")
			.field("is_deleted", .bool, .required, .sql(.default(false)))
			.update()
	}
}
