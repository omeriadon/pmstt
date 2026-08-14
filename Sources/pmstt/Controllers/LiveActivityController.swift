import Fluent
import Vapor

struct LiveActivityController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let protected = routes
			.grouped("v1")
			.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())

		protected.put("devices", "current", "live-activity-token", use: registerPushToStartToken)
		protected.delete("devices", "current", "live-activity-token", use: removePushToStartToken)
		protected.put("live-activities", ":activityKey", "update-token", use: registerUpdateToken)
		protected.post("live-activities", "current", "reconcile", use: reconcileCurrentActivity)
		protected.get("live-activities", "debug", use: debugState)
		protected.post("live-activities", "debug", "start", use: startDebugActivity)
		protected.post("live-activities", "debug", "update", use: updateDebugActivity)
		protected.post("live-activities", "debug", "stop", use: stopDebugActivity)
	}

	func registerPushToStartToken(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(LiveActivityPushToStartTokenRequest.self)
		try validate(installationID: body.installationID, token: body.token)

		let device = try await UserDevice.query(on: req.db)
			.filter(\.$user.$id == payload.sub)
			.filter(\.$installationID == body.installationID)
			.first() ?? UserDevice(userID: payload.sub, installationID: body.installationID, platform: "iOS")
		device.$user.id = payload.sub
		device.platform = "iOS"
		device.isDebug = body.isDebug
		device.liveActivityPushToStartToken = body.token
		device.lastSeenAt = Date()
		try await device.save(on: req.db)
		let deviceID = try device.requireID()
		req.logger.info("Registered Live Activity push-to-start token", metadata: [
			"user_id": .string(payload.sub.uuidString),
			"device_id": .string(deviceID.uuidString),
			"installation_id": .string(body.installationID),
		])
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
			let deviceID = try device.requireID()
			req.logger.info("Removed Live Activity push-to-start token", metadata: [
				"user_id": .string(payload.sub.uuidString),
				"device_id": .string(deviceID.uuidString),
			])
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
		let deviceID = try device.requireID()
		req.logger.info("Registered Live Activity update token", metadata: [
			"user_id": .string(payload.sub.uuidString),
			"device_id": .string(deviceID.uuidString),
			"activity_key": .string(activity.activityKey),
		])
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
			localActivityKeys: body.activeActivityKeys.map(Set.init),
			at: Date(),
			database: req.db,
			logger: req.logger
		)
		let deviceID = try device.requireID()
		req.logger.info("Reconciled current Live Activity", metadata: [
			"user_id": .string(payload.sub.uuidString),
			"device_id": .string(deviceID.uuidString),
			"started": .stringConvertible(started),
		])
		return ReconcileLiveActivityResponse(started: started)
	}

	private func debugState(req: Request) async throws -> LiveActivityDebugStateResponse {
		let user = try await requireSystemOwner(req)
		guard let installationID = req.query[String.self, at: "installationID"] else {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The installation ID is required.", field: "installationID")
		}
		try validateInstallationID(installationID)
		guard let device = try await device(userID: user.requireID(), installationID: installationID, database: req.db) else {
			return LiveActivityDebugStateResponse(isActive: false, canUpdate: false)
		}

		return try await debugState(for: device, database: req.db)
	}

	private func startDebugActivity(req: Request) async throws -> LiveActivityDebugStateResponse {
		let user = try await requireSystemOwner(req)
		let body = try req.content.decode(LiveActivityDebugRequest.self)
		try validateInstallationID(body.installationID)
		guard let device = try await device(userID: user.requireID(), installationID: body.installationID, database: req.db) else {
			throw AppError(.notFound, code: .notFound, reason: "Device not found.")
		}
		guard try await activeDebugActivity(for: device, database: req.db) == nil else {
			return try await debugState(for: device, database: req.db)
		}
		guard let token = device.liveActivityPushToStartToken,
		      let timetable = try await OwnerTimetable.query(on: req.db).filter(\.$user.$id == user.requireID()).first()
		else {
			throw AppError(.notFound, code: .notFound, reason: "A Live Activity push-to-start token and timetable are required.")
		}

		let now = Date()
		let dayIndex = SchoolCalendar.configured.dayIndex(for: now) ?? 0
		let subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: timetable.subjectsData)
		let projection = SchoolDayActivityProjector().debugProjection(
			for: .morning,
			on: now,
			dayIndex: dayIndex,
			subjects: subjects
		)
		let activity = try SchoolDayLiveActivity(
			userDeviceID: device.requireID(),
			activityKey: UUID().uuidString,
			schoolDate: "debug-\(UUID().uuidString)",
			currentTransition: SchoolDayTransition.morning.rawValue,
			isDebug: true
		)
		try await activity.create(on: req.db)

		do {
			let result = try await LiveActivityAPNSService().sendStart(
				to: token,
				isDebug: device.isDebug,
				attributes: SchoolDayActivityAttributesPayload(
					activityKey: activity.activityKey,
					schoolDate: activity.schoolDate,
					isDebug: true
				),
				projection: projection,
				logger: req.logger
			)
			guard result.succeeded else {
				try await activity.delete(on: req.db)
				if result.permanentlyInvalidToken {
					device.liveActivityPushToStartToken = nil
					try await device.save(on: req.db)
				}
				throw AppError(.badGateway, code: .internalServerError, reason: "APNs did not start the Live Activity.")
			}
		} catch {
			try? await activity.delete(on: req.db)
			throw error
		}

		activity.lastAPNSTimestamp = now
		try await activity.save(on: req.db)
		return LiveActivityDebugStateResponse(isActive: true, canUpdate: false)
	}

	private func updateDebugActivity(req: Request) async throws -> LiveActivityDebugStateResponse {
		let user = try await requireSystemOwner(req)
		let body = try req.content.decode(LiveActivityDebugUpdateRequest.self)
		try validateInstallationID(body.installationID)
		guard let transition = SchoolDayTransition(rawValue: body.transition),
		      [.morning, .period1, .recess, .lunch, .period6, .finished].contains(transition),
		      let device = try await device(userID: user.requireID(), installationID: body.installationID, database: req.db),
		      let activity = try await activeDebugActivity(for: device, database: req.db),
		      let token = activity.updateToken,
		      let timetable = try await OwnerTimetable.query(on: req.db).filter(\.$user.$id == user.requireID()).first()
		else {
			throw AppError(.notFound, code: .notFound, reason: "An active Live Activity with an update token is required.")
		}

		let now = Date()
		let dayIndex = SchoolCalendar.configured.dayIndex(for: now) ?? 0
		let subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: timetable.subjectsData)
		let projection = SchoolDayActivityProjector().debugProjection(
			for: transition,
			on: now,
			dayIndex: dayIndex,
			subjects: subjects
		)
		let result = try await LiveActivityAPNSService().sendUpdate(
			to: token,
			activityKey: activity.activityKey,
			isDebug: device.isDebug,
			projection: projection,
			logger: req.logger
		)
		guard result.succeeded else {
			if result.permanentlyInvalidToken {
				activity.updateToken = nil
				try await activity.save(on: req.db)
			}
			throw AppError(.badGateway, code: .internalServerError, reason: "APNs did not update the Live Activity.")
		}

		activity.currentTransition = transition.rawValue
		activity.lastAPNSTimestamp = now
		try await activity.save(on: req.db)
		return LiveActivityDebugStateResponse(isActive: true, canUpdate: true)
	}

	private func stopDebugActivity(req: Request) async throws -> LiveActivityDebugStateResponse {
		let user = try await requireSystemOwner(req)
		let body = try req.content.decode(LiveActivityDebugRequest.self)
		try validateInstallationID(body.installationID)
		guard let device = try await device(userID: user.requireID(), installationID: body.installationID, database: req.db) else {
			throw AppError(.notFound, code: .notFound, reason: "Device not found.")
		}
		guard let activity = try await activeDebugActivity(for: device, database: req.db) else {
			return LiveActivityDebugStateResponse(isActive: false, canUpdate: false)
		}

		let now = Date()
		if let token = activity.updateToken {
			let projection = SchoolDayActivityProjector().projection(for: .finished, on: now, dayIndex: 0, subjects: [])
			let result = try await LiveActivityAPNSService().sendEnd(
				to: token,
				activityKey: activity.activityKey,
				isDebug: device.isDebug,
				projection: projection,
				logger: req.logger
			)
			guard result.succeeded || result.permanentlyInvalidToken else {
				throw AppError(.badGateway, code: .internalServerError, reason: "APNs did not stop the Live Activity.")
			}
			if result.permanentlyInvalidToken {
				activity.updateToken = nil
			}
		}

		activity.status = .ended
		activity.currentTransition = SchoolDayTransition.finished.rawValue
		activity.lastAPNSTimestamp = now
		try await activity.save(on: req.db)
		return LiveActivityDebugStateResponse(isActive: false, canUpdate: false)
	}

	private func device(userID: UUID, installationID: String, database: any Database) async throws -> UserDevice? {
		try await UserDevice.query(on: database)
			.filter(\.$user.$id == userID)
			.filter(\.$installationID == installationID)
			.first()
	}

	private func activeDebugActivity(for device: UserDevice, database: any Database) async throws -> SchoolDayLiveActivity? {
		try await SchoolDayLiveActivity.query(on: database)
			.filter(\.$userDevice.$id == device.requireID())
			.filter(\.$status == .active)
			.filter(\.$isDebug == true)
			.sort(\.$createdAt, .descending)
			.first()
	}

	private func debugState(for device: UserDevice, database: any Database) async throws -> LiveActivityDebugStateResponse {
		guard let activity = try await activeDebugActivity(for: device, database: database) else {
			return LiveActivityDebugStateResponse(isActive: false, canUpdate: false)
		}

		return LiveActivityDebugStateResponse(isActive: true, canUpdate: activity.updateToken != nil)
	}

	private func requireSystemOwner(_ req: Request) async throws -> User {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw Abort(.notFound)
		}
		guard user.resolvedAccountAuthority == .systemOwner else {
			throw Abort(.forbidden)
		}
		return user
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
