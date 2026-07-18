import Fluent

struct CreateTimetableShareAlias: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(TimetableShareAlias.schema)
			.id()
			.field("alias", .string, .required)
			.field("owner_timetable_id", .uuid, .required, .references(OwnerTimetable.schema, "id", onDelete: .cascade))
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "alias")
			.unique(on: "owner_timetable_id")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(TimetableShareAlias.schema).delete()
	}
}
