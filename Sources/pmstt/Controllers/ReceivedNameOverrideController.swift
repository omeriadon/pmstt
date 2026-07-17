import Fluent
import Vapor

struct ReceivedNameOverrideController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let overrides = routes.grouped("v1", "received-name-overrides")
		let protected = overrides.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())

		protected.get(use: getOverrides)
		protected.put(":serialNumber", use: updateOverride)
		protected.delete(":serialNumber", use: removeOverride)
	}

	func getOverrides(req: Request) async throws -> [ReceivedNameOverrideResponse] {
		let payload = try req.auth.require(UserPayload.self)
		return try await ReceivedNameOverride.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.sort(\.$passSerialNumber, .ascending)
			.all()
			.map {
				ReceivedNameOverrideResponse(
					serialNumber: $0.passSerialNumber,
					displayName: $0.displayName
				)
			}
	}

	func updateOverride(req: Request) async throws -> ReceivedNameOverrideResponse {
		let payload = try req.auth.require(UserPayload.self)
		let serialNumber = try req.parameters.require("serialNumber")
		let body = try req.content.decode(UpdateReceivedNameOverrideRequest.self)
		let displayName = body.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

		guard !serialNumber.isEmpty, serialNumber.count <= 200 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "Invalid pass serial number.")
		}
		guard !displayName.isEmpty, displayName.count <= 100 else {
			throw AppError(
				.badRequest,
				code: .invalidRequest,
				reason: "The display name must contain between 1 and 100 characters.",
				field: "displayName"
			)
		}

		guard try await ReceivedPassMirror.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.filter(\.$passSerialNumber == serialNumber)
			.first() != nil
		else {
			req.logger.warning("not found")
			throw AppError(.notFound, code: .notFound, reason: "Received timetable not found.")
		}

		let record = try await ReceivedNameOverride.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.filter(\.$passSerialNumber == serialNumber)
			.first() ?? ReceivedNameOverride(
				userID: payload.sub,
				passSerialNumber: serialNumber,
				displayName: displayName
			)
		record.displayName = displayName
		try await record.save(on: req.db)

		return ReceivedNameOverrideResponse(serialNumber: serialNumber, displayName: displayName)
	}

	func removeOverride(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		let serialNumber = try req.parameters.require("serialNumber")
		try await ReceivedNameOverride.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.filter(\.$passSerialNumber == serialNumber)
			.delete()
		return .noContent
	}
}
