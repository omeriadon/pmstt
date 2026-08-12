import Fluent

struct AddUserDeviceAppVersion: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(UserDevice.schema)
			.field("app_version", .string)
			.field("app_build", .string)
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(UserDevice.schema)
			.deleteField("app_version")
			.deleteField("app_build")
			.update()
	}
}
