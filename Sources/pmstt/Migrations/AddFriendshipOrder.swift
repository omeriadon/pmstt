import Fluent

struct AddFriendshipOrder: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(Friendship.schema)
			.field("requester_sort_order", .int, .required, .sql(.default(0)))
			.field("recipient_sort_order", .int, .required, .sql(.default(0)))
			.update()

		let friendships = try await Friendship.query(on: database)
			.filter(\.$status == .accepted)
			.sort(\.$acceptedAt)
			.all()
		var nextOrderByAccount: [UUID: Int] = [:]
		for friendship in friendships {
			let requesterID = friendship.$requester.id
			let recipientID = friendship.$recipient.id
			friendship.requesterSortOrder = nextOrderByAccount[requesterID, default: 0]
			friendship.recipientSortOrder = nextOrderByAccount[recipientID, default: 0]
			nextOrderByAccount[requesterID, default: 0] += 1
			nextOrderByAccount[recipientID, default: 0] += 1
			try await friendship.update(on: database)
		}
	}

	func revert(on database: any Database) async throws {
		try await database.schema(Friendship.schema)
			.deleteField("requester_sort_order")
			.deleteField("recipient_sort_order")
			.update()
	}
}
