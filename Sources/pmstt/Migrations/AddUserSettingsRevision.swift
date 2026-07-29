import Fluent

struct AddUserSettingsRevision: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(User.schema)
			.field("settings_revision", .int, .required, .sql(.default(0)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema)
			.deleteField("settings_revision")
			.update()
	}
}
