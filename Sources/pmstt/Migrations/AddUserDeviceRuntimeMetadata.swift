import Fluent

struct AddUserDeviceRuntimeMetadata: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(UserDevice.schema)
			.field("os_minor_version", .int)
			.field("is_beta", .bool, .required, .sql(.default(false)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(UserDevice.schema)
			.deleteField("os_minor_version")
			.deleteField("is_beta")
			.update()
	}
}
