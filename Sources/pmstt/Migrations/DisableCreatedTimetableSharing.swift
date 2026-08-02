import Fluent

struct DisableCreatedTimetableSharing: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await CreatedTimetable.query(on: database)
			.set(\.$isSearchable, to: false)
			.update()
	}

	func revert(on _: any Database) async throws {}
}
