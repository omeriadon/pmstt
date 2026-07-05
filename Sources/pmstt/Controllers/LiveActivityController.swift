import Fluent
import Vapor

struct LiveActivityController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let protected = routes
			.grouped("v1")
			.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())

		protected.put("devices", "current", "live-activity-token", use: registerPushToStartToken)
		protected.delete("devices", "current", "live-activity-token", use: removePushToStartToken)
		protected.put("live-activities", ":activityKey", "update-token", use: registerUpdateToken)
		protected.post("live-activities", "current", "reconcile", use: reconcileCurrentActivity)
	}

	func registerPushToStartToken(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(LiveActivityPushToStartTokenRequest.self)
		try validate(installationID: body.installationID, token: body.token)

		let device = try await UserDevice.query(on: req.db)
			.filter(\.$installationID == body.installationID)
			.first() ?? UserDevice(userID: payload.sub, installationID: body.installationID, platform: "iOS")
		device.$user.id = payload.sub
		device.platform = "iOS"
		device.isDebug = body.isDebug
		device.liveActivityPushToStartToken = body.token
		device.lastSeenAt = Date()
		try await device.save(on: req.db)
		return .noContent
	}

	func removePushToStartToken(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(RemoveLiveActivityTokenRequest.self)
		try validateInstallationID(body.installationID)

		if let device = try await device(userID: payload.sub, installationID: body.installationID, database: req.db) {
			await SchoolDayActivityCoordinator().endActivities(for: device, database: req.db, logger: req.logger)
			device.liveActivityPushToStartToken = nil
			device.lastSeenAt = Date()
			try await device.save(on: req.db)
		}
		return .noContent
	}

	func registerUpdateToken(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(LiveActivityUpdateTokenRequest.self)
		guard let activityKey = req.parameters.get("activityKey"), UUID(uuidString: activityKey) != nil else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The Live Activity key is invalid.", field: "activityKey")
		}
		try validate(installationID: body.installationID, token: body.token)

		guard let device = try await device(userID: payload.sub, installationID: body.installationID, database: req.db),
		      let activity = try await SchoolDayLiveActivity.query(on: req.db)
		      .filter(\.$userDevice.$id == device.requireID())
		      .filter(\.$activityKey == activityKey)
		      .first()
		else {
			throw AppError(.notFound, code: .notFound, reason: "Live Activity not found.")
		}

		device.isDebug = body.isDebug
		device.lastSeenAt = Date()
		activity.updateToken = body.token
		try await device.save(on: req.db)
		try await activity.save(on: req.db)
		return .noContent
	}

	func reconcileCurrentActivity(req: Request) async throws -> ReconcileLiveActivityResponse {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(ReconcileLiveActivityRequest.self)
		try validateInstallationID(body.installationID)

		guard let device = try await device(userID: payload.sub, installationID: body.installationID, database: req.db) else {
			throw AppError(.notFound, code: .notFound, reason: "Device not found.")
		}

		let started = try await SchoolDayActivityScheduler().startCurrentActivity(
			for: device,
			at: Date(),
			database: req.db,
			logger: req.logger
		)
		return ReconcileLiveActivityResponse(started: started)
	}

	private func device(userID: UUID, installationID: String, database: any Database) async throws -> UserDevice? {
		try await UserDevice.query(on: database)
			.filter(\.$user.$id == userID)
			.filter(\.$installationID == installationID)
			.first()
	}

	private func validate(installationID: String, token: String) throws {
		try validateInstallationID(installationID)
		guard token.count >= 32, token.count <= 512, token.allSatisfy(\.isHexDigit) else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The Live Activity token is invalid.", field: "token")
		}
	}

	private func validateInstallationID(_ installationID: String) throws {
		guard !installationID.isEmpty, installationID.count <= 200 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The installation ID is invalid.", field: "installationID")
		}
	}
}
