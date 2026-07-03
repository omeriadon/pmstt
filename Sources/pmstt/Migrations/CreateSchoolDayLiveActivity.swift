import Fluent

struct CreateSchoolDayLiveActivity: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(SchoolDayLiveActivity.schema)
			.id()
			.field("user_device_id", .uuid, .required, .references(UserDevice.schema, "id", onDelete: .cascade))
			.field("activity_key", .string, .required)
			.field("school_date", .string, .required)
			.field("update_token", .string)
			.field("current_transition", .string, .required)
			.field("status", .string, .required)
			.field("last_apns_timestamp", .datetime)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "user_device_id", "school_date", "activity_key")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(SchoolDayLiveActivity.schema).delete()
	}
}
