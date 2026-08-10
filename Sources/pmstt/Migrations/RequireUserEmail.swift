import Fluent
import SQLKit

struct RequireUserEmail: AsyncMigration {
	func prepare(on database: any Database) async throws {
		guard let sqlDatabase = database as? any SQLDatabase else {
			throw RequireUserEmailMigrationError.unsupportedDatabase
		}

		try await sqlDatabase.raw(
			"""
			UPDATE "users"
			SET "email" = 'missing-email-' || CAST("id" AS TEXT) || '@timetable.invalid'
			WHERE "email" IS NULL OR TRIM("email") = ''
			"""
		).run()

		if sqlDatabase.dialect.name == "postgresql" {
			try await sqlDatabase.raw(
				"ALTER TABLE \"users\" ALTER COLUMN \"email\" SET NOT NULL"
			).run()
		}
	}

	func revert(on database: any Database) async throws {
		guard let sqlDatabase = database as? any SQLDatabase else {
			throw RequireUserEmailMigrationError.unsupportedDatabase
		}

		if sqlDatabase.dialect.name == "postgresql" {
			try await sqlDatabase.raw(
				"ALTER TABLE \"users\" ALTER COLUMN \"email\" DROP NOT NULL"
			).run()
		}
	}
}

private enum RequireUserEmailMigrationError: Error {
	case unsupportedDatabase
}
