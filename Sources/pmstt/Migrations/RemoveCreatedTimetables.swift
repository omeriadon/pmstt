import Fluent
import SQLKit

struct RemoveCreatedTimetables: AsyncMigration {
	func prepare(on database: any Database) async throws {
		if let sqlDatabase = database as? any SQLDatabase {
			try await sqlDatabase.raw("""
				DELETE FROM "received_timetable_imports"
				WHERE "source_kind" = 'createdForThirdParty'
				""").run()
			try await sqlDatabase.raw("""
				DELETE FROM "received_pass_mirrors"
				WHERE "source_kind" = 'createdForThirdParty'
				""").run()
			try await sqlDatabase.raw("""
				DELETE FROM "pass_records"
				WHERE "source_kind" = 'createdForThirdParty'
				""").run()
		}

		try await database.schema("pass_records")
			.deleteField("created_timetable_id")
			.update()
		try await database.schema("created_timetables").delete()
	}

	func revert(on _: any Database) async throws {}
}
