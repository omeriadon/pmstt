import Fluent

struct RemoveNonYearGroupEventTags: AsyncMigration {
	func prepare(on database: any Database) async throws {
		let tags = try await EventTag.query(on: database)
			.filter(\.$category != .yearGroup)
			.all()
		let tagIDs = tags.compactMap(\.id)

		if !tagIDs.isEmpty {
			try await CalendarEventTag.query(on: database)
				.filter(\.$eventTag.$id ~~ tagIDs)
				.delete()
			try await AccountEventTagSubscription.query(on: database)
				.filter(\.$eventTag.$id ~~ tagIDs)
				.delete()
			try await EventTagAssociatedName.query(on: database)
				.filter(\.$eventTag.$id ~~ tagIDs)
				.delete()
			try await EventTag.query(on: database)
				.filter(\.$id ~~ tagIDs)
				.delete()
		}

		try await EventTagSection.query(on: database)
			.filter(\.$category != .yearGroup)
			.delete()
	}

	func revert(on _: any Database) async throws {}
}
