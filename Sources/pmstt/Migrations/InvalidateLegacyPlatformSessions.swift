import Fluent
import Foundation

struct InvalidateLegacyPlatformSessions: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await UserToken.query(on: database)
			.filter(\.$revokedAt == nil)
			.set(\.$revokedAt, to: Date())
			.set(\.$activeWatchKey, to: nil)
			.update()
	}

	func revert(on _: any Database) async throws {}
}
