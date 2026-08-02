import Fluent
import SQLKit

/// Clears legacy friendship state before the directional request model is rebuilt.
/// Friendship rows are intentionally not recoverable after this migration runs.
struct ResetFriendshipsForRebuild: AsyncMigration {
	func prepare(on database: any Database) async throws {
		guard let sqlDatabase = database as? any SQLDatabase else {
			throw ResetFriendshipsMigrationError.unsupportedDatabase
		}
		try await sqlDatabase.raw("DELETE FROM \"friendships\"").run()

		try await database.schema(Friendship.schema)
			.field("pair_key", .string, .required)
			.update()

		try await sqlDatabase.raw(
			"CREATE UNIQUE INDEX IF NOT EXISTS \"ux_friendships_pair_key\" ON \"friendships\" (\"pair_key\")"
		).run()
	}

	func revert(on database: any Database) async throws {
		if let sqlDatabase = database as? any SQLDatabase {
			try await sqlDatabase.raw("DROP INDEX IF EXISTS \"ux_friendships_pair_key\"").run()
		}

		try await database.schema(Friendship.schema)
			.deleteField("pair_key")
			.update()
	}
}

private enum ResetFriendshipsMigrationError: Error {
	case unsupportedDatabase
}
