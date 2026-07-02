import Fluent

struct CreateSchoolNotificationDelivery: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(SchoolNotificationDelivery.schema)
			.id()
			.field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
			.field("school_date", .string, .required)
			.field("event", .string, .required)
			.field("created_at", .datetime)
			.unique(on: "user_id", "school_date", "event")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(SchoolNotificationDelivery.schema).delete()
	}
}
