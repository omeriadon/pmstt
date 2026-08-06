import Fluent
import Vapor

struct AccountController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let account = routes.grouped("v1", "account")
		let protected = account.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())

		protected.get(use: getAccount)
		protected.put(use: updateAccount)
		protected.delete(use: deleteAccount)
		protected.post("status", use: updateLocationStatus)
		protected.get("status", "statistics", use: locationStatusStatistics)
	}

	func getAccount(req: Request) async throws -> UserAccountResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}

		return try await UserAccountResponse(user: user, on: req.db)
	}

	func updateAccount(req: Request) async throws -> UserAccountResponse {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(UpdateAccountRequest.self)

		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}
		try requireMatchingRevision(body.baseRevision, for: user)

		var didChangeProfile = false
		if let displayName = body.displayName, !displayName.isEmpty {
			didChangeProfile = displayName != user.displayName
			user.displayName = displayName
		}

		if let email = body.email {
			let normalizedEmail = try normalizedSchoolEmail(email)
			try await ServerAccessModeService.requirePermittedEmail(normalizedEmail, on: req.db)
			if normalizedEmail != user.email {
				let existing = try await User.query(on: req.db)
					.filter(\.$email == normalizedEmail)
					.first()
				if existing != nil {
					throw AppError(.conflict, code: .emailAlreadyExists, reason: "Email is already registered.", field: "email")
				}
				user.email = normalizedEmail
				didChangeProfile = true
			}
		}

		if didChangeProfile {
			user.profileRevision += 1
		}
		try await user.save(on: req.db)

		return try await UserAccountResponse(user: user, on: req.db)
	}

	func deleteAccount(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}

		await SchoolDayActivityCoordinator().endActivities(forUserID: payload.sub, database: req.db, logger: req.logger)
		try await user.delete(on: req.db)
		return .noContent
	}

	func updateLocationStatus(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		guard payload.platformValue == .iOS else {
			throw Abort(.forbidden)
		}
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}

		let request = try req.content.decode(LocationStatusUpdateRequest.self)
		var history = try user.locationStatusHistory()
		guard history.last?.state != request.state else {
			return .noContent
		}

		history.append(LocationStatusItem(state: request.state, updatedAt: request.updatedAt))
		try user.setLocationStatusHistory(history)
		try await user.update(on: req.db)
		return .noContent
	}

	func locationStatusStatistics(req: Request) async throws -> LocationArrivalStatisticsResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}

		return try LocationArrivalStatisticsResponse(
			averageArrivalSecondsSinceMidnight: LocationStatusStatisticsService().averageArrival(
				for: [user.locationStatusHistory()]
			)
		)
	}

	private func requireMatchingRevision(
		_ baseRevision: Int?,
		for user: User
	) throws {
		guard let baseRevision else {
			return
		}
		guard baseRevision == user.profileRevision else {
			throw Abort(
				.conflict,
				reason: "The account profile has changed on the server."
			)
		}
	}
}
