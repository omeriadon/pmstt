import Fluent
import SQLKit

struct CreateReceivedTimetableImport: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(ReceivedTimetableImport.schema)
			.id()
			.field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
			.field("timetable_id", .uuid, .required)
			.field("source_kind", .string, .required)
			.field("imported_at", .datetime, .required)
			.field("revoked_at", .datetime)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "user_id", "timetable_id", "source_kind")
			.create()

		if let sqlDatabase = database as? any SQLDatabase {
			try await sqlDatabase.raw("CREATE INDEX IF NOT EXISTS \"ix_received_timetable_imports_source\" ON \"received_timetable_imports\" (\"timetable_id\", \"source_kind\")").run()
		}
	}

	func revert(on database: any Database) async throws {
		if let sqlDatabase = database as? any SQLDatabase {
			try await sqlDatabase.raw("DROP INDEX IF EXISTS \"ix_received_timetable_imports_source\"").run()
		}
		try await database.schema(ReceivedTimetableImport.schema).delete()
	}
}
