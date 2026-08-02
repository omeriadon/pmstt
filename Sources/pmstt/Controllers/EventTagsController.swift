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
			let tagResponses = try await tags.asyncMap { tag in
				try await EventTagResponse(tag, on: req.db)
			}
			return try EventTagSectionResponse(section, tags: tagResponses)
		})
	}

	private func subscriptions(req: Request) async throws -> EventTagSubscriptionResponse {
		let user = try await user(req)
		return try await EventTagSubscriptionResponse(
			tagIDs: subscriptionIDs(for: user, on: req.db),
			droppedTagIDs: []
		)
	}

	private func replaceSubscriptions(req: Request) async throws -> EventTagSubscriptionResponse {
		let user = try await user(req)
		let userID = try user.requireID()
		let request = try req.content.decode(EventTagSubscriptionUpdateRequest.self)
		let requestedTagIDs = Array(Set(request.tagIDs))
		var tags: [EventTag] = if requestedTagIDs.isEmpty {
			[]
		} else {
			try await EventTag.query(on: req.db)
				.filter(\.$id ~~ requestedTagIDs)
				.filter(\.$isArchived == false)
				.all()
		}
		if !tags.contains(where: { $0.category == .yearGroup }),
		   let defaultYearGroup = try await EventTag.query(on: req.db)
				.filter(\.$category == .yearGroup)
				.filter(\.$slug == "year-7")
				.filter(\.$isArchived == false)
				.first()
		{
			tags.append(defaultYearGroup)
		}
		let tagIDs = try tags.map { try $0.requireID() }
		let droppedTagIDs = requestedTagIDs.filter { !tagIDs.contains($0) }

		try await req.db.transaction { database in
			try await AccountEventTagSubscription.query(on: database)
				.filter(\.$account.$id == userID)
				.delete()
			for tagID in tagIDs {
				try await AccountEventTagSubscription(
					accountID: userID,
					eventTagID: tagID
				).create(on: database)
			}
		}
		return EventTagSubscriptionResponse(
			tagIDs: tagIDs,
			droppedTagIDs: droppedTagIDs
		)
	}

	private func replaceSubjectSubscriptions(req: Request) async throws -> EventTagSubscriptionResponse {
		let user = try await user(req)
		let userID = try user.requireID()
		let request = try req.content.decode(EventTagSubscriptionUpdateRequest.self)
		let requestedTagIDs = Array(Set(request.tagIDs))
		let subjectTags: [EventTag] = if requestedTagIDs.isEmpty {
			[]
		} else {
			try await EventTag.query(on: req.db)
				.filter(\.$id ~~ requestedTagIDs)
				.filter(\.$category == .subject)
				.filter(\.$isArchived == false)
				.all()
		}

		try await req.db.transaction { database in
			let existingSubscriptions = try await AccountEventTagSubscription.query(on: database)
				.filter(\.$account.$id == userID)
				.all()
			for subscription in existingSubscriptions {
				guard let tag = try await EventTag.find(subscription.$eventTag.id, on: database), tag.category == .subject else {
					continue
				}
				try await subscription.delete(on: database)
			}
			for tag in subjectTags {
				try await AccountEventTagSubscription(
					accountID: userID,
					eventTagID: tag.requireID()
				).create(on: database)
			}
		}
		let acceptedSubjectTagIDs = try subjectTags.map {
			try $0.requireID()
		}
		let droppedTagIDs = requestedTagIDs.filter {
			!acceptedSubjectTagIDs.contains($0)
		}
		return try await EventTagSubscriptionResponse(
			tagIDs: subscriptionIDs(for: user, on: req.db),
			droppedTagIDs: droppedTagIDs
		)
	}

	private func user(_ req: Request) async throws -> User {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw Abort(.notFound)
		}
		return user
	}

	private func subscriptionIDs(for user: User, on database: any Database) async throws -> [UUID] {
		let userID = try user.requireID()
		return try await AccountEventTagSubscription.query(on: database)
			.filter(\.$account.$id == userID)
			.all()
			.map(\.$eventTag.id)
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

	init(_ section: EventTagSection, tags: [EventTagResponse]) throws {
		id = try section.requireID()
		category = section.category
		displayName = section.displayName
		self.tags = tags
	}
}

private struct EventTagResponse: Content {
	let id: UUID
	let displayName: String
	let category: EventTagCategory
	let symbol: String?
	let colorHex: String?
	let associatedNames: [String]

	init(_ tag: EventTag, on database: any Database) async throws {
		id = try tag.requireID()
		displayName = tag.displayName
		category = tag.category
		symbol = tag.symbol
		colorHex = tag.colorHex
		associatedNames = try await EventTagAssociatedName.query(on: database)
			.filter(\.$eventTag.$id == id)
			.sort(\.$displayName)
			.all()
			.map(\.displayName)
	}
}

private struct EventTagSubscriptionResponse: Content {
	let tagIDs: [UUID]
	let droppedTagIDs: [UUID]
}

private struct EventTagSubscriptionUpdateRequest: Content {
	let tagIDs: [UUID]
}

private extension Array {
	func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
		var results: [T] = []
		results.reserveCapacity(count)
		for element in self {
			try await results.append(transform(element))
		}
		return results
	}
}
