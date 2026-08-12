import Fluent

struct CreateEmailDeliveryRecord: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(EmailDeliveryRecord.schema)
			.id()
			.field("recipient", .string, .required)
			.field("subject", .string, .required)
			.field("body", .string, .required)
			.field("status", .string, .required)
			.field("failure_reason", .string)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(EmailDeliveryRecord.schema).delete()
	}
}
