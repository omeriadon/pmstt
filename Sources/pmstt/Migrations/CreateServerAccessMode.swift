import Fluent

struct CreateServerAccessMode: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(ServerAccessMode.schema)
			.id()
			.field("development_access_only", .bool, .required)
			.field("updated_at", .datetime)
			.create()

		try await ServerAccessMode().create(on: database)
	}

	func revert(on database: any Database) async throws {
		try await database.schema(ServerAccessMode.schema).delete()
	}
}
