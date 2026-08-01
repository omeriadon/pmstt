import Fluent

struct AddBroadcastNotificationDeletion: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(BroadcastNotificationRecord.schema)
			.field("is_deleted", .bool, .required, .sql(.default(false)))
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(BroadcastNotificationRecord.schema)
			.deleteField("is_deleted")
			.update()
	}
}
