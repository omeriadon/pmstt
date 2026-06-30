import Fluent

struct AddTimetableSearchability: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("owner_timetables")
			.field("is_searchable", .bool, .required, .sql(.default(true)))
			.update()
		try await database.schema("authored_timetables")
			.field("is_searchable", .bool, .required, .sql(.default(true)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("authored_timetables").deleteField("is_searchable").update()
		try await database.schema("owner_timetables").deleteField("is_searchable").update()
	}
}
