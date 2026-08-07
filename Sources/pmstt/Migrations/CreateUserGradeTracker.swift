import Fluent

struct CreateUserGradeTracker: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(User.schema)
			.field("grade_tracker_data", .data)
			.field("grade_tracker_revision", .int, .required, .sql(.default(0)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema)
			.deleteField("grade_tracker_data")
			.deleteField("grade_tracker_revision")
			.update()
	}
}
