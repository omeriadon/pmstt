import Fluent

struct AddUserProfileRevision: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(User.schema)
			.field("profile_revision", .int, .required, .sql(.default(0)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema)
			.deleteField("profile_revision")
			.update()
	}
}
