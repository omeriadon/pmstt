import Fluent

struct CreateCalendarEvent: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(CalendarEvent.schema)
			.id()
			.field("user_id", .uuid, .references(User.schema, "id", onDelete: .cascade))
			.field("title", .string, .required)
			.field("notes", .string)
			.field("symbol", .string, .required)
			.field("event_date", .string, .required)
			.field("is_global", .bool, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(CalendarEvent.schema).delete()
	}
}
