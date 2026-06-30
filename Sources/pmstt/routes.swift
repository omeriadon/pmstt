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

	try app.register(collection: AuthController())
	try app.register(collection: AccountController())
	try app.register(collection: OwnerTimetableController())
	try app.register(collection: ReceivedTimetableController())
	try app.register(collection: ReceivedNameOverrideController())
	try app.register(collection: SettingsController())
	try app.register(collection: PassController())
	try app.register(collection: NotificationController())
	try app.register(collection: ReportController())
	try app.register(collection: AuthoredTimetableController())
	try app.register(collection: TimetableDiscoveryController())
	try app.register(collection: WalletWebServiceController())
}

struct HealthResponse: Content {
	let status: String
	let uptime: Int
}
