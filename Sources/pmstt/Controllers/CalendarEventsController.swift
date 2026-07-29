import Fluent
import Vapor

struct CalendarEventsController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let events = routes.grouped("v1", "events")
		let protected = events.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		protected.get(use: list)
		protected.post("private", use: createPrivate)
		protected.delete("private", ":eventID", use: deletePrivate)
		protected.put("private", ":eventID", use: updatePrivate)
		protected.post("global", use: createGlobal)
		protected.delete("global", ":eventID", use: deleteGlobal)
		protected.put("global", ":eventID", use: updateGlobal)
	}

	private func list(req: Request) async throws -> CalendarEventsResponse {
		try await response(for: authenticatedUser(req), on: req)
	}

	private func createPrivate(req: Request) async throws -> CalendarEventsResponse {
		let user = try await authenticatedUser(req)
		let request = try req.content.decode(CreateCalendarEventRequest.self)
		try validate(request)
		let event = CalendarEvent(
			id: request.id,
			userID: user.requireID(),
			title: request.title,
			notes: request.notes,
			symbol: request.symbol,
			eventDate: request.date.storageValue,
			isGlobal: false
		)
		try await req.db.transaction { database in
			try await event.create(on: database)
			try await replaceTagAssociations(request.tagIDs, for: event, isGlobal: false, on: database)
		}
		return try await response(for: user, on: req)
	}

	private func deletePrivate(req: Request) async throws -> CalendarEventsResponse {
		let user = try await authenticatedUser(req)
		let event = try await ownedEvent(req: req, user: user, globally: false)
		try requireMatchingRevision(
			req.query[Int.self, at: "baseRevision"],
			for: event
		)
		let eventID = try event.requireID()
		try await req.db.transaction { database in
			try await event.delete(on: database)
			try await SyncRecordTombstone(
				userID: user.requireID(),
				recordType: .privateCalendarEvent,
				recordID: eventID,
				revision: event.revision + 1
			).create(on: database)
		}
		return try await response(for: user, on: req)
	}

	private func updatePrivate(req: Request) async throws -> CalendarEventsResponse {
		let user = try await authenticatedUser(req)
		let event = try await ownedEvent(req: req, user: user, globally: false)
		let request = try req.content.decode(CreateCalendarEventRequest.self)
		try requireMatchingRevision(request.baseRevision, for: event)
		try update(event, with: request)
		event.revision += 1
		try await req.db.transaction { database in
			try await event.update(on: database)
			try await replaceTagAssociations(request.tagIDs, for: event, isGlobal: false, on: database)
		}
		return try await response(for: user, on: req)
	}

	private func createGlobal(req: Request) async throws -> CalendarEventsResponse {
		let user = try await authenticatedUser(req)
		try requireGlobalEventAuthority(user)
		let request = try req.content.decode(CreateCalendarEventRequest.self)
		try validate(request)
		let event = CalendarEvent(
			id: request.id,
			userID: user.requireID(),
			title: request.title,
			notes: request.notes,
			symbol: request.symbol,
			eventDate: request.date.storageValue,
			isGlobal: true
		)
		try await req.db.transaction { database in
			try await event.create(on: database)
			try await replaceTagAssociations(request.tagIDs, for: event, isGlobal: true, on: database)
		}
		return try await response(for: user, on: req)
	}

	private func deleteGlobal(req: Request) async throws -> CalendarEventsResponse {
		let user = try await authenticatedUser(req)
		try requireGlobalEventAuthority(user)
		let event = try await ownedEvent(req: req, user: user, globally: true, requiresOwner: false)
		try await event.delete(on: req.db)
		return try await response(for: user, on: req)
	}

	private func updateGlobal(req: Request) async throws -> CalendarEventsResponse {
		let user = try await authenticatedUser(req)
		try requireGlobalEventAuthority(user)
		let event = try await ownedEvent(req: req, user: user, globally: true, requiresOwner: false)
		let request = try req.content.decode(CreateCalendarEventRequest.self)
		try requireMatchingRevision(request.baseRevision, for: event)
		try update(event, with: request)
		event.revision += 1
		try await req.db.transaction { database in
			try await event.update(on: database)
			try await replaceTagAssociations(request.tagIDs, for: event, isGlobal: true, on: database)
		}
		return try await response(for: user, on: req)
	}

	private func response(for user: User, on req: Request) async throws -> CalendarEventsResponse {
		let globalEvents = try await visibleGlobalEvents(for: user, on: req.db)
		let privateEvents = try await CalendarEvent.query(on: req.db)
			.filter(\.$isGlobal == false).filter(\.$user.$id == user.requireID()).all()
		return try CalendarEventsResponse(
			globalEvents: try await globalEvents.asyncMap { try await CalendarEventResponse($0, on: req.db) },
			privateEvents: try await privateEvents.asyncMap { try await CalendarEventResponse($0, on: req.db) },
			canManageGlobalEvents: canManageGlobalEvents(user)
		)
	}

	private func ownedEvent(req: Request, user: User, globally: Bool, requiresOwner: Bool = true) async throws -> CalendarEvent {
		guard let id = req.parameters.get("eventID", as: UUID.self),
		      let event = try await CalendarEvent.find(id, on: req.db), event.isGlobal == globally
		else { throw Abort(.notFound) }
		if requiresOwner {
			guard try event.$user.id == user.requireID() else {
				throw Abort(.forbidden)
			}
		}
		return event
	}

	private func authenticatedUser(_ req: Request) async throws -> User {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else { throw Abort(.notFound) }
		return user
	}

	private func requireGlobalEventAuthority(_ user: User) throws {
		guard canManageGlobalEvents(user) else {
			throw Abort(.forbidden)
		}
	}

	private func canManageGlobalEvents(_ user: User) -> Bool {
		user.resolvedAccountAuthority.isAdministrator
	}

	private func validate(_ request: CreateCalendarEventRequest) throws {
		guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
		      request.title.count <= 120, request.symbol.count <= 120, request.notes?.count ?? 0 <= 2000
		else { throw Abort(.badRequest) }
	}

	private func update(_ event: CalendarEvent, with request: CreateCalendarEventRequest) throws {
		try validate(request)
		event.title = request.title
		event.notes = request.notes
		event.symbol = request.symbol
		event.eventDate = request.date.storageValue
	}

	private func requireMatchingRevision(
		_ baseRevision: Int?,
		for event: CalendarEvent
	) throws {
		guard let baseRevision else {
			return
		}
		guard baseRevision == event.revision else {
			throw Abort(
				.conflict,
				reason: "The calendar event has changed on the server."
			)
		}
	}

	private func replaceTagAssociations(
		_ requestedTagIDs: [UUID],
		for event: CalendarEvent,
		isGlobal: Bool,
		on database: any Database
	) async throws {
		let uniqueTagIDs = Array(Set(requestedTagIDs))
		let tags: [EventTag]
		if uniqueTagIDs.isEmpty {
			tags = []
		} else {
			tags = try await EventTag.query(on: database)
				.filter(\.$id ~~ uniqueTagIDs)
				.filter(\.$isArchived == false)
				.all()
		}
		if !isGlobal, tags.contains(where: { $0.category == .yearGroup }) {
			throw Abort(.badRequest)
		}

		try await CalendarEventTag.query(on: database)
			.filter(\.$calendarEvent.$id == event.requireID())
			.delete()
		for tag in tags {
			try await CalendarEventTag(
				calendarEventID: event.requireID(),
				eventTagID: try tag.requireID()
			).create(on: database)
		}
	}

	private func visibleGlobalEvents(for user: User, on database: any Database) async throws -> [CalendarEvent] {
		let globalEvents = try await CalendarEvent.query(on: database)
			.filter(\.$isGlobal == true)
			.all()
		guard !canManageGlobalEvents(user) else {
			return globalEvents
		}

		let subscribedTagIDs = Set(try await AccountEventTagSubscription.query(on: database)
			.filter(\.$account.$id == user.requireID())
			.all()
			.map { try $0.$eventTag.id })

		return try await globalEvents.asyncFilter { event in
			let assignedTags = try await tags(for: event, on: database)
			let yearTagIDs = Set(assignedTags.filter { $0.category == .yearGroup }.compactMap(\.id))
			let ordinaryTagIDs = Set(assignedTags.filter { $0.category != .yearGroup }.compactMap(\.id))
			let matchesOrdinaryTags = ordinaryTagIDs.isEmpty || !ordinaryTagIDs.isDisjoint(with: subscribedTagIDs)
			let matchesYearGroup = yearTagIDs.isEmpty || !yearTagIDs.isDisjoint(with: subscribedTagIDs)
			return matchesOrdinaryTags && matchesYearGroup
		}
	}

	private func tags(for event: CalendarEvent, on database: any Database) async throws -> [EventTag] {
		let associations = try await CalendarEventTag.query(on: database)
			.filter(\.$calendarEvent.$id == event.requireID())
			.all()
		let tagIDs = associations.compactMap { try? $0.$eventTag.id }
		guard !tagIDs.isEmpty else {
			return []
		}
		return try await EventTag.query(on: database)
			.filter(\.$id ~~ tagIDs)
			.filter(\.$isArchived == false)
			.all()
	}
}

