import Fluent

struct CreateSyncRecordTombstone: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(SyncRecordTombstone.schema)
			.id()
			.field(
				"user_id",
				.uuid,
				.required,
				.references(User.schema, "id", onDelete: .cascade)
			)
			.field("record_type", .string, .required)
			.field("record_id", .uuid, .required)
			.field("revision", .int, .required)
			.field("deleted_at", .datetime)
			.unique(on: "user_id", "record_type", "record_id", "revision")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(SyncRecordTombstone.schema).delete()
	}
}
