import Fluent

struct AddCalendarEventRevision: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(CalendarEvent.schema)
			.field("revision", .int, .required, .sql(.default(1)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(CalendarEvent.schema)
			.deleteField("revision")
			.update()
	}
}
