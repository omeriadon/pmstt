import Vapor

func routes(_ app: Application) throws {
	app.get("health") { req async -> HealthResponse in
		req.logger.debug("Health check completed")
		return HealthResponse(
			status: "ok",
			uptime: Int(ProcessInfo.processInfo.systemUptime)
		)
	}

	app.post("register", "pushToken") { req async throws -> HTTPStatus in
		struct Body: Content {
			let token: String
		}

		let body = try req.content.decode(Body.self)

		savePushStartToken(body.token)

		return .ok
	}

	app.post("v1", "report", "user") { req async throws -> HTTPStatus in
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(ReportUserRequest.self)

		let reporterUserID = payload.sub

		guard let reportedUserID = UUID(uuidString: body.reportedAccountID) else {
			throw AppError(
				.badRequest,
				code: .accountNotFound,
				reason: "Unable to convert reportedUserID from string to UUID. This most likely means reportedUserID isn't a valid user ID.",
				field: "reportedUserID"
			)
		}

		guard reporterUserID != reportedUserID else {
			throw AppError(
				.badRequest,
				code: .invalidRequest,
				reason: "You cannot report yourself.",
				field: "reportedUserID"
			)
		}

		guard try await User.find(reportedUserID, on: req.db) != nil else {
			throw AppError(
				.notFound,
				code: .notFound,
				reason: "Reported user was not found.",
				field: "reportedUserID"
			)
		}

		guard try await User.find(reporterUserID, on: req.db) != nil else {
			throw Abort(.unauthorized)
		}

		return try await sendReportEmail(body: body, req: req)
	}

	try app.register(collection: AuthController())
	try app.register(collection: AccountController())
	try app.register(collection: OwnerTimetableController())
	try app.register(collection: ReceivedTimetableController())
	try app.register(collection: ReceivedNameOverrideController())
	try app.register(collection: SettingsController())
	try app.register(collection: PassController())
}

struct HealthResponse: Content {
	let status: String
	let uptime: Int
}
