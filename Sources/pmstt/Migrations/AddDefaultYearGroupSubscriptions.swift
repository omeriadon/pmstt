import Fluent

struct AddDefaultYearGroupSubscriptions: AsyncMigration {
	func prepare(on database: any Database) async throws {
		guard let yearSevenTag = try await EventTag.query(on: database)
			.filter(\.$category == .yearGroup)
			.filter(\.$slug == "year-7")
			.filter(\.$isArchived == false)
			.first()
		else {
			return
		}

		let yearSevenTagID = try yearSevenTag.requireID()
		let yearGroupTags = try await EventTag.query(on: database)
			.filter(\.$category == .yearGroup)
			.filter(\.$isArchived == false)
			.all()
		let yearGroupTagIDs = Set(yearGroupTags.compactMap(\.id))
		let subscriptions = try await AccountEventTagSubscription.query(on: database).all()
		let accountIDsWithYearGroup = Set(
			subscriptions
				.filter { yearGroupTagIDs.contains($0.$eventTag.id) }
				.map(\.$account.id)
		)
		let accounts = try await User.query(on: database).all()

		for account in accounts {
			let accountID = try account.requireID()
			guard !accountIDsWithYearGroup.contains(accountID) else {
				continue
			}

			try await AccountEventTagSubscription(
				accountID: accountID,
				eventTagID: yearSevenTagID
			).create(on: database)
		}
	}

	func revert(on _: any Database) async throws {}
}
