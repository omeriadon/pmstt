import Fluent
import Vapor

struct CalendarEventsController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let events = routes.grouped("v1", "events")
		let protected = events.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		protected.get(use: list)
		protected.post("private", use: createPrivate)
		protected.delete("private", ":eventID", use: deletePrivate)
		protected.post("global", use: createGlobal)
		protected.delete("global", ":eventID", use: deleteGlobal)
	}

	private func list(req: Request) async throws -> CalendarEventsResponse {
		try await response(for: authenticatedUser(req), on: req)
	}

	private func createPrivate(req: Request) async throws -> CalendarEventsResponse {
		let user = try await authenticatedUser(req)
		let request = try req.content.decode(CreateCalendarEventRequest.self)
		try validate(request)
		try await CalendarEvent(
			userID: user.requireID(), title: request.title, notes: request.notes,
			symbol: request.symbol, eventDate: request.date.storageValue, isGlobal: false
		).create(on: req.db)
		return try await response(for: user, on: req)
	}

	private func deletePrivate(req: Request) async throws -> CalendarEventsResponse {
		let user = try await authenticatedUser(req)
		let event = try await ownedEvent(req: req, user: user, globally: false)
		try await event.delete(on: req.db)
		return try await response(for: user, on: req)
	}

	private func createGlobal(req: Request) async throws -> CalendarEventsResponse {
		let user = try await authenticatedUser(req)
		try requireGlobalEventAuthority(user, req: req)
		let request = try req.content.decode(CreateCalendarEventRequest.self)
		try validate(request)
		try await CalendarEvent(
			userID: user.requireID(), title: request.title, notes: request.notes,
			symbol: request.symbol, eventDate: request.date.storageValue, isGlobal: true
		).create(on: req.db)
		return try await response(for: user, on: req)
	}

	private func deleteGlobal(req: Request) async throws -> CalendarEventsResponse {
		let user = try await authenticatedUser(req)
		try requireGlobalEventAuthority(user, req: req)
		let event = try await ownedEvent(req: req, user: user, globally: true, requiresOwner: false)
		try await event.delete(on: req.db)
		return try await response(for: user, on: req)
	}

	private func response(for user: User, on req: Request) async throws -> CalendarEventsResponse {
		let globalEvents = try await CalendarEvent.query(on: req.db).filter(\.$isGlobal == true).all()
		let privateEvents = try await CalendarEvent.query(on: req.db)
			.filter(\.$isGlobal == false).filter(\.$user.$id == user.requireID()).all()
		return try CalendarEventsResponse(
			globalEvents: globalEvents.map(CalendarEventResponse.init),
			privateEvents: privateEvents.map(CalendarEventResponse.init),
			canManageGlobalEvents: canManageGlobalEvents(user, req: req)
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

	private func requireGlobalEventAuthority(_ user: User, req: Request) throws {
		guard canManageGlobalEvents(user, req: req) else { throw Abort(.forbidden) }
	}

	private func canManageGlobalEvents(_ user: User, req _: Request) -> Bool {
		let allowedEmails = Set((Environment.get("TIMETABLE_EVENT_ADMIN_EMAILS") ?? "")
			.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
		guard let email = user.email?.lowercased() else { return false }
		return allowedEmails.contains(email)
	}

	private func validate(_ request: CreateCalendarEventRequest) throws {
		guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
		      request.title.count <= 120, request.symbol.count <= 120, request.notes?.count ?? 0 <= 2000
		else { throw Abort(.badRequest) }
	}
}

private struct CreateCalendarEventRequest: Content {
	let title: String
	let notes: String?
	let symbol: String
	let date: SchoolCalendarDate
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

	init(_ event: CalendarEvent) throws {
		id = try event.requireID()
		title = event.title
		notes = event.notes
		symbol = event.symbol
		date = try SchoolCalendarDate(storageValue: event.eventDate)
		isGlobal = event.isGlobal
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
