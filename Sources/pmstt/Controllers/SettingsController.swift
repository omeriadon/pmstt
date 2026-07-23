import Fluent
import Vapor

struct SettingsController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let settings = routes.grouped("v1", "settings")
		let protected = settings.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())

		protected.get(use: getSettings)
		protected.put(use: updateSettings)
		protected.put("notifications", use: updateNotificationSettings)
	}

	func getSettings(req: Request) async throws -> AccountSettings {
		let user = try await authenticatedUser(req)
		return try decodeSettings(for: user)
	}

	func updateSettings(req: Request) async throws -> AccountSettings {
		let settings = try req.content.decode(UpdateSettingsRequest.self)
		try validate(settings)

		let user = try await authenticatedUser(req)
		let previousSettings = try decodeSettings(for: user)
		user.settingsData = try JSONEncoder().encode(settings.accountSettings)
		try await user.save(on: req.db)
		if previousSettings.liveActivitiesEnabled, !settings.liveActivitiesEnabled {
			try await SchoolDayActivityCoordinator().endActivities(forUserID: user.requireID(), database: req.db, logger: req.logger)
			try await UserDevice.query(on: req.db)
				.filter(\.$user.$id == user.requireID())
				.set(\.$liveActivityPushToStartToken, to: nil)
				.update()
		}
		return try decodeSettings(for: user)
	}

	func updateNotificationSettings(req: Request) async throws -> AccountSettings {
		let update = try req.content.decode(NotificationSettingsUpdateRequest.self)
		let user = try await authenticatedUser(req)
		var settings = try decodeSettings(for: user)
		settings.notificationsEnabled = update.notificationsEnabled
		settings.broadcastNotificationsEnabled = update.broadcastNotificationsEnabled
		settings.notificationLeadTimes = update.notificationLeadTimes
		user.settingsData = try JSONEncoder().encode(settings)
		try await user.save(on: req.db)
		return settings
	}

	private func authenticatedUser(_ req: Request) async throws -> User {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}
		return user
	}

	private func decodeSettings(for user: User) throws -> AccountSettings {
		do {
			return try JSONDecoder().decode(AccountSettings.self, from: user.settingsData)
		} catch {
			throw AppError(
				.internalServerError,
				code: .internalServerError,
				reason: "Stored account settings are invalid."
			)
		}
	}

	private func validate(_ settings: UpdateSettingsRequest) throws {
		_ = settings
	}
}
