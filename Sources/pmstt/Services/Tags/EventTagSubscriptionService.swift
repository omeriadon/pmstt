import Fluent
import Foundation

enum EventTagSubscriptionService {
	static func subscribeNewAccount(_ accountID: UUID, on database: any Database) async throws {
		let yearSevenTag = try await EventTag.query(on: database)
			.filter(\.$category == .yearGroup)
			.filter(\.$slug == "year-7")
			.filter(\.$isArchived == false)
			.first()

		for tag in [yearSevenTag].compactMap(\.self) {
			let tagID = try tag.requireID()
			let existingSubscription = try await AccountEventTagSubscription.query(on: database)
				.filter(\.$account.$id == accountID)
				.filter(\.$eventTag.$id == tagID)
				.first()

			guard existingSubscription == nil else {
				continue
			}

			try await AccountEventTagSubscription(
				accountID: accountID,
				eventTagID: tagID
			).create(on: database)
		}
	}
}
