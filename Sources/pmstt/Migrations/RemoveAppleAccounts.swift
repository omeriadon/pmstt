import Fluent
import SQLKit

struct RemoveAppleAccounts: AsyncMigration {
	func prepare(on database: any Database) async throws {
		guard let sqlDatabase = database as? any SQLDatabase else {
			throw RemoveAppleAccountsMigrationError.unsupportedDatabase
		}

		try await markProfileObjectsForDeletedAccounts(on: sqlDatabase)
		try await deleteAppleOnlyAccounts(on: sqlDatabase)
		try await clearPreservedAppleCredentials(on: sqlDatabase)

		try await database.schema(User.schema)
			.deleteField("apple_subject")
			.deleteField("apple_email_forwarding_enabled")
			.deleteField("apple_authorization_revoked_at")
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema)
			.field("apple_subject", .string)
			.field("apple_email_forwarding_enabled", .bool)
			.field("apple_authorization_revoked_at", .datetime)
			.update()
	}

	private func markProfileObjectsForDeletedAccounts(on database: any SQLDatabase) async throws {
		try await database.raw(
			"""
			UPDATE "profile_storage_objects"
			SET "state" = 'orphaned', "updated_at" = CURRENT_TIMESTAMP
			WHERE "user_id" IN (
				SELECT "id"
				FROM "users"
				WHERE "password_hash" IS NULL
				AND LOWER(COALESCE("email", '')) NOT IN (
					'omeriadon@outlook.com',
					'adon.omeri@student.education.wa.edu.au'
				)
			)
			"""
		).run()
	}

	private func deleteAppleOnlyAccounts(on database: any SQLDatabase) async throws {
		try await database.raw(
			"""
			DELETE FROM "users"
			WHERE "password_hash" IS NULL
			AND LOWER(COALESCE("email", '')) NOT IN (
				'omeriadon@outlook.com',
				'adon.omeri@student.education.wa.edu.au'
			)
			"""
		).run()
	}

	private func clearPreservedAppleCredentials(on database: any SQLDatabase) async throws {
		try await database.raw(
			"""
			UPDATE "users"
			SET "apple_subject" = NULL,
				"apple_email_forwarding_enabled" = NULL,
				"apple_authorization_revoked_at" = NULL
			"""
		).run()
	}
}

private enum RemoveAppleAccountsMigrationError: Error {
	case unsupportedDatabase
}
