import Fluent
import Vapor

struct AdministrationController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let admin = routes.grouped("v1", "administration").grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		admin.get(use: dashboard)
		admin.get("statistics", use: locationStatusStatistics)
		admin.get("friends-since-requests", use: friendshipDateChangeRequests)
		admin.put("friends-since-requests", ":requestID", use: resolveFriendshipDateChangeRequest)
		admin.get("user-reports", use: userReports)
		admin.put("user-reports", ":reportID", use: resolveUserReport)
		admin.get("users", use: users)
		admin.get("users", ":userID", use: userDetail)
		admin.post("users", use: createUser)
		admin.put("users", ":userID", use: updateUser)
		admin.delete("users", ":userID", use: deleteUser)
		admin.put("users", ":userID", "authority", use: updateAuthority)
		admin.post("broadcast-notification", use: broadcastNotification)
		admin.get("broadcast-notifications", use: broadcastNotifications)
		admin.delete("broadcast-notifications", ":notificationID", use: deleteBroadcastNotification)
		admin.get("profile-storage-quota", use: profileStorageQuota)
		admin.get("app-version", use: appVersionRequirement)
		admin.put("app-version", use: updateAppVersionRequirement)
		admin.post("test-email", use: sendTestEmail)
		admin.get("email-log", use: emailLog)
		admin.get("badges", use: specialBadges)
		admin.post("badges", use: createSpecialBadge)
		admin.put("badges", "order", use: reorderSpecialBadges)
		admin.put("badges", ":badgeID", use: updateSpecialBadge)
		admin.delete("badges", ":badgeID", use: deleteSpecialBadge)
		admin.put("badges", ":badgeID", "users", use: replaceSpecialBadgeUsers)
		admin.get("event-tags", use: eventTags)
		admin.post("event-tags", use: createEventTag)
		admin.put("event-tags", "order", use: reorderEventTags)
		admin.put("event-tags", ":tagID", use: updateEventTag)
		admin.delete("event-tags", ":tagID", use: deleteEventTag)
		admin.post("event-tags", "sections", use: createEventTagSection)
		admin.put("event-tags", "sections", ":sectionID", use: updateEventTagSection)
		admin.get("calendar", use: calendar)
		admin.post("calendar", use: createCalendarEntry)
		admin.put("calendar", ":entryID", use: updateCalendarEntry)
		admin.delete("calendar", ":entryID", use: deleteCalendarEntry)
	}

	private func profileStorageQuota(req: Request) async throws -> ProfileStorageQuotaSnapshot {
		_ = try await requireAdministrator(req)
		let configuration = try ProfileStorageConfiguration.load()
		return try await ProfileStorageQuotaService(configuration: configuration).snapshot(on: req.db)
	}

	private func sendTestEmail(req: Request) async throws -> HTTPStatus {
		_ = try await requireSystemOwner(req)
		try await sendAdministrationTestEmail(on: req.db)
		return .noContent
	}

	private func emailLog(req: Request) async throws -> [AdministrationEmailDeliveryRecordResponse] {
		_ = try await requireAdministrator(req)
		return try await EmailDeliveryRecord.query(on: req.db)
			.sort(\.$createdAt, .descending)
			.limit(500)
			.all()
			.map(AdministrationEmailDeliveryRecordResponse.init)
	}

	private func appVersionRequirement(req: Request) async throws -> AppVersionRequirementResponse {
		_ = try await requireSystemOwner(req)
		let requirement = try await AppVersionRequirementService.current(on: req.db)
		return AppVersionRequirementResponse(requirement)
	}

	private func updateAppVersionRequirement(req: Request) async throws -> AppVersionRequirementResponse {
		_ = try await requireSystemOwner(req)
		let update = try req.content.decode(AppVersionRequirementUpdateRequest.self)
		guard Self.isValidVersion(update.appVersion),
		      Self.isValidVersion(update.macVersion),
		      update.appBuild >= 0,
		      update.macBuild >= 0
		else {
			throw Abort(.badRequest, reason: "Versions must use the xx.xx.xx format and builds cannot be negative.")
		}

		let requirement = try await AppVersionRequirementService.current(on: req.db)
		requirement.appVersion = update.appVersion
		requirement.appBuild = update.appBuild
		requirement.macVersion = update.macVersion
		requirement.macBuild = update.macBuild
		try await requirement.update(on: req.db)
		return AppVersionRequirementResponse(requirement)
	}

	private static func isValidVersion(_ value: String) -> Bool {
		let components = value.split(separator: ".", omittingEmptySubsequences: false)
		return components.count == 3 && components.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
	}

	private func specialBadges(req: Request) async throws -> [AdministrationSpecialBadgeResponse] {
		_ = try await requireSystemOwner(req)
		return try await SpecialProfileBadge.query(on: req.db)
			.sort(\.$priority, .descending)
			.sort(\.$accessibilityLabel)
			.all()
			.asyncMap { try await AdministrationSpecialBadgeResponse($0, on: req.db) }
	}

	private func reorderSpecialBadges(req: Request) async throws -> [AdministrationSpecialBadgeResponse] {
		_ = try await requireSystemOwner(req)
		let request = try req.content.decode(AdministrationSpecialBadgeOrderRequest.self)
		guard Set(request.badgeIDs).count == request.badgeIDs.count else {
			throw Abort(.badRequest)
		}

		let badges = try await SpecialProfileBadge.query(on: req.db).all()
		let badgeByID = Dictionary(uniqueKeysWithValues: badges.compactMap { badge in
			badge.id.map { ($0, badge) }
		})
		guard Set(request.badgeIDs) == Set(badgeByID.keys) else {
			throw Abort(.badRequest)
		}

		try await req.db.transaction { database in
			for (index, badgeID) in request.badgeIDs.enumerated() {
				guard let badge = badgeByID[badgeID] else {
					throw Abort(.badRequest)
				}
				badge.priority = request.badgeIDs.count - index
				try await badge.update(on: database)
			}
		}

		return try await specialBadges(req: req)
	}

	private func createSpecialBadge(req: Request) async throws -> AdministrationSpecialBadgeResponse {
		_ = try await requireSystemOwner(req)
		let request = try req.content.decode(AdministrationSpecialBadgeRequest.self)
		let values = try validatedSpecialBadge(request)
		let badge = try SpecialProfileBadge(
			symbol: values.symbol,
			backgroundColorData: encodeColor(values.backgroundColor),
			symbolColorData: encodeColor(values.symbolColor),
			priority: values.priority,
			accessibilityLabel: values.accessibilityLabel
		)
		try await badge.create(on: req.db)
		return try await AdministrationSpecialBadgeResponse(badge, on: req.db)
	}

	private func updateSpecialBadge(req: Request) async throws -> AdministrationSpecialBadgeResponse {
		_ = try await requireSystemOwner(req)
		guard let badgeID = req.parameters.get("badgeID", as: UUID.self),
		      let badge = try await SpecialProfileBadge.find(badgeID, on: req.db)
		else {
			throw Abort(.notFound)
		}

		let request = try req.content.decode(AdministrationSpecialBadgeRequest.self)
		let values = try validatedSpecialBadge(request)
		badge.symbol = values.symbol
		badge.backgroundColorData = try encodeColor(values.backgroundColor)
		badge.symbolColorData = try encodeColor(values.symbolColor)
		badge.priority = values.priority
		badge.accessibilityLabel = values.accessibilityLabel
		try await badge.update(on: req.db)
		return try await AdministrationSpecialBadgeResponse(badge, on: req.db)
	}

	private func deleteSpecialBadge(req: Request) async throws -> HTTPStatus {
		_ = try await requireSystemOwner(req)
		guard let badgeID = req.parameters.get("badgeID", as: UUID.self),
		      let badge = try await SpecialProfileBadge.find(badgeID, on: req.db)
		else {
			throw Abort(.notFound)
		}

		try await badge.delete(on: req.db)
		return .noContent
	}

	private func replaceSpecialBadgeUsers(req: Request) async throws -> AdministrationSpecialBadgeResponse {
		_ = try await requireSystemOwner(req)
		guard let badgeID = req.parameters.get("badgeID", as: UUID.self),
		      let badge = try await SpecialProfileBadge.find(badgeID, on: req.db)
		else {
			throw Abort(.notFound)
		}

		let request = try req.content.decode(AdministrationSpecialBadgeAssignmentsRequest.self)
		let requestedUserIDs = Set(request.userIDs)
		let existingUsers = try await User.query(on: req.db)
			.filter(\.$id ~~ requestedUserIDs)
			.all()
		guard existingUsers.count == requestedUserIDs.count else {
			throw Abort(.badRequest)
		}

		try await req.db.transaction { database in
			try await UserSpecialProfileBadge.query(on: database)
				.filter(\.$badge.$id == badgeID)
				.delete()

			for userID in requestedUserIDs {
				try await UserSpecialProfileBadge(userID: userID, badgeID: badgeID).create(on: database)
			}
		}

		return try await AdministrationSpecialBadgeResponse(badge, on: req.db)
	}

	private func dashboard(req: Request) async throws -> AdministrationDashboardResponse {
		let user = try await requireAdministrator(req)
		async let pendingFriendshipRequests = FriendshipDateChangeRequest.query(on: req.db)
			.filter(\.$action == .pending)
			.count()
		async let pendingReports = UserReport.query(on: req.db)
			.filter(\.$action == .pending)
			.count()
		let pendingCounts = try await (pendingFriendshipRequests, pendingReports)
		let pendingModerationCount = pendingCounts.0 + pendingCounts.1
		return AdministrationDashboardResponse(
			isAdmin: true,
			authority: user.resolvedAccountAuthority,
			pendingModerationCount: pendingModerationCount
		)
	}

	private func locationStatusStatistics(req: Request) async throws -> AdministrationStatisticsResponse {
		_ = try await requireAdministrator(req)
		let users = try await User.query(on: req.db).all()
		let histories = try users.map { try $0.locationStatusHistory() }
		let devices = try await UserDevice.query(on: req.db).filter(\.$platform != ClientPlatform.legacy.rawValue).all()
		let assessmentCounts = users.map { user in
			guard let data = user.gradeTrackerData,
			      let document = try? JSONDecoder().decode(GradeTrackerDocument.self, from: data)
			else {
				return 0
			}

			return document.assessments.count
		}
		let totalAssessments = assessmentCounts.reduce(0, +)
		let usersWithAssessments = assessmentCounts.filter { $0 > 0 }
		let usersWithLocationStatus = histories.filter { !$0.isEmpty }
		let totalLocationStatusUpdates = histories.reduce(0) { $0 + $1.count }
		let activeDeviceCutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
		async let usersWithOwnerTimetable = OwnerTimetable.query(on: req.db).count()
		async let totalDevices = UserDevice.query(on: req.db).count()
		async let activeDevicesLast30Days = UserDevice.query(on: req.db)
			.filter(\.$lastSeenAt >= activeDeviceCutoff)
			.count()
		async let debugDevices = UserDevice.query(on: req.db)
			.filter(\.$isDebug == true)
			.count()
		async let testFlightDevices = UserDevice.query(on: req.db)
			.filter(\.$isDebug == false)
			.filter(\.$isTestFlight == true)
			.count()
		async let releaseDevices = UserDevice.query(on: req.db)
			.filter(\.$isDebug == false)
			.filter(\.$isTestFlight == false)
			.count()
		async let iPhoneDevices = UserDevice.query(on: req.db)
			.filter(\.$platform == ClientPlatform.iOS.rawValue)
			.count()
		async let iPadDevices = UserDevice.query(on: req.db)
			.filter(\.$platform == ClientPlatform.iPadOS.rawValue)
			.count()
		async let macDevices = UserDevice.query(on: req.db)
			.filter(\.$platform == ClientPlatform.macOS.rawValue)
			.count()
		async let watchDevices = UserDevice.query(on: req.db)
			.filter(\.$platform == ClientPlatform.watchOS.rawValue)
			.count()
		async let legacyDevices = UserDevice.query(on: req.db)
			.filter(\.$platform == ClientPlatform.legacy.rawValue)
			.count()
		async let acceptedFriendshipModels = Friendship.query(on: req.db)
			.filter(\.$status == .accepted)
			.all()
		async let totalCalendarEvents = CalendarEvent.query(on: req.db).count()
		async let globalCalendarEvents = CalendarEvent.query(on: req.db)
			.filter(\.$isGlobal == true)
			.count()
		async let personalCalendarEvents = CalendarEvent.query(on: req.db)
			.filter(\.$isGlobal == false)
			.count()
		async let activeEventTagSubscriptions = AccountEventTagSubscription.query(on: req.db)
			.count()
		let counts = try await (
			usersWithOwnerTimetable,
			totalDevices,
			activeDevicesLast30Days,
			debugDevices,
			testFlightDevices,
			releaseDevices,
			iPhoneDevices,
			iPadDevices,
			macDevices,
			watchDevices,
			legacyDevices,
			acceptedFriendshipModels,
			totalCalendarEvents,
			globalCalendarEvents,
			personalCalendarEvents,
			activeEventTagSubscriptions
		)
		let friendshipParticipantIDs = Set(
			counts.11.flatMap { friendship in
				[friendship.$requester.id, friendship.$recipient.id]
			}
		)
		let totalFriendConnections = counts.11.count * 2

		return AdministrationStatisticsResponse(
			totalUsers: users.count,
			usersWithOwnerTimetable: counts.0,
			totalAssessments: totalAssessments,
			averageAssessmentsPerUser: average(
				total: totalAssessments,
				across: users.count
			),
			averageAssessmentsPerUserWithMultipleAssessments: average(
				total: usersWithAssessments.reduce(0, +),
				across: usersWithAssessments.count
			),
			totalDevices: counts.1,
			activeDevicesLast30Days: counts.2,
			debugDevices: counts.3,
			testFlightDevices: counts.4,
			releaseDevices: counts.5,
			iPhoneDevices: counts.6,
			iPadDevices: counts.7,
			macDevices: counts.8,
			watchDevices: counts.9,
			legacyDevices: counts.10,
			acceptedFriendships: counts.11.count,
			averageFriendsPerUser: average(
				total: totalFriendConnections,
				across: users.count
			),
			averageFriendsPerUserWithFriends: average(
				total: totalFriendConnections,
				across: friendshipParticipantIDs.count
			),
			totalCalendarEvents: counts.12,
			globalCalendarEvents: counts.13,
			personalCalendarEvents: counts.14,
			activeEventTagSubscriptions: counts.15,
			averageArrivalSecondsSinceMidnight: LocationStatusStatisticsService().averageArrival(for: histories),
			usersWithAssessments: usersWithAssessments.count,
			usersWithLocationStatus: usersWithLocationStatus.count,
			totalLocationStatusUpdates: totalLocationStatusUpdates,
			deviceTypes: deviceTypeCounts(devices),
			osVersions: osVersionCounts(devices),
			deviceOSVersions: deviceOSVersionCounts(devices),
			appVersions: appVersionCounts(devices),
			appVersionBuilds: appVersionBuildCounts(devices)
		)
	}

	private func appVersionCounts(_ devices: [UserDevice]) -> [AdministrationStatisticCount] {
		let counts = Dictionary(grouping: devices.compactMap(\.appVersion), by: { $0 })
			.mapValues { $0.count }

		return counts
			.map { AdministrationStatisticCount(label: $0.key, count: $0.value) }
			.sorted { $0.label.localizedStandardCompare($1.label) == .orderedDescending }
	}

	private func appVersionBuildCounts(_ devices: [UserDevice]) -> [AdministrationStatisticCount] {
		let labels = devices.compactMap { device -> String? in
			guard let version = device.appVersion, let build = device.appBuild else {
				return nil
			}

			return "\(version) (\(build))"
		}
		let counts = Dictionary(grouping: labels, by: { $0 }).mapValues { $0.count }

		return counts
			.map { AdministrationStatisticCount(label: $0.key, count: $0.value) }
			.sorted { $0.label.localizedStandardCompare($1.label) == .orderedDescending }
	}

	private func deviceTypeCounts(_ devices: [UserDevice]) -> [AdministrationStatisticCount] {
		let counts = Dictionary(grouping: devices, by: { deviceTypeLabel(for: $0) }).mapValues { $0.count }
		return counts
			.map { AdministrationStatisticCount(label: $0.key, count: $0.value) }
			.sorted { $0.count > $1.count }
	}

	private func osVersionCounts(_ devices: [UserDevice]) -> [AdministrationStatisticCount] {
		let counts = Dictionary(grouping: devices.compactMap { device -> DeviceOSVersionKey? in
			guard let major = device.osMajorVersion, let minor = device.osMinorVersion else { return nil }
			return DeviceOSVersionKey(
				platform: "",
				osMajorVersion: major,
				osMinorVersion: minor,
				isDebug: false,
				isOSBeta: false
			)
		}, by: { $0 }).mapValues { $0.count }
		return counts
			.map {
				AdministrationStatisticCount(
					label: "OS \($0.key.osMajorVersion).\($0.key.osMinorVersion)",
					count: $0.value
				)
			}
			.sorted { $0.label > $1.label }
	}

	private func deviceOSVersionCounts(_ devices: [UserDevice]) -> [AdministrationDeviceOSVersionCount] {
		let keys: [DeviceOSVersionKey] = devices.compactMap { device in
			guard let major = device.osMajorVersion, let minor = device.osMinorVersion else { return nil }
			return DeviceOSVersionKey(
				platform: device.platform,
				osMajorVersion: major,
				osMinorVersion: minor,
				isDebug: device.isDebug,
				isOSBeta: device.isOSBeta
			)
		}
		let grouped = Dictionary(grouping: keys, by: { $0 })
		return grouped.map { key, entries in
			AdministrationDeviceOSVersionCount(
				platform: deviceTypeLabel(for: key.platform),
				osMajorVersion: key.osMajorVersion,
				osMinorVersion: key.osMinorVersion,
				isDebug: key.isDebug,
				isOSBeta: key.isOSBeta,
				count: entries.count
			)
		}.sorted {
			if $0.platform == $1.platform {
				if $0.osMajorVersion == $1.osMajorVersion {
					if $0.osMinorVersion == $1.osMinorVersion {
						return !$0.isOSBeta && $1.isOSBeta
					}
					return $0.osMinorVersion > $1.osMinorVersion
				}
				return $0.osMajorVersion > $1.osMajorVersion
			}
			return $0.platform < $1.platform
		}
	}

	private func deviceTypeLabel(for device: UserDevice) -> String {
		deviceTypeLabel(for: device.platform)
	}

	private func deviceTypeLabel(for platform: String) -> String {
		switch platform {
			case ClientPlatform.iOS.rawValue: "iPhone"
			case ClientPlatform.iPadOS.rawValue: "iPad"
			case ClientPlatform.macOS.rawValue: "Mac"
			case ClientPlatform.watchOS.rawValue: "Apple Watch"
			default: platform
		}
	}

	private func average(total: Int, across count: Int) -> Double? {
		guard count > 0 else {
			return nil
		}

		return Double(total) / Double(count)
	}

	private func friendshipDateChangeRequests(req: Request) async throws -> [AdministrationFriendshipDateChangeRequestResponse] {
		_ = try await requireAdministrator(req)
		let requests = try await FriendshipDateChangeRequest.query(on: req.db)
			.sort(\.$createdAt, .descending)
			.all()
		return try await requests.asyncMap { request in
			try await friendshipDateChangeRequestResponse(request, on: req.db)
		}
	}

	private func resolveFriendshipDateChangeRequest(req: Request) async throws -> AdministrationFriendshipDateChangeRequestResponse {
		_ = try await requireAdministrator(req)
		guard let requestID = req.parameters.get("requestID", as: UUID.self),
		      let changeRequest = try await FriendshipDateChangeRequest.find(requestID, on: req.db)
		else {
			throw Abort(.notFound)
		}
		let resolution = try req.content.decode(AdministrationModerationResolutionRequest.self)
		guard resolution.action == .approved || resolution.action == .rejected else {
			throw Abort(.badRequest)
		}
		if resolution.action == .approved {
			guard let friendship = try await Friendship.find(changeRequest.friendshipID, on: req.db) else {
				throw Abort(.notFound)
			}
			friendship.acceptedAt = changeRequest.requestedDate
			try await friendship.update(on: req.db)
		}
		changeRequest.action = resolution.action
		try await changeRequest.update(on: req.db)
		return try await friendshipDateChangeRequestResponse(changeRequest, on: req.db)
	}

	private func friendshipDateChangeRequestResponse(
		_ request: FriendshipDateChangeRequest,
		on database: any Database
	) async throws -> AdministrationFriendshipDateChangeRequestResponse {
		let requester = try await User.find(request.requesterID, on: database)
		let friendship = try await Friendship.find(request.friendshipID, on: database)
		let friendID = friendship.map {
			$0.$requester.id == request.requesterID ? $0.$recipient.id : $0.$requester.id
		}
		let friend: User? = if let friendID {
			try await User.find(friendID, on: database)
		} else {
			nil
		}

		return try AdministrationFriendshipDateChangeRequestResponse(
			request,
			requesterDisplayName: requester?.displayName,
			friendID: friendID,
			friendDisplayName: friend?.displayName
		)
	}

	private func userReports(req: Request) async throws -> [AdministrationUserReportResponse] {
		_ = try await requireAdministrator(req)
		let reports = try await UserReport.query(on: req.db)
			.sort(\.$createdAt, .descending)
			.all()
		return try await reports.asyncMap { report in
			async let reporter = User.find(report.reporterID, on: req.db)
			async let reportedUser = User.find(report.reportedUserID, on: req.db)
			let users = try await (reporter, reportedUser)
			return try AdministrationUserReportResponse(
				report,
				reporterDisplayName: users.0?.displayName,
				reportedUserDisplayName: users.1?.displayName
			)
		}
	}

	private func resolveUserReport(req: Request) async throws -> AdministrationUserReportResponse {
		_ = try await requireAdministrator(req)
		guard let reportID = req.parameters.get("reportID", as: UUID.self),
		      let report = try await UserReport.find(reportID, on: req.db)
		else {
			throw Abort(.notFound)
		}
		let resolution = try req.content.decode(AdministrationModerationResolutionRequest.self)
		guard resolution.action == .noAction || resolution.action == .accountDeleted else {
			throw Abort(.badRequest)
		}
		if resolution.action == .accountDeleted,
		   let reportedUser = try await User.find(report.reportedUserID, on: req.db)
		{
			try preventChangingSystemOwner(reportedUser)
			report.action = resolution.action
			try await report.update(on: req.db)
			try await reportedUser.delete(on: req.db)
		} else {
			report.action = resolution.action
			try await report.update(on: req.db)
		}
		let reporter = try await User.find(report.reporterID, on: req.db)
		let reportedUser = try await User.find(report.reportedUserID, on: req.db)
		return try AdministrationUserReportResponse(
			report,
			reporterDisplayName: reporter?.displayName,
			reportedUserDisplayName: reportedUser?.displayName
		)
	}

	private func users(req: Request) async throws -> [AdministrationUserResponse] {
		_ = try await requireAdministrator(req)
		let users = try await User.query(on: req.db)
			.sort(\.$displayName)
			.all()
		var responses: [AdministrationUserResponse] = []
		responses.reserveCapacity(users.count)
		for user in users {
			try await responses.append(AdministrationUserResponse(user, on: req.db))
		}
		return responses
	}

	private func updateUser(req: Request) async throws -> AdministrationUserResponse {
		_ = try await requireAdministrator(req)
		guard let id = req.parameters.get("userID", as: UUID.self), let user = try await User.find(id, on: req.db) else { throw Abort(.notFound) }
		try preventChangingSystemOwner(user)
		let update = try req.content.decode(AdministrationUserUpdateRequest.self)
		let displayName = update.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !displayName.isEmpty else { throw Abort(.badRequest) }
		let email = try normalizedEmail(update.email)
		if email != user.email, try await User.query(on: req.db).filter(\.$email == email).first() != nil {
			throw Abort(.conflict)
		}
		user.displayName = displayName
		user.email = email
		if let password = update.password, !password.isEmpty {
			guard (8 ... 100).contains(password.count) else { throw Abort(.badRequest) }
			user.passwordHash = try req.password.hash(password)
		}
		try await user.update(on: req.db)
		return try await AdministrationUserResponse(user, on: req.db)
	}

	private func updateAuthority(req: Request) async throws -> AdministrationUserResponse {
		let systemOwner = try await requireSystemOwner(req)
		guard let id = req.parameters.get("userID", as: UUID.self), let user = try await User.find(id, on: req.db) else {
			throw Abort(.notFound)
		}

		let request = try req.content.decode(AdministrationUserAuthorityUpdateRequest.self)
		guard request.authority == .user || request.authority == .administrator else {
			throw Abort(.badRequest)
		}
		guard user.resolvedAccountAuthority != .systemOwner else {
			throw Abort(.forbidden)
		}
		guard systemOwner.resolvedAccountAuthority == .systemOwner else {
			throw Abort(.forbidden)
		}

		let oldAuthority = user.resolvedAccountAuthority
		let actorUserID = try systemOwner.requireID()
		let targetUserID = try user.requireID()
		try await req.db.transaction { database in
			user.accountAuthority = request.authority
			try await user.update(on: database)
			let auditRecord = AuthorityAuditRecord(
				actorUserID: actorUserID,
				targetUserID: targetUserID,
				oldAuthority: oldAuthority,
				newAuthority: request.authority
			)
			try await auditRecord.create(on: database)
		}
		return try await AdministrationUserResponse(user, on: req.db)
	}

	private func createUser(req: Request) async throws -> AdministrationUserResponse {
		_ = try await requireAdministrator(req)
		let create = try req.content.decode(AdministrationUserCreateRequest.self)
		let displayName = create.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
		let email = try normalizedEmail(create.email)
		try await ServerAccessModeService.requirePermittedEmail(email, on: req.db)
		guard !displayName.isEmpty, (8 ... 100).contains(create.password.count) else {
			throw Abort(.badRequest)
		}
		guard try await User.query(on: req.db).filter(\.$email == email).first() == nil else {
			throw Abort(.conflict)
		}

		let user = try User(
			email: email,
			passwordHash: req.password.hash(create.password),
			displayName: displayName,
			selfPassSerialNumber: UUID().uuidString,
			settingsData: JSONEncoder().encode(AccountSettings.default)
		)
		try await req.db.transaction { database in
			try await user.create(on: database)
			try await EventTagSubscriptionService.subscribeNewAccount(
				user.requireID(),
				on: database
			)
		}
		return try await AdministrationUserResponse(user, on: req.db)
	}

	private func deleteUser(req: Request) async throws -> HTTPStatus {
		_ = try await requireAdministrator(req)
		guard let id = req.parameters.get("userID", as: UUID.self), let user = try await User.find(id, on: req.db) else {
			throw Abort(.notFound)
		}
		try preventChangingSystemOwner(user)
		try await user.delete(on: req.db)
		return .noContent
	}

	private func userDetail(req: Request) async throws -> AdministrationUserDetailResponse {
		_ = try await requireAdministrator(req)
		guard let id = req.parameters.get("userID", as: UUID.self), let user = try await User.find(id, on: req.db) else {
			throw Abort(.notFound)
		}

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.dateEncodingStrategy = .iso8601
		encoder.dataEncodingStrategy = .custom { data, encoder in
			var container = encoder.singleValueContainer()
			try container.encode(String(data: data, encoding: .utf8) ?? data.base64EncodedString())
		}

		let devices = try await UserDevice.query(on: req.db)
			.filter(\.$user.$id == id)
			.all()

		let friendships = try await Friendship.query(on: req.db)
			.group(.or) { group in
				group.filter(\.$requester.$id == id)
				group.filter(\.$recipient.$id == id)
			}
			.with(\.$requester)
			.with(\.$recipient)
			.sort(\.$createdAt, .descending)
			.all()

		let rawData = try await AdministrationUserRawData(
			account: AdministrationRawAccount(user),
			ownerTimetables: OwnerTimetable.query(on: req.db).filter(\.$user.$id == id).all(),
			devices: devices.compactMap(AdministrationRawDevice.init),
			friendships: friendships.map(AdministrationRawFriendship.init),
			calendarEvents: CalendarEvent.query(on: req.db).filter(\.$user.$id == id).all(),
			schoolNotificationDeliveries: SchoolNotificationDelivery.query(on: req.db).filter(\.$user.$id == id).all()
		)

		let data = try encoder.encode(rawData)
		return AdministrationUserDetailResponse(rawData: String(decoding: data, as: UTF8.self))
	}

	private func broadcastNotification(req: Request) async throws -> BroadcastNotificationResponse {
		let sender = try await requireAdministrator(req)
		let request = try req.content.decode(BroadcastNotificationRequest.self)
		let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
		let subtitle = request.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
		let body = request.body?.trimmingCharacters(in: .whitespacesAndNewlines)

		guard !title.isEmpty, title.count <= 200 else {
			throw Abort(.badRequest)
		}

		guard subtitle?.count ?? 0 <= 200 else {
			throw Abort(.badRequest)
		}

		guard body?.count ?? 0 <= 2000 else {
			throw Abort(.badRequest)
		}

		return try await NotificationService().broadcast(
			title: title,
			subtitle: subtitle?.nilIfEmpty,
			body: body?.nilIfEmpty,
			sender: sender,
			on: req
		)
	}

	private func broadcastNotifications(req: Request) async throws -> [BroadcastNotificationHistoryResponse] {
		_ = try await requireAdministrator(req)
		return try await BroadcastNotificationRecord.query(on: req.db)
			.sort(\.$createdAt, .descending)
			.all()
			.map(BroadcastNotificationHistoryResponse.init)
	}

	private func deleteBroadcastNotification(req: Request) async throws -> BroadcastNotificationHistoryResponse {
		_ = try await requireAdministrator(req)
		guard let notificationID = req.parameters.get("notificationID", as: UUID.self),
		      let record = try await BroadcastNotificationRecord.find(notificationID, on: req.db)
		else {
			throw Abort(.notFound)
		}

		guard !record.isDeleted else {
			return try BroadcastNotificationHistoryResponse(record)
		}

		try await NotificationService().deleteBroadcast(record, on: req)
		record.isDeleted = true
		try await record.update(on: req.db)
		return try BroadcastNotificationHistoryResponse(record)
	}

	private func eventTags(req: Request) async throws -> AdministrationEventTagCatalogueResponse {
		_ = try await requireAdministrator(req)
		return try await eventTagCatalogue(on: req.db)
	}

	private func createEventTag(req: Request) async throws -> AdministrationEventTagCatalogueResponse {
		_ = try await requireAdministrator(req)
		let request = try req.content.decode(AdministrationEventTagRequest.self)
		try await req.db.transaction { database in
			let section = try await eventTagSection(id: request.sectionID, on: database)
			guard section.category == .yearGroup else {
				throw Abort(.badRequest, reason: "Only year-group tags are supported.")
			}
			let tag = try eventTag(from: request, section: section)
			try await validateTag(tag, aliases: request.associatedNames, excluding: nil, on: database)
			try await tag.create(on: database)
			try await replaceAssociatedNames(request.associatedNames, for: tag, on: database)
		}
		return try await eventTagCatalogue(on: req.db)
	}

	private func updateEventTag(req: Request) async throws -> AdministrationEventTagCatalogueResponse {
		_ = try await requireAdministrator(req)
		guard let tagID = req.parameters.get("tagID", as: UUID.self), let tag = try await EventTag.find(tagID, on: req.db) else {
			throw Abort(.notFound)
		}

		let request = try req.content.decode(AdministrationEventTagRequest.self)
		try await req.db.transaction { database in
			let section = try await eventTagSection(id: request.sectionID, on: database)
			try apply(request, to: tag, section: section)
			try await validateTag(tag, aliases: request.associatedNames, excluding: tagID, on: database)
			tag.revision += 1
			try await tag.update(on: database)
			try await replaceAssociatedNames(request.associatedNames, for: tag, on: database)
			if tag.isArchived {
				try await removeAssociations(for: tagID, on: database)
			}
		}
		return try await eventTagCatalogue(on: req.db)
	}

	private func deleteEventTag(req: Request) async throws -> AdministrationEventTagCatalogueResponse {
		_ = try await requireAdministrator(req)
		guard let tagID = req.parameters.get("tagID", as: UUID.self),
		      let tag = try await EventTag.find(tagID, on: req.db)
		else {
			throw Abort(.notFound)
		}
		guard tag.category != .yearGroup else {
			throw Abort(.badRequest, reason: "Canonical year-group tags cannot be deleted.")
		}

		try await req.db.transaction { database in
			try await removeAssociations(for: tagID, on: database)
			try await EventTagAssociatedName.query(on: database)
				.filter(\.$eventTag.$id == tagID)
				.delete()
			try await tag.delete(on: database)
		}

		return try await eventTagCatalogue(on: req.db)
	}

	private func reorderEventTags(req: Request) async throws -> AdministrationEventTagCatalogueResponse {
		_ = try await requireAdministrator(req)
		let request = try req.content.decode(AdministrationEventTagOrderRequest.self)
		guard Set(request.tagIDs).count == request.tagIDs.count else {
			throw Abort(.badRequest)
		}

		let tags = try await EventTag.query(on: req.db).all()
		let tagsByID = Dictionary(uniqueKeysWithValues: tags.compactMap { tag in
			tag.id.map { ($0, tag) }
		})
		guard Set(request.tagIDs) == Set(tagsByID.keys) else {
			throw Abort(.badRequest)
		}

		try await req.db.transaction { database in
			for (index, tagID) in request.tagIDs.enumerated() {
				guard let tag = tagsByID[tagID] else {
					throw Abort(.badRequest)
				}
				tag.sortOrder = index
				tag.revision += 1
				try await tag.update(on: database)
			}
		}

		return try await eventTagCatalogue(on: req.db)
	}

	private func createEventTagSection(req: Request) async throws -> AdministrationEventTagCatalogueResponse {
		_ = try await requireAdministrator(req)
		let request = try req.content.decode(AdministrationEventTagSectionCreateRequest.self)
		guard request.category == .yearGroup else {
			throw Abort(.badRequest, reason: "Only the year-group tag section is supported.")
		}
		let displayName = try validatedDisplayName(request.displayName)
		guard try await EventTagSection.query(on: req.db).filter(\.$category == request.category).first() == nil else {
			throw Abort(.conflict)
		}

		try await EventTagSection(
			category: request.category,
			displayName: displayName,
			sortOrder: request.sortOrder
		).create(on: req.db)
		return try await eventTagCatalogue(on: req.db)
	}

	private func updateEventTagSection(req: Request) async throws -> AdministrationEventTagCatalogueResponse {
		_ = try await requireAdministrator(req)
		guard let sectionID = req.parameters.get("sectionID", as: UUID.self), let section = try await EventTagSection.find(sectionID, on: req.db) else {
			throw Abort(.notFound)
		}

		let request = try req.content.decode(AdministrationEventTagSectionUpdateRequest.self)
		guard section.category != .yearGroup || !request.isArchived else {
			throw Abort(
				.badRequest,
				reason: "The canonical year-group section cannot be archived."
			)
		}
		section.displayName = try validatedDisplayName(request.displayName)
		section.sortOrder = request.sortOrder
		section.isArchived = request.isArchived
		section.revision += 1
		try await req.db.transaction { database in
			try await section.update(on: database)
			if section.isArchived {
				let tags = try await EventTag.query(on: database)
					.filter(\.$section.$id == sectionID)
					.all()
				for tag in tags {
					tag.isArchived = true
					tag.revision += 1
					try await tag.update(on: database)
					try await EventTagAssociatedName.query(on: database)
						.filter(\.$eventTag.$id == tag.requireID())
						.set(\.$isActive, to: false)
						.update()
					try await removeAssociations(
						for: tag.requireID(),
						on: database
					)
				}
			}
		}
		return try await eventTagCatalogue(on: req.db)
	}

	private func calendar(req: Request) async throws -> [AdministrationCalendarEntryResponse] {
		_ = try await requireAdministrator(req)
		return try await SchoolCalendarEntry.query(on: req.db).all().map(AdministrationCalendarEntryResponse.init)
	}

	private func createCalendarEntry(req: Request) async throws -> [AdministrationCalendarEntryResponse] {
		_ = try await requireAdministrator(req)
		let request = try req.content.decode(AdministrationCalendarEntryRequest.self)
		try validate(request)
		try await SchoolCalendarEntry(kind: request.kind, label: request.label, startDate: request.startDate.storageValue, endDate: request.endDate?.storageValue).create(on: req.db)
		return try await calendar(req: req)
	}

	private func updateCalendarEntry(req: Request) async throws -> [AdministrationCalendarEntryResponse] {
		_ = try await requireAdministrator(req)
		let request = try req.content.decode(AdministrationCalendarEntryRequest.self)
		try validate(request)
		guard let id = req.parameters.get("entryID", as: UUID.self), let entry = try await SchoolCalendarEntry.find(id, on: req.db) else { throw Abort(.notFound) }
		entry.kind = request.kind
		entry.label = request.label
		entry.startDate = request.startDate.storageValue
		entry.endDate = request.endDate?.storageValue
		try await entry.update(on: req.db)
		return try await calendar(req: req)
	}

	private func deleteCalendarEntry(req: Request) async throws -> [AdministrationCalendarEntryResponse] {
		_ = try await requireAdministrator(req)
		guard let id = req.parameters.get("entryID", as: UUID.self), let entry = try await SchoolCalendarEntry.find(id, on: req.db) else {
			throw Abort(.notFound)
		}
		try await entry.delete(on: req.db)
		return try await calendar(req: req)
	}

	private func requireAdministrator(_ req: Request) async throws -> User {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw Abort(.notFound)
		}
		guard user.resolvedAccountAuthority.isAdministrator else {
			throw Abort(.forbidden)
		}
		return user
	}

	private func requireSystemOwner(_ req: Request) async throws -> User {
		let user = try await requireAdministrator(req)
		guard user.resolvedAccountAuthority == .systemOwner else {
			throw Abort(.forbidden)
		}
		return user
	}

	private func preventChangingSystemOwner(_ target: User) throws {
		guard target.resolvedAccountAuthority != .systemOwner else {
			throw Abort(.forbidden)
		}
	}

	private func validatedSpecialBadge(
		_ request: AdministrationSpecialBadgeRequest
	) throws -> (symbol: String, backgroundColor: ProfileColorDTO?, symbolColor: ProfileColorDTO?, priority: Int, accessibilityLabel: String) {
		let symbol = request.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
		let accessibilityLabel = request.accessibilityLabel.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !symbol.isEmpty, symbol.count <= 120,
		      !accessibilityLabel.isEmpty, accessibilityLabel.count <= 120,
		      (0 ... 10000).contains(request.priority)
		else {
			throw Abort(.badRequest)
		}

		return (
			symbol,
			normalizedColor(request.backgroundColor),
			normalizedColor(request.symbolColor),
			request.priority,
			accessibilityLabel
		)
	}

	private func normalizedColor(_ color: ProfileColorDTO?) -> ProfileColorDTO? {
		guard let color else {
			return nil
		}

		return ProfileColorDTO(
			red: normalizedColorComponent(color.red),
			green: normalizedColorComponent(color.green),
			blue: normalizedColorComponent(color.blue),
			alpha: normalizedColorComponent(color.alpha)
		)
	}

	private func normalizedColorComponent(_ value: Double) -> Double {
		guard value.isFinite else {
			return 0
		}

		return min(max(value, 0), 1)
	}

	private func encodeColor(_ color: ProfileColorDTO?) throws -> Data? {
		guard let color else {
			return nil
		}

		return try JSONEncoder().encode(color)
	}

	private func validate(_ request: AdministrationCalendarEntryRequest) throws {
		guard ["term", "noSchool"].contains(request.kind), !request.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, request.label.count <= 120, request.kind == "noSchool" || request.endDate != nil else { throw Abort(.badRequest) }
	}

	private func eventTagCatalogue(on database: any Database) async throws -> AdministrationEventTagCatalogueResponse {
		let sections = try await EventTagSection.query(on: database)
			.sort(\.$sortOrder)
			.sort(\.$displayName)
			.all()

		let responseSections = try await sections.asyncMap { section in
			let tags = try await EventTag.query(on: database)
				.filter(\.$section.$id == section.requireID())
				.sort(\.$sortOrder)
				.sort(\.$displayName)
				.all()
			return try await AdministrationEventTagSectionResponse(section, tags: tags, on: database)
		}
		return AdministrationEventTagCatalogueResponse(sections: responseSections)
	}

	private func eventTagSection(id: UUID, on database: any Database) async throws -> EventTagSection {
		guard let section = try await EventTagSection.find(id, on: database) else {
			throw Abort(.notFound)
		}
		return section
	}

	private func eventTag(from request: AdministrationEventTagRequest, section: EventTagSection) throws -> EventTag {
		try EventTag(
			sectionID: section.requireID(),
			slug: validatedSlug(request.slug),
			displayName: validatedDisplayName(request.displayName),
			category: section.category,
			symbol: request.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
			colorHex: request.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
			sortOrder: request.sortOrder,
			isArchived: request.isArchived
		)
	}

	private func apply(_ request: AdministrationEventTagRequest, to tag: EventTag, section: EventTagSection) throws {
		if tag.category == .yearGroup {
			guard section.category == .yearGroup, !request.isArchived else {
				throw Abort(.badRequest, reason: "Canonical year-group tags cannot move category or be archived.")
			}
			tag.displayName = try validatedDisplayName(request.displayName)
			tag.symbol = request.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
			tag.colorHex = request.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
			tag.sortOrder = request.sortOrder
			return
		}

		tag.$section.id = try section.requireID()
		tag.slug = try validatedSlug(request.slug)
		tag.displayName = try validatedDisplayName(request.displayName)
		tag.category = section.category
		tag.symbol = request.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
		tag.colorHex = request.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
		tag.sortOrder = request.sortOrder
		tag.isArchived = request.isArchived
	}

	private func validateTag(
		_ tag: EventTag,
		aliases: [String],
		excluding tagID: UUID?,
		on database: any Database
	) async throws {
		let existingTag = try await EventTag.query(on: database)
			.filter(\.$slug == tag.slug)
			.first()
		guard existingTag?.id == tagID || existingTag == nil else {
			throw Abort(.conflict)
		}

		let normalizedAliases = try normalizedAssociatedNames(aliases, displayName: tag.displayName)
		guard !tag.isArchived else {
			return
		}

		let categoryTags = try await EventTag.query(on: database)
			.filter(\.$category == tag.category)
			.filter(\.$isArchived == false)
			.all()

		for candidate in categoryTags where candidate.id != tagID {
			let candidateNames = try await EventTagAssociatedName.query(on: database)
				.filter(\.$eventTag.$id == candidate.requireID())
				.all()
			guard Set(candidateNames.map(\.normalizedName)).isDisjoint(with: normalizedAliases.map(\.normalizedName)) else {
				throw Abort(.conflict)
			}
		}
	}

	private func replaceAssociatedNames(
		_ aliases: [String],
		for tag: EventTag,
		on database: any Database
	) async throws {
		if tag.category == .yearGroup,
		   try await EventTagAssociatedName.query(on: database)
		   .filter(\.$eventTag.$id == tag.requireID())
		   .first() != nil
		{
			return
		}

		let names = try normalizedAssociatedNames(aliases, displayName: tag.displayName)
		try await EventTagAssociatedName.query(on: database)
			.filter(\.$eventTag.$id == tag.requireID())
			.delete()
		for name in names {
			try await EventTagAssociatedName(
				eventTagID: tag.requireID(),
				displayName: name.displayName,
				normalizedName: name.normalizedName,
				category: tag.category,
				isActive: !tag.isArchived
			).create(on: database)
		}
	}

	private func removeAssociations(
		for tagID: UUID,
		on database: any Database
	) async throws {
		try await AccountEventTagSubscription.query(on: database)
			.filter(\.$eventTag.$id == tagID)
			.delete()
		try await CalendarEventTag.query(on: database)
			.filter(\.$eventTag.$id == tagID)
			.delete()
	}

	private func normalizedAssociatedNames(
		_ aliases: [String],
		displayName: String
	) throws -> [(displayName: String, normalizedName: String)] {
		let names = aliases + [displayName]
		var normalizedNames: Set<String> = []
		var result: [(displayName: String, normalizedName: String)] = []

		for name in names {
			let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !displayName.isEmpty, displayName.count <= 120 else {
				throw Abort(.badRequest)
			}
			let normalizedName = displayName
				.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
				.lowercased()
				.split(whereSeparator: \.isWhitespace)
				.joined(separator: " ")
			guard normalizedNames.insert(normalizedName).inserted else {
				continue
			}
			result.append((displayName, normalizedName))
		}

		return result
	}

	private func validatedDisplayName(_ value: String) throws -> String {
		let displayName = value.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !displayName.isEmpty, displayName.count <= 120 else {
			throw Abort(.badRequest)
		}
		return displayName
	}

	private func validatedSlug(_ value: String) throws -> String {
		let slug = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !slug.isEmpty, slug.count <= 120, slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
			throw Abort(.badRequest)
		}
		return slug
	}
}

