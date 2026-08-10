import Fluent

struct AddUserDeviceOSMajorVersion: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(UserDevice.schema)
			.field("os_major_version", .int)
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(UserDevice.schema)
			.deleteField("os_major_version")
			.update()
	}
}
