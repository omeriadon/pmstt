import Fluent
import SQLKit

struct RemoveTimetableSharing: AsyncMigration {
	func prepare(on database: any Database) async throws {
		guard let sqlDatabase = database as? any SQLDatabase else {
			return
		}

		try await sqlDatabase.raw("DROP TABLE IF EXISTS \"received_timetable_imports\"").run()
		try await sqlDatabase.raw("DROP TABLE IF EXISTS \"received_pass_mirrors\"").run()
		try await sqlDatabase.raw("DROP TABLE IF EXISTS \"received_name_overrides\"").run()
		try await sqlDatabase.raw("DROP TABLE IF EXISTS \"timetable_share_aliases\"").run()
	}

	func revert(on _: any Database) async throws {}
}
