import Fluent
import Vapor

struct SettingsController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let settings = routes.grouped("v1", "settings")
		let protected = settings.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())

		protected.get(use: getSettings)
		protected.get("calendar", use: getSchoolCalendar)
		protected.put(use: updateSettings)
		protected.put("notifications", use: updateNotificationSettings)
	}

	func getSettings(req: Request) async throws -> AccountSettings {
		let user = try await authenticatedUser(req)
		return try decodeSettings(for: user)
	}

	func getSchoolCalendar(req: Request) async throws -> SchoolCalendarResponse {
		try await SchoolCalendar.response(on: req.db)
	}

	func updateSettings(req: Request) async throws -> AccountSettings {
		let settings = try req.content.decode(UpdateSettingsRequest.self)
		try validate(settings)

		let user = try await authenticatedUser(req)
		try requireMatchingRevision(settings.serverRevision, for: user)
		let previousSettings = try decodeSettings(for: user)
		user.settingsRevision += 1
		var updatedSettings = settings.accountSettings
		updatedSettings.serverRevision = user.settingsRevision
		user.settingsData = try JSONEncoder().encode(updatedSettings)
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
		try requireMatchingRevision(update.serverRevision, for: user)
		var settings = try decodeSettings(for: user)
		settings.notificationsEnabled = update.notificationsEnabled
		settings.broadcastNotificationsEnabled = update.broadcastNotificationsEnabled
		settings.notificationLeadTimes = update.notificationLeadTimes
		settings.breakToPeriodNotificationLeadTimes = update.breakToPeriodNotificationLeadTimes
		settings.eventNotificationSchedules = update.eventNotificationSchedules
		user.settingsRevision += 1
		settings.serverRevision = user.settingsRevision
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
			var settings = try JSONDecoder().decode(
				AccountSettings.self,
				from: user.settingsData
			)
			settings.serverRevision = user.settingsRevision
			return settings
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

	private func requireMatchingRevision(
		_ baseRevision: Int?,
		for user: User
	) throws {
		guard let baseRevision else {
			return
		}
		guard baseRevision == user.settingsRevision else {
			throw Abort(
				.conflict,
				reason: "Account settings have changed on the server."
			)
		}
	}
}
