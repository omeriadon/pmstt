import Foundation
import Fluent
import SQLKit

struct AddUserTokenAuthority: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.transaction { database in
			try await database.schema(UserToken.schema)
				.field("parent_session_id", .uuid)
				.update()
			try await database.schema(UserToken.schema)
				.field("refresh_jti", .uuid)
				.update()
			try await database.schema(UserToken.schema)
				.field("revoked_at", .datetime)
				.update()
			try await database.schema(UserToken.schema)
				.field("active_watch_key", .string)
				.update()

			let tokens = try await UserToken.query(on: database).all()
			let byID = Dictionary(uniqueKeysWithValues: tokens.compactMap { token in
				token.id.map { ($0, token) }
			})
			var activeWatchKeys = Set<String>()
			for token in tokens {
				let platform = ClientPlatform(rawValue: token.clientPlatform ?? "") ?? .legacy
				token.clientPlatform = platform.rawValue
				if platform == .watchOS {
					let parent = token.parentSessionID.flatMap { byID[$0] }
					let orphaned = parent == nil || parent?.revokedAt != nil || parent?.platformValue != .iOS
					if orphaned {
						token.revokedAt = token.revokedAt ?? Date()
						token.activeWatchKey = nil
					} else if let installationID = token.installationID {
						let userID = token.$user.id
						let key = Self.watchKey(userID: userID, installationID: installationID)
						if token.revokedAt == nil && activeWatchKeys.insert(key).inserted {
							token.activeWatchKey = key
						} else {
							token.revokedAt = token.revokedAt ?? Date()
							token.activeWatchKey = nil
						}
					}
				} else {
					token.activeWatchKey = nil
				}
				try await token.save(on: database)
			}

			guard let sqlDatabase = database as? any SQLDatabase else {
				throw SessionConstraintMigrationError.unsupportedDatabase
			}
			try await sqlDatabase.raw("CREATE UNIQUE INDEX IF NOT EXISTS \"uq_user_tokens_active_watch_key\" ON \"user_tokens\" (\"active_watch_key\")").run()
		}
	}

	func revert(on database: any Database) async throws {
		if let sqlDatabase = database as? any SQLDatabase {
			try await sqlDatabase.raw("DROP INDEX IF EXISTS \"uq_user_tokens_active_watch_key\"").run()
		}
		try await database.schema(UserToken.schema)
			.deleteField("parent_session_id")
			.deleteField("refresh_jti")
			.deleteField("revoked_at")
			.deleteField("active_watch_key")
			.update()
	}

	static func watchKey(userID: UUID, installationID: String) -> String {
		"\(userID.uuidString):\(installationID)"
	}
}

private enum SessionConstraintMigrationError: Error {
	case unsupportedDatabase
}
