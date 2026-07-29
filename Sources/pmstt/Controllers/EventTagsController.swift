import Fluent
import Vapor

struct EventTagsController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let tags = routes.grouped("v1", "tags").grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		tags.get(use: catalogue)
		tags.get("subscriptions", use: subscriptions)
		tags.put("subscriptions", use: replaceSubscriptions)
		tags.put("subscriptions", "subjects", use: replaceSubjectSubscriptions)
	}

	private func catalogue(req: Request) async throws -> EventTagCatalogueResponse {
		_ = try await user(req)
		let sections = try await EventTagSection.query(on: req.db)
			.filter(\.$isArchived == false)
			.sort(\.$sortOrder)
			.all()
		return try await EventTagCatalogueResponse(sections: sections.asyncMap { section in
			let tags = try await EventTag.query(on: req.db)
				.filter(\.$section.$id == section.requireID())
				.filter(\.$isArchived == false)
				.sort(\.$sortOrder)
				.all()
			return try EventTagSectionResponse(section, tags: tags)
		})
	}

	private func subscriptions(req: Request) async throws -> EventTagSubscriptionResponse {
		let user = try await user(req)
		return try await EventTagSubscriptionResponse(tagIDs: subscriptionIDs(for: user, on: req.db))
	}

	private func replaceSubscriptions(req: Request) async throws -> EventTagSubscriptionResponse {
		let user = try await user(req)
		let request = try req.content.decode(EventTagSubscriptionUpdateRequest.self)
		let requestedTagIDs = Array(Set(request.tagIDs))
		let tags: [EventTag]
		if requestedTagIDs.isEmpty {
			tags = []
		} else {
			tags = try await EventTag.query(on: req.db)
				.filter(\.$id ~~ requestedTagIDs)
				.filter(\.$isArchived == false)
				.all()
		}
		let tagIDs = try tags.map(\.requireID)

		try await req.db.transaction { database in
			try await AccountEventTagSubscription.query(on: database)
				.filter(\.$account.$id == user.requireID())
				.delete()
			for tagID in tagIDs {
				try await AccountEventTagSubscription(accountID: user.requireID(), eventTagID: tagID).create(on: database)
			}
		}
		return EventTagSubscriptionResponse(tagIDs: tagIDs)
	}

	private func replaceSubjectSubscriptions(req: Request) async throws -> EventTagSubscriptionResponse {
		let user = try await user(req)
		let request = try req.content.decode(EventTagSubscriptionUpdateRequest.self)
		let requestedTagIDs = Array(Set(request.tagIDs))
		let subjectTags: [EventTag]
		if requestedTagIDs.isEmpty {
			subjectTags = []
		} else {
			subjectTags = try await EventTag.query(on: req.db)
				.filter(\.$id ~~ requestedTagIDs)
				.filter(\.$category == .subject)
				.filter(\.$isArchived == false)
				.all()
		}

		try await req.db.transaction { database in
			let existingSubscriptions = try await AccountEventTagSubscription.query(on: database)
				.filter(\.$account.$id == user.requireID())
				.all()
			for subscription in existingSubscriptions {
				guard let tag = try await EventTag.find(subscription.$eventTag.id, on: database), tag.category == .subject else {
					continue
				}
				try await subscription.delete(on: database)
			}
			for tag in subjectTags {
				try await AccountEventTagSubscription(
					accountID: user.requireID(),
					eventTagID: try tag.requireID()
				).create(on: database)
			}
		}
		return try await EventTagSubscriptionResponse(tagIDs: subscriptionIDs(for: user, on: req.db))
	}

	private func user(_ req: Request) async throws -> User {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw Abort(.notFound)
		}
		return user
	}

	private func subscriptionIDs(for user: User, on database: any Database) async throws -> [UUID] {
		try await AccountEventTagSubscription.query(on: database)
			.filter(\.$account.$id == user.requireID())
			.all()
			.compactMap { try? $0.$eventTag.id }
	}
}

private struct EventTagCatalogueResponse: Content {
	let sections: [EventTagSectionResponse]
}

private struct EventTagSectionResponse: Content {
	let id: UUID
	let category: EventTagCategory
	let displayName: String
	let tags: [EventTagResponse]

	init(_ section: EventTagSection, tags: [EventTag]) throws {
		id = try section.requireID()
		category = section.category
		displayName = section.displayName
		self.tags = try tags.map(EventTagResponse.init)
	}
}

private struct EventTagResponse: Content {
	let id: UUID
	let displayName: String
	let category: EventTagCategory
	let symbol: String?
	let colorHex: String?

	init(_ tag: EventTag) throws {
		id = try tag.requireID()
		displayName = tag.displayName
		category = tag.category
		symbol = tag.symbol
		colorHex = tag.colorHex
	}
}

private struct EventTagSubscriptionResponse: Content {
	let tagIDs: [UUID]
}

private struct EventTagSubscriptionUpdateRequest: Content {
	let tagIDs: [UUID]
}

private extension Array {
	func asyncMap<T>(_ transform: (Element) throws -> T) rethrows -> [T] {
		try map(transform)
	}
}
