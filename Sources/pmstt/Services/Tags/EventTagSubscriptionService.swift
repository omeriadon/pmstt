import Fluent
import Foundation

enum EventTagSubscriptionService {
	static func subscribeNewAccount(_ accountID: UUID, on database: any Database) async throws {
		guard let generalTag = try await EventTag.query(on: database)
			.filter(\.$category == .general)
			.filter(\.$isArchived == false)
			.sort(\.$sortOrder)
			.first()
		else {
			return
		}

		let generalTagID = try generalTag.requireID()
		let existingSubscription = try await AccountEventTagSubscription.query(on: database)
			.filter(\.$account.$id == accountID)
			.filter(\.$eventTag.$id == generalTagID)
			.first()

		guard existingSubscription == nil else {
			return
		}

		try await AccountEventTagSubscription(
			accountID: accountID,
			eventTagID: generalTagID
		).create(on: database)
	}
}
