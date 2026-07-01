import Fluent

struct AddReceivedPassShareability: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("received_pass_mirrors")
			.field("is_shareable", .bool, .required, .sql(.default(false)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema("received_pass_mirrors")
			.deleteField("is_shareable")
			.update()
	}
}
