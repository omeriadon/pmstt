import Fluent

struct CreateModerationRecords: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(UserReport.schema)
			.id()
			.field("reporter_id", .uuid, .required)
			.field("reported_user_id", .uuid, .required)
			.field("action", .string, .required)
			.field("created_at", .datetime)
			.field("acted_at", .datetime)
			.create()

		try await database.schema(FriendshipDateChangeRequest.schema)
			.id()
			.field("friendship_id", .uuid, .required)
			.field("requester_id", .uuid, .required)
			.field("requested_date", .datetime, .required)
			.field("action", .string, .required)
			.field("created_at", .datetime)
			.field("acted_at", .datetime)
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(FriendshipDateChangeRequest.schema).delete()
		try await database.schema(UserReport.schema).delete()
	}
}
