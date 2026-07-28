import Fluent

struct AddUserProfileAppearance: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(User.schema)
			.field("profile_appearance_data", .data)
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema)
			.deleteField("profile_appearance_data")
			.update()
	}
}
