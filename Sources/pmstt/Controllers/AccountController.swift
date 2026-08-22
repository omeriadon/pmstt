import Fluent
import Vapor

struct AccountController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let account = routes.grouped("v1", "account")
		let protected = account.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())

		protected.get(use: getAccount)
		protected.put(use: updateAccount)
		protected.delete(use: deleteAccount)
		protected.get("status", use: currentLocationStatus)
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
			let normalizedAddress = try normalizedEmail(email)
			try await ServerAccessModeService.requirePermittedEmail(normalizedAddress, on: req.db)
			if normalizedAddress != user.email {
				let existing = try await User.query(on: req.db)
					.filter(\.$email == normalizedAddress)
					.first()
				if existing != nil {
					throw AppError(.conflict, code: .emailAlreadyExists, reason: "Email is already registered.", field: "email")
				}
				user.email = normalizedAddress
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
		if history.last?.state == request.state {
			history[history.index(before: history.endIndex)] = LocationStatusItem(
				state: request.state,
				updatedAt: request.updatedAt
			)
			try user.setLocationStatusHistory(history)
			try await user.update(on: req.db)
			return .noContent
		}

		history.append(LocationStatusItem(state: request.state, updatedAt: request.updatedAt))
		try user.setLocationStatusHistory(history)
		try await user.update(on: req.db)
		await notifyFriendLocationObservers(
			for: user,
			status: request.state,
			updatedAt: request.updatedAt,
			on: req
		)
		return .noContent
	}

	private func notifyFriendLocationObservers(
		for watchedUser: User,
		status: LocationStatus,
		updatedAt: Date,
		on req: Request
	) async {
		guard let watchedUserID = watchedUser.id,
		      let preference = LocationNotificationPreference(for: status)
		else {
			return
		}

		do {
			let relationships = try await Friendship.query(on: req.db)
				.group(.or) { group in
					group.filter(\.$requester.$id == watchedUserID)
					group.filter(\.$recipient.$id == watchedUserID)
				}
				.filter(\.$status == .accepted)
				.with(\.$requester)
				.with(\.$recipient)
				.all()

			for relationship in relationships {
				let observerID = relationship.$requester.id == watchedUserID
					? relationship.$recipient.id
					: relationship.$requester.id
				let preferences = try relationship.locationNotificationPreferences(for: observerID)
				guard preferences.contains(preference),
				      let relationshipID = relationship.id
				else {
					continue
				}

				do {
					_ = try await NotificationService().send(
						title: "Friend location",
						body: "\(watchedUser.displayName) is \(preference.notificationDescription).",
						threadID: "friend-location-\(watchedUserID.uuidString)",
						collapseID: "friend-location-\(relationshipID.uuidString)-\(preference.rawValue)-\(Int(updatedAt.timeIntervalSince1970))",
						to: observerID,
						on: req,
						notificationType: "friend-location"
					)
				} catch {
					req.logger.error("Friend location notification delivery failed", metadata: [
						"observer_id": .string(observerID.uuidString),
						"watched_user_id": .string(watchedUserID.uuidString),
						"error": .string(error.localizedDescription),
					])
				}
			}
		} catch {
			req.logger.error("Friend location observer lookup failed", metadata: [
				"watched_user_id": .string(watchedUserID.uuidString),
				"error": .string(error.localizedDescription),
			])
		}
	}

	func currentLocationStatus(req: Request) async throws -> LocationStatusCurrentResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}

		return try LocationStatusCurrentResponse(item: user.locationStatusHistory().last)
	}

	func locationStatusStatistics(req: Request) async throws -> LocationArrivalStatisticsResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}

		let history = try user.locationStatusHistory()
		let statistics = LocationStatusStatisticsService()
		return LocationArrivalStatisticsResponse(
			averageArrivalSecondsSinceMidnight: statistics.averageArrival(
				for: [history]
			),
			weekdayAverageArrivalSecondsSinceMidnight: statistics.averageArrivalBySchoolDay(
				for: history
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

private extension LocationNotificationPreference {
	init?(for status: LocationStatus) {
		switch status {
			case .withinTenMinutes:
				self = .withinTenMinutes
			case .withinFiveMinutes:
				self = .withinFiveMinutes
			case .onCampus:
				self = .arrived
			case .offCampus:
				return nil
		}
	}

	var notificationDescription: String {
		switch self {
			case .withinTenMinutes:
				"within 10 minutes of school"
			case .withinFiveMinutes:
				"within 5 minutes of school"
			case .arrived:
				"at school"
		}
	}
}