private struct DeviceOSVersionKey: Hashable {
	let platform: String
	let osMajorVersion: Int
	let osMinorVersion: Int
	let isDebug: Bool
	let isOSBeta: Bool
}

private extension String {
	var nilIfEmpty: String? {
		isEmpty ? nil : self
	}
}

private struct AdministrationSpecialBadgeResponse: Content {
	let id: UUID
	let symbol: String
	let backgroundColor: ProfileColorDTO?
	let symbolColor: ProfileColorDTO?
	let priority: Int
	let accessibilityLabel: String
	let assignedUserIDs: [UUID]

	init(_ badge: SpecialProfileBadge, on database: any Database) async throws {
		id = try badge.requireID()
		let profileBadge = badge.profileBadge
		symbol = profileBadge.symbol
		backgroundColor = profileBadge.backgroundColor
		symbolColor = profileBadge.symbolColor
		priority = profileBadge.priority
		accessibilityLabel = profileBadge.accessibilityLabel
		assignedUserIDs = try await UserSpecialProfileBadge.query(on: database)
			.filter(\.$badge.$id == id)
			.all()
			.map(\.$user.id)
	}
}

private struct AdministrationSpecialBadgeRequest: Content {
	let symbol: String
	let backgroundColor: ProfileColorDTO?
	let symbolColor: ProfileColorDTO?
	let priority: Int
	let accessibilityLabel: String
}

