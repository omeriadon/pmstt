import Fluent

struct AddUserDeviceDebugFlag: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("user_devices")
			.field("is_debug", .bool, .required, .custom("DEFAULT FALSE"))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("user_devices")
			.deleteField("is_debug")
			.update()
	}
}
