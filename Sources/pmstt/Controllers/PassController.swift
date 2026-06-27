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

		// 1. Fetch user to get selfPassSerialNumber and displayName
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw Abort(.notFound, reason: "User not found.")
		}

		// 2. Fetch user's OwnerTimetable
		guard let ownerTimetable = try await OwnerTimetable.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.first()
		else {
			throw Abort(.notFound, reason: "No timetable data has been uploaded yet.")
		}

		// 3. Resolve passes resource directory path
		let workingDir = req.application.directory.workingDirectory
		let resourceDirectory = URL(fileURLWithPath: workingDir)
			.appendingPathComponent("Sources")
			.appendingPathComponent("pmstt")
			.appendingPathComponent("Services")
			.appendingPathComponent("Passes")

		// 4. Generate the Apple Wallet pass
		let fileURL: URL
		do {
			fileURL = try await generatePass(
				serialNumber: user.selfPassSerialNumber,
				displayName: user.displayName,
				subjectsData: ownerTimetable.subjectsData,
				resourceDirectory: resourceDirectory
			)
		} catch {
			req.logger.error("Pass generation failed: \(error)")
			throw Abort(.internalServerError, reason: "Failed to generate Apple Wallet pass.")
		}

		// 5. Read generated pass bytes
		let data = try Data(contentsOf: fileURL)

		// 6. Cleanup temporary directory
		try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())

		// 7. Construct Response with Apple Wallet Content-Type
		let response = Response(
			status: .ok,
			headers: [
				"Content-Type": "application/vnd.apple.pkpass",
				"Content-Disposition": "attachment; filename=\"timetable.pkpass\""
			],
			body: .init(data: data)
		)

		return response
	}
}
