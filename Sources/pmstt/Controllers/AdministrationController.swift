import Fluent
import Vapor

struct AdministrationController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let admin = routes.grouped("v1", "administration").grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		admin.get(use: dashboard)
		admin.get("users", use: users)
		admin.get("users", ":userID", use: userDetail)
		admin.post("users", use: createUser)
		admin.put("users", ":userID", use: updateUser)
		admin.delete("users", ":userID", use: deleteUser)
		admin.post("broadcast-notification", use: broadcastNotification)
		admin.get("calendar", use: calendar)
		admin.post("calendar", use: createCalendarEntry)
		admin.put("calendar", ":entryID", use: updateCalendarEntry)
		admin.delete("calendar", ":entryID", use: deleteCalendarEntry)
	}

	private func dashboard(req: Request) async throws -> AdministrationDashboardResponse {
		try await requireAdmin(req)
		return AdministrationDashboardResponse(isAdmin: true)
	}

	private func users(req: Request) async throws -> [AdministrationUserResponse] {
		try await requireAdmin(req)
		return try await User.query(on: req.db).sort(\.$displayName).all().map(AdministrationUserResponse.init)
	}

	private func updateUser(req: Request) async throws -> AdministrationUserResponse {
		try await requireAdmin(req)
		guard let id = req.parameters.get("userID", as: UUID.self), let user = try await User.find(id, on: req.db) else { throw Abort(.notFound) }
		let update = try req.content.decode(AdministrationUserUpdateRequest.self)
		let displayName = update.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !displayName.isEmpty else { throw Abort(.badRequest) }
		let email = update.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard email.contains("@") else { throw Abort(.badRequest) }
		if email != user.email, try await User.query(on: req.db).filter(\.$email == email).first() != nil {
			throw Abort(.conflict)
		}
		user.displayName = displayName
		user.email = email
		if let password = update.password, !password.isEmpty {
			guard password.count >= 8 else { throw Abort(.badRequest) }
			user.passwordHash = try req.password.hash(password)
		}
		try await user.update(on: req.db)
		return try AdministrationUserResponse(user)
	}

	private func createUser(req: Request) async throws -> AdministrationUserResponse {
		try await requireAdmin(req)
		let create = try req.content.decode(AdministrationUserCreateRequest.self)
		let displayName = create.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
		let email = create.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !displayName.isEmpty, email.contains("@"), create.password.count >= 8 else {
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
		try await user.create(on: req.db)
		return try AdministrationUserResponse(user)
	}

	private func deleteUser(req: Request) async throws -> HTTPStatus {
		try await requireAdmin(req)
		guard let id = req.parameters.get("userID", as: UUID.self), let user = try await User.find(id, on: req.db) else {
			throw Abort(.notFound)
		}
		try await user.delete(on: req.db)
		return .noContent
	}

	private func userDetail(req: Request) async throws -> AdministrationUserDetailResponse {
		try await requireAdmin(req)
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

		let rawData = try await AdministrationUserRawData(
			account: AdministrationRawAccount(user),
			ownerTimetables: OwnerTimetable.query(on: req.db).filter(\.$user.$id == id).all(),
			createdTimetables: CreatedTimetable.query(on: req.db).filter(\.$author.$id == id).all(),
			receivedTimetableImports: ReceivedTimetableImport.query(on: req.db).filter(\.$user.$id == id).all(),
			receivedPassMirrors: ReceivedPassMirror.query(on: req.db).filter(\.$user.$id == id).all(),
			receivedNameOverrides: ReceivedNameOverride.query(on: req.db).filter(\.$user.$id == id).all(),
			devices: UserDevice.query(on: req.db).filter(\.$user.$id == id).all(),
			calendarEvents: CalendarEvent.query(on: req.db).filter(\.$user.$id == id).all(),
			schoolNotificationDeliveries: SchoolNotificationDelivery.query(on: req.db).filter(\.$user.$id == id).all(),
			sessions: UserToken.query(on: req.db).filter(\.$user.$id == id).all()
		)

		let data = try encoder.encode(rawData)
		return AdministrationUserDetailResponse(rawData: String(decoding: data, as: UTF8.self))
	}

	private func broadcastNotification(req: Request) async throws -> BroadcastNotificationResponse {
		try await requireAdmin(req)
		let request = try req.content.decode(BroadcastNotificationRequest.self)
		let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
		let subtitle = request.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
		let body = request.body.trimmingCharacters(in: .whitespacesAndNewlines)

		guard !title.isEmpty, title.count <= 200 else {
			throw Abort(.badRequest)
		}

		guard !subtitle.isEmpty, subtitle.count <= 200 else {
			throw Abort(.badRequest)
		}

		guard !body.isEmpty, body.count <= 2000 else {
			throw Abort(.badRequest)
		}

		return try await NotificationService().broadcast(title: title, subtitle: subtitle, body: body, on: req)
	}

	private func calendar(req: Request) async throws -> [AdministrationCalendarEntryResponse] {
		try await requireAdmin(req)
		return try await SchoolCalendarEntry.query(on: req.db).all().map(AdministrationCalendarEntryResponse.init)
	}

	private func createCalendarEntry(req: Request) async throws -> [AdministrationCalendarEntryResponse] {
		try await requireAdmin(req); let request = try req.content.decode(AdministrationCalendarEntryRequest.self); try validate(request)
		try await SchoolCalendarEntry(kind: request.kind, label: request.label, startDate: request.startDate.storageValue, endDate: request.endDate?.storageValue).create(on: req.db)
		return try await calendar(req: req)
	}

	private func updateCalendarEntry(req: Request) async throws -> [AdministrationCalendarEntryResponse] {
		try await requireAdmin(req); let request = try req.content.decode(AdministrationCalendarEntryRequest.self); try validate(request)
		guard let id = req.parameters.get("entryID", as: UUID.self), let entry = try await SchoolCalendarEntry.find(id, on: req.db) else { throw Abort(.notFound) }
		entry.kind = request.kind; entry.label = request.label; entry.startDate = request.startDate.storageValue; entry.endDate = request.endDate?.storageValue
		try await entry.update(on: req.db); return try await calendar(req: req)
	}

	private func deleteCalendarEntry(req: Request) async throws -> [AdministrationCalendarEntryResponse] {
		try await requireAdmin(req); guard let id = req.parameters.get("entryID", as: UUID.self), let entry = try await SchoolCalendarEntry.find(id, on: req.db) else { throw Abort(.notFound) }
		try await entry.delete(on: req.db); return try await calendar(req: req)
	}

	private func requireAdmin(_ req: Request) async throws {
		let payload = try req.auth.require(UserPayload.self); guard let user = try await User.find(payload.sub, on: req.db) else { throw Abort(.notFound) }
		let emails = Set((Environment.get("TIMETABLE_EVENT_ADMIN_EMAILS") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
		guard let email = user.email?.lowercased(), emails.contains(email) else { throw Abort(.forbidden) }
	}

	private func validate(_ request: AdministrationCalendarEntryRequest) throws {
		guard ["term", "noSchool"].contains(request.kind), !request.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, request.label.count <= 120, request.kind == "noSchool" || request.endDate != nil else { throw Abort(.badRequest) }
	}
}

private struct AdministrationDashboardResponse: Content { let isAdmin: Bool }
private struct AdministrationUserCreateRequest: Content {
	let displayName: String
	let email: String
	let password: String
}

private struct AdministrationUserUpdateRequest: Content { let displayName: String; let email: String; let password: String? }
private struct AdministrationUserDetailResponse: Content {
	let rawData: String
}

private struct AdministrationUserResponse: Content { let id: UUID; let displayName: String; let email: String?; let createdAt: Date?; init(_ user: User) throws {
	id = try user.requireID(); displayName = user.displayName; email = user.email; createdAt = user.createdAt
} }
private struct AdministrationRawAccount: Content {
	let id: UUID
	let email: String?
	let appleSubject: String?
	let appleEmailForwardingEnabled: Bool?
	let appleAuthorizationRevokedAt: Date?
	let displayName: String
	let selfPassSerialNumber: String
	let settingsData: Data
	let createdAt: Date?
	let updatedAt: Date?

	init(_ user: User) throws {
		id = try user.requireID()
		email = user.email
		appleSubject = user.appleSubject
		appleEmailForwardingEnabled = user.appleEmailForwardingEnabled
		appleAuthorizationRevokedAt = user.appleAuthorizationRevokedAt
		displayName = user.displayName
		selfPassSerialNumber = user.selfPassSerialNumber
		settingsData = user.settingsData
		createdAt = user.createdAt
		updatedAt = user.updatedAt
	}
}

private struct AdministrationUserRawData: Content {
	let account: AdministrationRawAccount
	let ownerTimetables: [OwnerTimetable]
	let createdTimetables: [CreatedTimetable]
	let receivedTimetableImports: [ReceivedTimetableImport]
	let receivedPassMirrors: [ReceivedPassMirror]
	let receivedNameOverrides: [ReceivedNameOverride]
	let devices: [UserDevice]
	let calendarEvents: [CalendarEvent]
	let schoolNotificationDeliveries: [SchoolNotificationDelivery]
	let sessions: [UserToken]
}

private struct AdministrationCalendarEntryRequest: Content { let kind: String; let label: String; let startDate: SchoolCalendarDate; let endDate: SchoolCalendarDate? }
private struct AdministrationCalendarEntryResponse: Content { let id: UUID; let kind: String; let label: String; let startDate: SchoolCalendarDate; let endDate: SchoolCalendarDate?; init(_ entry: SchoolCalendarEntry) throws {
	id = try entry.requireID(); kind = entry.kind; label = entry.label; startDate = try SchoolCalendarDate(storageValue: entry.startDate); endDate = try entry.endDate.map(SchoolCalendarDate.init(storageValue:))
} }

private extension SchoolCalendarDate { var storageValue: String {
	String(format: "%04d-%02d-%02d", year, month, day)
}; init(storageValue: String) throws {
	let values = storageValue.split(separator: "-").compactMap { Int($0) }; guard values.count == 3 else { throw Abort(.internalServerError) }; year = values[0]; month = values[1]; day = values[2]
} }
