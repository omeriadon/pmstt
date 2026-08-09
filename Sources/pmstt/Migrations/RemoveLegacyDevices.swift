import Fluent

struct RemoveLegacyDevices: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await UserDevice.query(on: database)
			.filter(\.$platform == ClientPlatform.legacy.rawValue)
			.delete()
	}

	func revert(on _: any Database) async throws {}
}
