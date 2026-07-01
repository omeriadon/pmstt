import Fluent
import Vapor

struct PassController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let passes = routes.grouped("v1", "passes")
		let protected = passes.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())

		protected.get("owner", use: getOwnerPass)
		protected.get("received", ":serialNumber", use: getReceivedPass)
	}

	func getOwnerPass(req: Request) async throws -> Response {
		let payload = try req.auth.require(UserPayload.self)

		guard let ownerTimetable = try await OwnerTimetable.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.with(\.$user)
			.first()
		else {
			req.logger.warning("Owner pass failed: no owner timetable for user id \(payload.sub)")
			throw Abort(.notFound, reason: "No timetable data has been uploaded yet.")
		}

		return try await PassFactory.response(for: .owner(ownerTimetable), req: req)
	}

	func getReceivedPass(req: Request) async throws -> Response {
		let payload = try req.auth.require(UserPayload.self)
		let serial = try req.parameters.require("serialNumber")
		guard let mirror = try await ReceivedPassMirror.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.filter(\.$passSerialNumber == serial)
			.filter(\.$isDeleted == false)
			.first(), mirror.isShareable
		else {
			throw Abort(.notFound, reason: "This timetable is not available for sharing.")
		}

		if let issuerAccountID = UUID(uuidString: mirror.issuerAccountID),
		   let owner = try await OwnerTimetable.query(on: req.db)
			.filter(\.$user.$id == issuerAccountID)
			.filter(\.$isSearchable == true)
			.with(\.$user)
			.first(), owner.user.selfPassSerialNumber == serial
		{
			return try await PassFactory.response(for: .owner(owner), req: req)
		}

		if let authored = try await AuthoredTimetable.query(on: req.db)
			.filter(\.$passSerialNumber == serial)
			.filter(\.$isSearchable == true)
			.with(\.$author)
			.first()
		{
			return try await PassFactory.response(for: .authored(authored), req: req)
		}

		throw Abort(.notFound, reason: "This timetable is no longer available for sharing.")
	}
}
