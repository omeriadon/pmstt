import Fluent
import Vapor

struct NotificationController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let protected = routes
			.grouped("v1")
			.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())

		protected.put("devices", "current", use: registerDevice)
		protected.delete("devices", "current", use: removeDevice)
		protected.put("devices", "current", "synchronize", use: synchronizeDevice)
		protected.post("notifications", "test", use: sendTestNotification)
	}

	func registerDevice(req: Request) async throws -> UserDeviceResponse {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(RegisterUserDeviceRequest.self)
		try validate(body)
		guard body.platform == payload.platform, body.installationID == payload.installationID else {
			throw Abort(.forbidden)
		}
		let existingDevice = try await UserDevice.query(on: req.db)
			.filter(\.$installationID == body.installationID)
			.first()
		if let existingDevice, existingDevice.$user.id != payload.sub {
			throw Abort(.forbidden)
		}
		let device = existingDevice ?? UserDevice(userID: payload.sub, installationID: body.installationID, platform: body.platform)

		device.$user.id = payload.sub
		device.platform = body.platform
		device.apnsToken = body.apnsToken
		device.isDebug = body.isDebug
		device.lastSeenAt = Date()
		try await device.save(on: req.db)
		let deviceID = try device.requireID()
		try await pruneStaleDevices(for: payload.sub, keeping: deviceID, platform: body.platform, database: req.db, logger: req.logger)
		req.logger.info("Registered device", metadata: [
			"user_id": .string(payload.sub.uuidString),
			"device_id": .string(deviceID.uuidString),
			"installation_id": .string(body.installationID),
			"platform": .string(body.platform),
			"has_apns_token": .stringConvertible(device.apnsToken != nil),
			"is_debug": .stringConvertible(body.isDebug),
		])
		return UserDeviceResponse(
			installationID: device.installationID,
			platform: device.platform,
			isDebug: device.isDebug,
			lastSeenAt: device.lastSeenAt
		)
	}

	func synchronizeDevice(req: Request) async throws -> UserDeviceResponse {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(SynchronizeUserDeviceRequest.self)
		try validate(body)
		guard body.platform == payload.platform, body.installationID == payload.installationID else {
			throw Abort(.forbidden)
		}

		let existingDevice = try await UserDevice.query(on: req.db)
			.filter(\.$installationID == body.installationID)
			.first()
		if let existingDevice, existingDevice.$user.id != payload.sub {
			throw Abort(.forbidden)
		}

		let device = existingDevice ?? UserDevice(
			userID: payload.sub,
			installationID: body.installationID,
			platform: body.platform
		)
		device.$user.id = payload.sub
		device.platform = body.platform
		device.osMajorVersion = body.osMajorVersion
		device.osMinorVersion = body.osMinorVersion
		device.isDebug = body.isDebug
		device.isBeta = body.isBeta
		device.lastSeenAt = Date()
		try await device.save(on: req.db)

		let deviceID = try device.requireID()
		try await pruneStaleDevices(
			for: payload.sub,
			keeping: deviceID,
			platform: body.platform,
			database: req.db,
			logger: req.logger
		)
		req.logger.info("Synchronized device", metadata: [
			"user_id": .string(payload.sub.uuidString),
			"device_id": .string(deviceID.uuidString),
			"installation_id": .string(body.installationID),
			"platform": .string(body.platform),
			"os_version": .string("\(body.osMajorVersion).\(body.osMinorVersion)"),
			"is_debug": .stringConvertible(body.isDebug),
			"is_beta": .stringConvertible(body.isBeta),
		])
		return UserDeviceResponse(
			installationID: device.installationID,
			platform: device.platform,
			isDebug: device.isDebug,
			lastSeenAt: device.lastSeenAt
		)
	}

	func removeDevice(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(RemoveUserDeviceRequest.self)
		guard body.platform == payload.platform, body.installationID == payload.installationID else {
			throw Abort(.forbidden)
		}
		guard !body.installationID.isEmpty, body.installationID.count <= 200 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The installation ID is invalid.", field: "installationID")
		}
		if let device = try await UserDevice.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.filter(\.$installationID == body.installationID)
			.first()
		{
			await SchoolDayActivityCoordinator().endActivities(for: device, database: req.db, logger: req.logger)
			try await device.delete(on: req.db)
		}
		req.logger.info("Removed device", metadata: [
			"user_id": .string(payload.sub.uuidString),
			"installation_id": .string(body.installationID),
			"platform": .string(body.platform),
		])
		return .noContent
	}

	private func pruneStaleDevices(for userID: UUID, keeping deviceID: UUID, platform: String, database: any Database, logger: Logger) async throws {
		let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
		let devices = try await UserDevice.query(on: database)
			.filter(\.$user.$id == userID)
			.filter(\.$platform == platform)
			.all()
		for device in devices where device.id != deviceID && device.lastSeenAt < cutoff {
			await SchoolDayActivityCoordinator().endActivities(for: device, database: database, logger: logger)
			try await device.delete(on: database)
			logger.info("Pruned stale device", metadata: [
				"user_id": .string(userID.uuidString),
				"device_id": .string(device.id?.uuidString ?? "unknown"),
				"platform": .string(platform),
			])
		}
	}

	func sendTestNotification(req: Request) async throws -> TestNotificationResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}
		let settings = try JSONDecoder().decode(AccountSettings.self, from: user.settingsData)
		guard settings.notificationsEnabled else {
			throw AppError(.conflict, code: .invalidRequest, reason: "Notifications are disabled.", field: "notificationsEnabled")
		}
		let count = try await NotificationService().send(
			title: "Timetable Notifications",
			body: "Notifications are configured for this device.",
			to: payload.sub,
			installationID: payload.installationID,
			on: req
		)
		return TestNotificationResponse(deliveredDeviceCount: count)
	}

	private func validate(_ body: RegisterUserDeviceRequest) throws {
		guard ["iOS", "iPadOS", "macOS", "watchOS"].contains(body.platform) else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The platform is invalid.", field: "platform")
		}

		guard !body.installationID.isEmpty, body.installationID.count <= 200 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The installation ID is invalid.", field: "installationID")
		}

		guard !body.apnsToken.isEmpty, body.apnsToken.count >= 32, body.apnsToken.count <= 200 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The APNS token is invalid.", field: "apnsToken")
		}
	}

	private func validate(_ body: SynchronizeUserDeviceRequest) throws {
		guard ["iOS", "iPadOS", "macOS", "watchOS"].contains(body.platform) else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The platform is invalid.", field: "platform")
		}

		guard !body.installationID.isEmpty, body.installationID.count <= 200 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The installation ID is invalid.", field: "installationID")
		}

		guard (1 ... 999).contains(body.osMajorVersion) else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The operating system major version is invalid.", field: "osMajorVersion")
		}

		guard (0 ... 999).contains(body.osMinorVersion) else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The operating system minor version is invalid.", field: "osMinorVersion")
		}
	}
}
