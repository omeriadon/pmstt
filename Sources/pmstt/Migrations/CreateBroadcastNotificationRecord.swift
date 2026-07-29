import Fluent

struct CreateBroadcastNotificationRecord: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(BroadcastNotificationRecord.schema)
			.id()
			.field("sender_account_id", .uuid)
			.field("sender_email", .string, .required)
			.field("sender_authority", .string, .required)
			.field("audience", .string, .required)
			.field("title", .string, .required)
			.field("subtitle", .string)
			.field("body", .string)
			.field("eligible_device_count", .int, .required)
			.field("delivered_device_count", .int, .required)
			.field("invalidated_device_count", .int, .required)
			.field("failed_device_count", .int, .required)
			.field("delivery_state", .string, .required)
			.field("failure_summary", .string)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(BroadcastNotificationRecord.schema).delete()
	}
}
