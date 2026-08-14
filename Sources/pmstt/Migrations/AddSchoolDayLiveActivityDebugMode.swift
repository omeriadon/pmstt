import Fluent

struct AddSchoolDayLiveActivityDebugMode: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(SchoolDayLiveActivity.schema)
			.field("is_debug", .bool, .required, .sql(.default(false)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(SchoolDayLiveActivity.schema)
			.deleteField("is_debug")
			.update()
	}
}
