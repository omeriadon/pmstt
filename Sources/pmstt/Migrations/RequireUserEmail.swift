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

		try await database.schema(User.schema)
			.field("email", .string, .required)
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema)
			.field("email", .string)
			.update()
	}
}

private enum RequireUserEmailMigrationError: Error {
	case unsupportedDatabase
}
