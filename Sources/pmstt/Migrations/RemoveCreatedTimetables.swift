import Fluent
import SQLKit

struct RemoveCreatedTimetables: AsyncMigration {
	func prepare(on database: any Database) async throws {
		guard let sqlDatabase = database as? any SQLDatabase else {
			return
		}

		let createdTimetableCount: Int
		if sqlDatabase.dialect.name == "postgresql" {
			createdTimetableCount = try await sqlDatabase.raw("""
				SELECT COUNT(*) AS "count"
				FROM information_schema.tables
				WHERE table_name = 'created_timetables'
				""").first(decodingColumn: "count", as: Int.self) ?? 0
		} else {
			createdTimetableCount = try await sqlDatabase.raw("""
				SELECT COUNT(*) AS "count"
				FROM sqlite_master
				WHERE type = 'table' AND name = 'created_timetables'
				""").first(decodingColumn: "count", as: Int.self) ?? 0
		}

		if createdTimetableCount > 0 {
			try await sqlDatabase.raw("""
				DELETE FROM "pass_records"
				WHERE "source_kind" = 'createdForThirdParty'
				""").run()

			try await database.schema("pass_records")
				.deleteField("created_timetable_id")
				.update()
		}

		try await sqlDatabase.raw("DROP TABLE IF EXISTS \"created_timetables\"").run()
	}

	func revert(on _: any Database) async throws {}
}
