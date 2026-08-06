import Fluent

struct AddUserLocationStatusHistory: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(User.schema)
			.field("location_status_data", .data)
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema)
			.deleteField("location_status_data")
			.update()
	}
}
