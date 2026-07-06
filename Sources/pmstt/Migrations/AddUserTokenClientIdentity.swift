import Fluent

struct AddUserTokenClientIdentity: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(UserToken.schema)
			.field("client_platform", .string)
			.field("installation_id", .string)
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(UserToken.schema)
			.deleteField("client_platform")
			.deleteField("installation_id")
			.update()
	}
}