private struct CreateCalendarEventRequest: Content {
	let id: UUID?
	let title: String
	let notes: String?
	let symbol: String
	let date: SchoolCalendarDate
	let tagIDs: [UUID]
	let baseRevision: Int?
}

private struct CalendarEventsResponse: Content {
	let globalEvents: [CalendarEventResponse]
	let privateEvents: [CalendarEventResponse]
	let canManageGlobalEvents: Bool
}

private struct CalendarEventResponse: Content {
	let id: UUID
	let title: String
	let notes: String?
	let symbol: String
	let date: SchoolCalendarDate
	let isGlobal: Bool
	let tagIDs: [UUID]
	let revision: Int
	let updatedAt: Date?

	init(_ event: CalendarEvent, on database: any Database) async throws {
		id = try event.requireID()
		title = event.title
		notes = event.notes
		symbol = event.symbol
		date = try SchoolCalendarDate(storageValue: event.eventDate)
		isGlobal = event.isGlobal
		tagIDs = try await CalendarEventsController().tags(for: event, on: database).compactMap(\.id)
		revision = event.revision
		updatedAt = event.updatedAt
	}
}

private extension Array {
	func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
		var result: [T] = []
		for element in self {
			try await result.append(transform(element))
		}
		return result
	}

	func asyncFilter(_ isIncluded: (Element) async throws -> Bool) async rethrows -> [Element] {
		var result: [Element] = []
		for element in self where try await isIncluded(element) {
			result.append(element)
		}
		return result
	}
}

private extension SchoolCalendarDate {
	var storageValue: String {
		String(format: "%04d-%02d-%02d", year, month, day)
	}

	init(storageValue: String) throws {
		let parts = storageValue.split(separator: "-").compactMap { Int($0) }
		guard parts.count == 3 else { throw Abort(.internalServerError) }
		year = parts[0]; month = parts[1]; day = parts[2]
	}
}
