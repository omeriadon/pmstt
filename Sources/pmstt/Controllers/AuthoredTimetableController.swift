import Fluent
import Vapor

struct AuthoredTimetableController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let routes = routes.grouped("v1", "timetables", "authored")
			.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())
		routes.get(use: list)
		routes.post(use: create)
		routes.put(":timetableID", use: update)
		routes.delete(":timetableID", use: delete)
	}

	func create(req: Request) async throws -> TimetableDetailResponse {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(AuthoredTimetableCreateRequest.self)
		let title = body.title.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !title.isEmpty, title.count <= 100 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The title must contain between 1 and 100 characters.", field: "title")
		}
		guard let user = try await User.find(payload.sub, on: req.db) else { throw Abort(.notFound) }
		let timetable = try AuthoredTimetable(
			authorUserID: payload.sub,
			subjectDisplayName: title,
			passSerialNumber: UUID().uuidString,
			subjectsData: JSONEncoder().encode(body.subjects),
			revision: 1,
			isSearchable: body.isSearchable
		)
		timetable.$author.value = user
		try await timetable.save(on: req.db)
		return try await ResolvedTimetable.authored(timetable).detail(on: req.db, viewerID: payload.sub)
	}

	func list(req: Request) async throws -> [TimetableDetailResponse] {
		let payload = try req.auth.require(UserPayload.self)
		let values = try await AuthoredTimetable.query(on: req.db).filter(\.$author.$id == payload.sub).with(\.$author).all()
		return try await values.asyncMap { try await ResolvedTimetable.authored($0).detail(on: req.db, viewerID: payload.sub) }
	}

	func update(req: Request) async throws -> TimetableDetailResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let id = req.parameters.get("timetableID", as: UUID.self), let timetable = try await AuthoredTimetable.query(on: req.db).filter(\.$id == id).filter(\.$author.$id == payload.sub).with(\.$author).first() else { throw Abort(.notFound) }
		let body = try req.content.decode(AuthoredTimetableUpdateRequest.self)
		let title = body.title.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !title.isEmpty, title.count <= 100 else { throw AppError(.badRequest, code: .invalidRequest, reason: "The title must contain between 1 and 100 characters.", field: "title") }
		timetable.subjectDisplayName = title
		timetable.subjectsData = try JSONEncoder().encode(body.subjects)
		timetable.isSearchable = body.isSearchable
		timetable.revision += 1
		try await timetable.save(on: req.db)
		if let record = try await PassRecord.query(on: req.db).filter(\.$serialNumber == timetable.passSerialNumber).first() {
			record.revision = timetable.revision
			try await record.save(on: req.db)
			try? await WalletPushService.sendUpdate(for: timetable.passSerialNumber, req: req)
		}
		return try await ResolvedTimetable.authored(timetable).detail(on: req.db, viewerID: payload.sub)
	}

	func delete(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		guard let id = req.parameters.get("timetableID", as: UUID.self), let timetable = try await AuthoredTimetable.query(on: req.db).filter(\.$id == id).filter(\.$author.$id == payload.sub).first() else { throw Abort(.notFound) }
		let serial = timetable.passSerialNumber
		try await timetable.delete(on: req.db)
		if let record = try await PassRecord.query(on: req.db).filter(\.$serialNumber == serial).first() {
			record.isDeleted = true
			record.revision += 1
			try await record.save(on: req.db)
			try? await WalletPushService.sendUpdate(for: serial, req: req)
		}
		return .noContent
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
}