private struct AdministrationSpecialBadgeAssignmentsRequest: Content {
	let userIDs: [UUID]
}

private struct AdministrationSpecialBadgeOrderRequest: Content {
	let badgeIDs: [UUID]
}

private extension Array {
	func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
		var result: [T] = []
		for element in self {
			try await result.append(transform(element))
		}
		return result
	}
}

private struct AdministrationDashboardResponse: Content {
	let isAdmin: Bool
	let authority: AccountAuthority
	let pendingModerationCount: Int
}

private struct AdministrationUserCreateRequest: Content {
	let displayName: String
	let email: String
	let password: String
}

private struct AdministrationUserUpdateRequest: Content {
	let displayName: String
	let email: String
	let password: String?
}

private struct AdministrationUserAuthorityUpdateRequest: Content {
	let authority: AccountAuthority
}

private struct AdministrationUserDetailResponse: Content {
	let rawData: String
}

private struct AdministrationUserResponse: Content {
	let id: UUID
	let displayName: String
	let email: String
	let createdAt: Date?
	let authority: AccountAuthority
	let appearance: ProfileAppearanceDTO
	let photo: ProfilePhotoMetadataDTO?
	let badges: [ProfileBadgeDTO]

	init(_ user: User, on database: any Database) async throws {
		id = try user.requireID()
		displayName = user.displayName
		email = user.email
		createdAt = user.createdAt
		authority = user.resolvedAccountAuthority
		appearance = user.decodedProfileAppearance
		photo = try await user.profilePhotoMetadata(on: database)
		badges = try await user.profileBadges(on: database)
	}
}

