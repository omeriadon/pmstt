import Fluent
import SQLKit

struct CreateFriendship: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(Friendship.schema)
			.id()
			.field("requester_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
			.field("recipient_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
			.field("status", .string, .required)
			.field("accepted_at", .datetime)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "requester_id", "recipient_id")
			.create()

		if let sqlDatabase = database as? any SQLDatabase {
			try await sqlDatabase.raw("CREATE INDEX IF NOT EXISTS \"ix_friendships_recipient_status\" ON \"friendships\" (\"recipient_id\", \"status\")").run()
			try await sqlDatabase.raw("CREATE INDEX IF NOT EXISTS \"ix_friendships_requester_status\" ON \"friendships\" (\"requester_id\", \"status\")").run()
		}
	}

	func revert(on database: any Database) async throws {
		if let sqlDatabase = database as? any SQLDatabase {
			try await sqlDatabase.raw("DROP INDEX IF EXISTS \"ix_friendships_recipient_status\"").run()
			try await sqlDatabase.raw("DROP INDEX IF EXISTS \"ix_friendships_requester_status\"").run()
		}
		try await database.schema(Friendship.schema).delete()
	}
}
