import Fluent
import Vapor

struct GradeTrackerController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		routes.grouped("v1", "grades")
			.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
			.get(use: get)
			.put(use: update)
	}

	func get(req: Request) async throws -> GradeTrackerResponse {
		let user = try await authenticatedUser(req)
		return try response(for: user)
	}

	func update(req: Request) async throws -> GradeTrackerResponse {
		let request = try req.content.decode(GradeTrackerUpdateRequest.self)
		let user = try await authenticatedUser(req)

		if let serverRevision = request.serverRevision,
		   serverRevision != user.gradeTrackerRevision
		{
			throw Abort(.conflict, reason: "Grade tracker has changed on the server.")
		}

		user.gradeTrackerRevision += 1
		var document = request.document
		document.serverRevision = user.gradeTrackerRevision
		user.gradeTrackerData = try JSONEncoder().encode(document)
		try await user.save(on: req.db)
		return try response(for: user)
	}

	private func authenticatedUser(_ req: Request) async throws -> User {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw Abort(.notFound)
		}
		return user
	}

	private func response(for user: User) throws -> GradeTrackerResponse {
		var document = user.gradeTrackerData
			.flatMap { try? JSONDecoder().decode(GradeTrackerDocument.self, from: $0) }
			?? .empty
		document.serverRevision = user.gradeTrackerRevision
		return GradeTrackerResponse(document: document)
	}
}