private struct AdministrationEventTagCatalogueResponse: Content {
	let sections: [AdministrationEventTagSectionResponse]
}

private struct BroadcastNotificationHistoryResponse: Content {
	let id: UUID
	let senderEmail: String
	let senderAuthority: AccountAuthority
	let title: String
	let subtitle: String?
	let body: String?
	let eligibleDeviceCount: Int
	let deliveredDeviceCount: Int
	let invalidatedDeviceCount: Int
	let failedDeviceCount: Int
	let deliveryState: BroadcastNotificationDeliveryState
	let isDeleted: Bool
	let failureSummary: String?
	let createdAt: Date?

	init(_ record: BroadcastNotificationRecord) throws {
		id = try record.requireID()
		senderEmail = record.senderEmail
		senderAuthority = record.senderAuthority
		title = record.title
		subtitle = record.subtitle
		body = record.body
		eligibleDeviceCount = record.eligibleDeviceCount
		deliveredDeviceCount = record.deliveredDeviceCount
		invalidatedDeviceCount = record.invalidatedDeviceCount
		failedDeviceCount = record.failedDeviceCount
		deliveryState = record.deliveryState
		isDeleted = record.isDeleted
		failureSummary = record.failureSummary
		createdAt = record.createdAt
	}
}

private struct AdministrationEventTagSectionResponse: Content {
	let id: UUID
	let category: EventTagCategory
	let displayName: String
	let sortOrder: Int
	let isArchived: Bool
	let revision: Int
	let tags: [AdministrationEventTagResponse]

