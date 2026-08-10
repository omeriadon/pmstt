import Fluent

struct AddFriendshipLocationNotifications: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(Friendship.schema)
			.field("requester_location_notification_preferences", .data)
			.field("recipient_location_notification_preferences", .data)
			.field("requester_location_notification_announced_preferences", .data)
			.field("recipient_location_notification_announced_preferences", .data)
			.field("requester_location_notification_preferences_updated_at", .datetime)
			.field("recipient_location_notification_preferences_updated_at", .datetime)
			.update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(Friendship.schema)
			.deleteField("requester_location_notification_preferences")
			.deleteField("recipient_location_notification_preferences")
			.deleteField("requester_location_notification_announced_preferences")
			.deleteField("recipient_location_notification_announced_preferences")
			.deleteField("requester_location_notification_preferences_updated_at")
			.deleteField("recipient_location_notification_preferences_updated_at")
			.update()
	}
}
