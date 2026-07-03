import Fluent
import Vapor

struct NotificationController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let protected = routes
			.grouped("v1")
			.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())

		protected.put("devices", "current", use: registerDevice)
		protected.delete("devices", "current", use: removeDevice)
		protected.post("notifications", "test", use: sendTestNotification)
		routes.post("v1", "developer", "broadcast-notification", use: sendBroadcastNotification)
	}

	func registerDevice(req: Request) async throws -> UserDeviceResponse {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(RegisterUserDeviceRequest.self)
		try validate(body)
		let device = try await UserDevice.query(on: req.db)
			.filter(\.$installationID == body.installationID)
			.first() ?? UserDevice(userID: payload.sub, installationID: body.installationID, platform: body.platform)

		device.$user.id = payload.sub
		device.platform = body.platform
		device.apnsToken = body.apnsToken
		device.isDebug = body.isDebug
		device.lastSeenAt = Date()
		try await device.save(on: req.db)
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
		return .noContent
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
			on: req
		)
		return TestNotificationResponse(deliveredDeviceCount: count)
	}

	func sendBroadcastNotification(req: Request) async throws -> BroadcastNotificationResponse {
		let body = try req.content.decode(BroadcastNotificationRequest.self)
		let title = body.title.trimmingCharacters(in: .whitespacesAndNewlines)
		let subtitle = body.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
		let message = body.body.trimmingCharacters(in: .whitespacesAndNewlines)
		try validateBroadcast(title: title, subtitle: subtitle, body: message)
		return try await NotificationService().broadcast(title: title, subtitle: subtitle, body: message, on: req)
	}

	private func validate(_ body: RegisterUserDeviceRequest) throws {
		guard ["iOS", "macOS", "watchOS"].contains(body.platform) else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The platform is invalid.", field: "platform")
		}

		guard !body.installationID.isEmpty, body.installationID.count <= 200 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The installation ID is invalid.", field: "installationID")
		}

		guard !body.apnsToken.isEmpty, body.apnsToken.count >= 32, body.apnsToken.count <= 200 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The APNS token is invalid.", field: "apnsToken")
		}
	}

	private func validateBroadcast(title: String, subtitle: String, body: String) throws {
		guard !title.isEmpty, title.count <= 200 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The broadcast title is invalid.", field: "title")
		}
		guard !subtitle.isEmpty, subtitle.count <= 200 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The broadcast subtitle is invalid.", field: "subtitle")
		}
		guard !body.isEmpty, body.count <= 2_000 else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The broadcast body is invalid.", field: "body")
		}
	}
}