	init(_ section: EventTagSection, tags: [EventTag], on database: any Database) async throws {
		id = try section.requireID()
		category = section.category
		displayName = section.displayName
		sortOrder = section.sortOrder
		isArchived = section.isArchived
		revision = section.revision
		self.tags = try await tags.asyncMap { tag in
			try await AdministrationEventTagResponse(tag, on: database)
		}
	}
}

private struct AdministrationEventTagResponse: Content {
	let id: UUID
	let sectionID: UUID
	let slug: String
	let displayName: String
	let category: EventTagCategory
	let symbol: String?
	let colorHex: String?
	let sortOrder: Int
	let isArchived: Bool
	let revision: Int
	let associatedNames: [String]

	init(_ tag: EventTag, on database: any Database) async throws {
		id = try tag.requireID()
		sectionID = tag.$section.id
		slug = tag.slug
		displayName = tag.displayName
		category = tag.category
		symbol = tag.symbol
		colorHex = tag.colorHex
		sortOrder = tag.sortOrder
		isArchived = tag.isArchived
		revision = tag.revision
		associatedNames = try await EventTagAssociatedName.query(on: database)
			.filter(\.$eventTag.$id == id)
			.sort(\.$displayName)
			.all()
			.map(\.displayName)
	}
}

private struct AdministrationEventTagRequest: Content {
	let sectionID: UUID
	let slug: String
	let displayName: String
	let symbol: String?
	let colorHex: String?
	let sortOrder: Int
	let isArchived: Bool
	let associatedNames: [String]
}

