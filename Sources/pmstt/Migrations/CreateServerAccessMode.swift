import Fluent
import SQLKit

struct CreateServerAccessMode: AsyncMigration {
	func prepare(on database: any Database) async throws {
		guard let sqlDatabase = database as? any SQLDatabase else {
			throw ServerAccessModeMigrationError.unsupportedDatabase
		}

		if sqlDatabase.dialect.name == "postgresql" {
			try await sqlDatabase.raw("CREATE TABLE IF NOT EXISTS \"server_access_mode\" (\"id\" UUID PRIMARY KEY, \"development_access_only\" BOOL NOT NULL, \"updated_at\" TIMESTAMPTZ)").run()
		} else {
			try await database.schema(ServerAccessMode.schema)
				.id()
				.field("development_access_only", .bool, .required)
				.field("updated_at", .datetime)
				.create()
		}

		guard try await ServerAccessMode.query(on: database).first() == nil else {
			return
		}

		try await ServerAccessMode(developmentAccessOnly: false).create(on: database)
	}

	func revert(on database: any Database) async throws {
		try await database.schema(ServerAccessMode.schema).delete()
	}
}

private enum ServerAccessModeMigrationError: Error {
	case unsupportedDatabase
}
