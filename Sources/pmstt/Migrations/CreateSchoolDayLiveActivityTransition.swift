import Fluent

struct CreateSchoolDayLiveActivityTransition: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(SchoolDayLiveActivityTransition.schema)
			.id()
			.field("live_activity_id", .uuid, .required, .references(SchoolDayLiveActivity.schema, "id", onDelete: .cascade))
			.field("transition", .string, .required)
			.field("created_at", .datetime)
			.unique(on: "live_activity_id", "transition")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(SchoolDayLiveActivityTransition.schema).delete()
	}
}
