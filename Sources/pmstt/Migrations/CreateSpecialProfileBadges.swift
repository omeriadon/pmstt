import Fluent

struct CreateSpecialProfileBadges: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(SpecialProfileBadge.schema)
			.id()
			.field("symbol", .string, .required)
			.field("background_color_data", .data)
			.field("symbol_color_data", .data)
			.field("priority", .int, .required)
			.field("accessibility_label", .string, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.create()

		try await database.schema(UserSpecialProfileBadge.schema)
			.id()
			.field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
			.field("badge_id", .uuid, .required, .references(SpecialProfileBadge.schema, "id", onDelete: .cascade))
			.field("created_at", .datetime)
			.unique(on: "user_id", "badge_id")
			.create()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(UserSpecialProfileBadge.schema).delete()
		try await database.schema(SpecialProfileBadge.schema).delete()
	}
}