private struct AdministrationEventTagOrderRequest: Content {
	let tagIDs: [UUID]
}

private struct AdministrationEventTagSectionCreateRequest: Content {
	let category: EventTagCategory
	let displayName: String
	let sortOrder: Int
}

private struct AdministrationEventTagSectionUpdateRequest: Content {
	let displayName: String
	let sortOrder: Int
	let isArchived: Bool
}

private struct AdministrationModerationResolutionRequest: Content {
	let action: ModerationAction
}

private struct AdministrationEmailDeliveryRecordResponse: Content {
	let id: UUID
	let recipient: String
	let subject: String
	let body: String
	let status: String
	let failureReason: String?
	let createdAt: Date?
	let updatedAt: Date?

	init(_ record: EmailDeliveryRecord) throws {
		id = try record.requireID()
		recipient = record.recipient
		subject = record.subject
		body = record.body
		status = record.status
		failureReason = record.failureReason
		createdAt = record.createdAt
		updatedAt = record.updatedAt
	}
}

private struct AdministrationFriendshipDateChangeRequestResponse: Content {
	let id: UUID
	let requesterID: UUID
	let requesterDisplayName: String?
	let friendID: UUID?
	let friendDisplayName: String?
	let requestedDate: Date
	let action: ModerationAction
	let createdAt: Date?

