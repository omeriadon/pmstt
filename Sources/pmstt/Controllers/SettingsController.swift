import Fluent
import Vapor

struct SettingsController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let settings = routes.grouped("v1", "settings")
		let protected = settings.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())

		protected.get(use: getSettings)
		protected.put(use: updateSettings)
	}

	func getSettings(req: Request) async throws -> AccountSettings {
		let user = try await authenticatedUser(req)
		return try decodeSettings(for: user)
	}

	func updateSettings(req: Request) async throws -> AccountSettings {
		let settings = try req.content.decode(AccountSettings.self)
		try validate(settings)

		let user = try await authenticatedUser(req)
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

	private func validate(_ settings: AccountSettings) throws {
		let start = settings.liveActivityStartTime
		let end = settings.liveActivityEndTime
		guard isValid(start), isValid(end) else {
			throw invalidSettings("Live Activity times are invalid.")
		}

		let startMinutes = start.hour * 60 + start.minute
		let endMinutes = end.hour * 60 + end.minute
		guard startMinutes < endMinutes else {
			throw invalidSettings("The Live Activity end time must be after its start time.")
		}

		guard !settings.liveActivityWeekdays.isEmpty else {
			throw invalidSettings("At least one Live Activity weekday is required.")
		}
	}

	private func isValid(_ time: TimeOfDay) -> Bool {
		(0 ... 23).contains(time.hour) && (0 ... 59).contains(time.minute)
	}

	private func invalidSettings(_ reason: String) -> AppError {
		AppError(.badRequest, code: .invalidRequest, reason: reason, field: "accountSettings")
	}
}
