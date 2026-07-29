import Fluent

struct CreateSyncMutationReceipt: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(SyncMutationReceipt.schema)
			.id()
			.field(
				"user_id",
				.uuid,
				.required,
				.references(User.schema, "id", onDelete: .cascade)
			)
			.field("mutation_id", .uuid, .required)
			.field("result_data", .data, .required)
			.field("created_at", .datetime)
			.unique(on: "user_id", "mutation_id")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(SyncMutationReceipt.schema).delete()
	}
}
