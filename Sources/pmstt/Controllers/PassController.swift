import Fluent
import Vapor

struct PassController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let passes = routes.grouped("v1", "passes")
		let protected = passes.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())

		protected.get("owner", use: getOwnerPass)
	}

	func getOwnerPass(req: Request) async throws -> Response {
		let payload = try req.auth.require(UserPayload.self)

		req.logger.info("test")

		// 1. Fetch user to get selfPassSerialNumber and displayName
		guard let user = try await User.find(payload.sub, on: req.db) else {
			req.logger.warning("Owner pass failed: user not found for id \(payload.sub)")
			throw Abort(.notFound, reason: "User not found.")
		}

		// 2. Fetch user's OwnerTimetable
		guard let ownerTimetable = try await OwnerTimetable.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.first()
		else {
			req.logger.warning("Owner pass failed: no owner timetable for user id \(payload.sub)")
			throw Abort(.notFound, reason: "No timetable data has been uploaded yet.")
		}

		ownerTimetable.user = user
		return try await PassFactory.response(for: .owner(ownerTimetable), req: req)
	}
}