	init(
		_ request: FriendshipDateChangeRequest,
		requesterDisplayName: String?,
		friendID: UUID?,
		friendDisplayName: String?
	) throws {
		id = try request.requireID()
		requesterID = request.requesterID
		self.requesterDisplayName = requesterDisplayName
		self.friendID = friendID
		self.friendDisplayName = friendDisplayName
		requestedDate = request.requestedDate
		action = request.action
		createdAt = request.createdAt
	}
}

private struct AdministrationUserReportResponse: Content {
	let id: UUID
	let reporterID: UUID
	let reporterDisplayName: String?
	let reportedUserID: UUID
	let reportedUserDisplayName: String?
	let action: ModerationAction
	let createdAt: Date?

	init(
		_ report: UserReport,
		reporterDisplayName: String?,
		reportedUserDisplayName: String?
	) throws {
		id = try report.requireID()
		reporterID = report.reporterID
		self.reporterDisplayName = reporterDisplayName
		reportedUserID = report.reportedUserID
		self.reportedUserDisplayName = reportedUserDisplayName
		action = report.action
		createdAt = report.createdAt
	}
}

private struct AdministrationRawAccount: Content {
	let id: UUID
	let email: String?
	let displayName: String
	let selfPassSerialNumber: String
	let settingsData: Data
	let settingsRevision: Int
	let gradeTracker: GradeTrackerDocument?
	let gradeTrackerRevision: Int
	let profileAppearanceData: Data?
	let profileRevision: Int
	let accountAuthority: AccountAuthority
	let locationStatusHistory: [LocationStatusItem]
	let createdAt: Date?
	let updatedAt: Date?

