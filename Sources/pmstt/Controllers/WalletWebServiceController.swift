import Fluent
import Vapor

struct WalletWebServiceController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let v1 = routes.grouped("v1")
		v1.post("devices", ":deviceID", "registrations", ":passTypeID", ":serialNumber", use: register)
		v1.delete("devices", ":deviceID", "registrations", ":passTypeID", ":serialNumber", use: unregister)
		v1.get("devices", ":deviceID", "registrations", ":passTypeID", use: changedSerials)
		v1.get("passes", ":passTypeID", ":serialNumber", use: updatedPass)
	}

	func register(req: Request) async throws -> HTTPStatus {
		let body = try req.content.decode(WalletRegistrationRequest.self)
		let (device, passType, serial) = try parameters(req)
		let record = try await authenticatedRecord(req: req, serial: serial)
		guard passType == expectedPassType else { throw Abort(.notFound) }
		let existing = try await PassRegistration.query(on: req.db).filter(\.$deviceLibraryIdentifier == device).filter(\.$serialNumber == serial).first()
		let registration = existing ?? PassRegistration(deviceLibraryIdentifier: device, passTypeIdentifier: passType, serialNumber: serial, pushToken: body.pushToken)
		registration.pushToken = body.pushToken
		try await registration.save(on: req.db)
		_ = record
		return existing == nil ? .created : .ok
	}

	func unregister(req: Request) async throws -> HTTPStatus {
		let (device, passType, serial) = try parameters(req)
		_ = try await authenticatedRecord(req: req, serial: serial)
		guard passType == expectedPassType else { throw Abort(.notFound) }
		try await PassRegistration.query(on: req.db).filter(\.$deviceLibraryIdentifier == device).filter(\.$serialNumber == serial).delete()
		if let record = try await PassRecord.query(on: req.db).filter(\.$serialNumber == serial).first(), record.isDeleted,
		   try await PassRegistration.query(on: req.db).filter(\.$serialNumber == serial).count() == 0 { try await record.delete(on: req.db) }
		return .ok
	}

	func changedSerials(req: Request) async throws -> WalletSerialNumbersResponse {
		guard let device = req.parameters.get("deviceID"), req.parameters.get("passTypeID") == expectedPassType else { throw Abort(.notFound) }
		let since = Int(req.query[String.self, at: "passesUpdatedSince"] ?? "") ?? -1
		let registrations = try await PassRegistration.query(on: req.db).filter(\.$deviceLibraryIdentifier == device).all()
		var serials: [String] = []
		var latest = since
		for registration in registrations {
			if let record = try await PassRecord.query(on: req.db).filter(\.$serialNumber == registration.serialNumber).first(), record.revision > since {
				serials.append(record.serialNumber)
				latest = max(latest, record.revision)
			}
		}
		return .init(serialNumbers: serials, lastUpdated: String(max(latest, 0)))
	}

	func updatedPass(req: Request) async throws -> Response {
		guard req.parameters.get("passTypeID") == expectedPassType, let serial = req.parameters.get("serialNumber") else { throw Abort(.notFound) }
		let record = try await authenticatedRecord(req: req, serial: serial)
		if record.isDeleted { return try await PassFactory.deletedResponse(record: record, req: req) }
		if let authored = try await AuthoredTimetable.query(on: req.db).filter(\.$passSerialNumber == serial).with(\.$author).first() { return try await PassFactory.response(for: .authored(authored), req: req) }
		if let user = try await User.query(on: req.db).filter(\.$selfPassSerialNumber == serial).first(), let userID = user.id, let owner = try await OwnerTimetable.query(on: req.db).filter(\.$user.$id == userID).first() {
			owner.user = user
			return try await PassFactory.response(for: .owner(owner), req: req)
		}
		throw Abort(.notFound)
	}

	private var expectedPassType: String { Environment.get("PASS_TYPE_IDENTIFIER") ?? "pass.com.omeriadon.Timetable" }

	private func parameters(_ req: Request) throws -> (String, String, String) {
		guard let device = req.parameters.get("deviceID"), let passType = req.parameters.get("passTypeID"), let serial = req.parameters.get("serialNumber") else { throw Abort(.badRequest) }
		return (device, passType, serial)
	}

	private func authenticatedRecord(req: Request, serial: String) async throws -> PassRecord {
		guard let authorization = req.headers.bearerAuthorization, authorization.token.hasPrefix("ApplePass ") == false else {
			let raw = req.headers.first(name: .authorization) ?? ""
			guard raw.hasPrefix("ApplePass ") else { throw Abort(.unauthorized) }
			return try await verify(token: String(raw.dropFirst("ApplePass ".count)), serial: serial, req: req)
		}
		return try await verify(token: authorization.token, serial: serial, req: req)
	}

	private func verify(token: String, serial: String, req: Request) async throws -> PassRecord {
		guard let record = try await PassRecord.query(on: req.db).filter(\.$serialNumber == serial).first(), record.authenticationTokenHash == PassFactory.tokenHash(token) else { throw Abort(.unauthorized) }
		return record
	}
}
