import Fluent

struct AddUserDeviceOSBetaFlag: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(UserDevice.schema)
			.field("is_os_beta", .bool, .required, .sql(.default(false)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(UserDevice.schema)
			.deleteField("is_os_beta")
			.update()
	}
}