	init(_ user: User) throws {
		id = try user.requireID()
		email = user.email
		displayName = user.displayName
		selfPassSerialNumber = user.selfPassSerialNumber
		settingsData = user.settingsData
		settingsRevision = user.settingsRevision
		gradeTracker = try user.gradeTrackerData.map {
			try JSONDecoder().decode(GradeTrackerDocument.self, from: $0)
		}
		gradeTrackerRevision = user.gradeTrackerRevision
		profileAppearanceData = user.profileAppearanceData
		profileRevision = user.profileRevision
		accountAuthority = user.resolvedAccountAuthority
		locationStatusHistory = try user.locationStatusHistory()
		createdAt = user.createdAt
		updatedAt = user.updatedAt
	}
}

private struct AdministrationRawDevice: Content {
	let id: UUID
	let platform: String
	let isDebug: Bool
	let lastSeenAt: Date
	let createdAt: Date?
	let updatedAt: Date?

	init?(_ device: UserDevice) {
		guard let id = device.id else {
			return nil
		}

		self.id = id
		platform = device.platform
		isDebug = device.isDebug
		lastSeenAt = device.lastSeenAt
		createdAt = device.createdAt
		updatedAt = device.updatedAt
	}
}

private struct AdministrationRawFriendship: Content {
	let id: UUID
	let status: FriendshipStatus
	let requesterID: UUID
	let requesterEmail: String?
	let requesterDisplayName: String
	let recipientID: UUID
	let recipientEmail: String?
	let recipientDisplayName: String
	let acceptedAt: Date?
	let createdAt: Date?
	let updatedAt: Date?

	init(_ friendship: Friendship) throws {
		id = try friendship.requireID()
		status = friendship.status
		requesterID = friendship.$requester.id
		requesterEmail = friendship.requester.email
		requesterDisplayName = friendship.requester.displayName
		recipientID = friendship.$recipient.id
		recipientEmail = friendship.recipient.email
		recipientDisplayName = friendship.recipient.displayName
		acceptedAt = friendship.acceptedAt
		createdAt = friendship.createdAt
		updatedAt = friendship.updatedAt
	}
}

private struct AdministrationUserRawData: Content {
	let account: AdministrationRawAccount
	let ownerTimetables: [OwnerTimetable]
	let devices: [AdministrationRawDevice]
	let friendships: [AdministrationRawFriendship]
	let calendarEvents: [CalendarEvent]
	let schoolNotificationDeliveries: [SchoolNotificationDelivery]
}

private struct AdministrationCalendarEntryRequest: Content {
	let kind: String
	let label: String
	let startDate: SchoolCalendarDate
	let endDate: SchoolCalendarDate?
}

private struct AdministrationCalendarEntryResponse: Content {
	let id: UUID
	let kind: String
	let label: String
	let startDate: SchoolCalendarDate
	let endDate: SchoolCalendarDate?

	init(_ entry: SchoolCalendarEntry) throws {
		id = try entry.requireID()
		kind = entry.kind
		label = entry.label
		startDate = try SchoolCalendarDate(storageValue: entry.startDate)
		endDate = try entry.endDate.map(SchoolCalendarDate.init(storageValue:))
	}
}

private extension SchoolCalendarDate {
	var storageValue: String {
		String(format: "%04d-%02d-%02d", year, month, day)
	}

	init(storageValue: String) throws {
		let values = storageValue
			.split(separator: "-")
			.compactMap { Int($0) }
		guard values.count == 3 else {
			throw Abort(.internalServerError)
		}
		year = values[0]
		month = values[1]
		day = values[2]
	}
}
