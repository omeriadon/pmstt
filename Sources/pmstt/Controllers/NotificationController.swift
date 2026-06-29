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
		device.lastSeenAt = Date()
		try await device.save(on: req.db)
		return UserDeviceResponse(
			installationID: device.installationID,
			platform: device.platform,
			lastSeenAt: device.lastSeenAt
		)
	}

	func removeDevice(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		let installationID = try req.query.get(String.self, at: "installationID")
		try await UserDevice.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.filter(\.$installationID == installationID)
			.delete()
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

	private func validate(_ body: RegisterUserDeviceRequest) throws {
		guard !body.installationID.isEmpty, body.installationID.count <= 200,
		      ["iOS", "macOS", "visionOS"].contains(body.platform),
		      body.apnsToken.count >= 32, body.apnsToken.count <= 200,
		      body.apnsToken.allSatisfy(\.isHexDigit)
		else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The device registration is invalid.", field: "device")
		}
	}
}
