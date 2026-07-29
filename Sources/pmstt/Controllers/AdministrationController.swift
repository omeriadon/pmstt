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
		admin.put("users", ":userID", "authority", use: updateAuthority)
		admin.post("broadcast-notification", use: broadcastNotification)
		admin.get("broadcast-notifications", use: broadcastNotifications)
		admin.get("profile-storage-quota", use: profileStorageQuota)
		admin.get("event-tags", use: eventTags)
		admin.post("event-tags", use: createEventTag)
		admin.put("event-tags", ":tagID", use: updateEventTag)
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

	private func dashboard(req: Request) async throws -> AdministrationDashboardResponse {
		let user = try await requireAdministrator(req)
		return AdministrationDashboardResponse(
			isAdmin: true,
			authority: user.resolvedAccountAuthority
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
			responses.append(try await AdministrationUserResponse(user, on: req.db))
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
		let email = try normalizedSchoolEmail(update.email)
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
		try await req.db.transaction { database in
			user.accountAuthority = request.authority
			try await user.update(on: database)
			let auditRecord = AuthorityAuditRecord(
				actorUserID: systemOwner.requireID(),
				targetUserID: user.requireID(),
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
		let email = try normalizedSchoolEmail(create.email)
		try await ServerAccessModeService.requirePermittedEmail(email, on: req.db)
		guard !displayName.isEmpty, create.password.count >= 8 else {
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

		let rawData = try await AdministrationUserRawData(
			account: AdministrationRawAccount(user),
			ownerTimetables: OwnerTimetable.query(on: req.db).filter(\.$user.$id == id).all(),
			createdTimetables: CreatedTimetable.query(on: req.db).filter(\.$author.$id == id).all(),
			receivedTimetableImports: ReceivedTimetableImport.query(on: req.db).filter(\.$user.$id == id).all(),
			receivedPassMirrors: ReceivedPassMirror.query(on: req.db).filter(\.$user.$id == id).all(),
			receivedNameOverrides: ReceivedNameOverride.query(on: req.db).filter(\.$user.$id == id).all(),
			devices: devices.compactMap(AdministrationRawDevice.init),
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

	private func eventTags(req: Request) async throws -> AdministrationEventTagCatalogueResponse {
		_ = try await requireAdministrator(req)
		return try await eventTagCatalogue(on: req.db)
	}

	private func createEventTag(req: Request) async throws -> AdministrationEventTagCatalogueResponse {
		_ = try await requireAdministrator(req)
		let request = try req.content.decode(AdministrationEventTagRequest.self)
		try await req.db.transaction { database in
			let section = try await eventTagSection(id: request.sectionID, on: database)
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
		}
		return try await eventTagCatalogue(on: req.db)
	}

	private func createEventTagSection(req: Request) async throws -> AdministrationEventTagCatalogueResponse {
		_ = try await requireAdministrator(req)
		let request = try req.content.decode(AdministrationEventTagSectionCreateRequest.self)
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
		section.displayName = try validatedDisplayName(request.displayName)
		section.sortOrder = request.sortOrder
		section.isArchived = request.isArchived
		section.revision += 1
		try await section.update(on: req.db)
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
		entry.kind = request.kind; entry.label = request.label; entry.startDate = request.startDate.storageValue; entry.endDate = request.endDate?.storageValue
		try await entry.update(on: req.db); return try await calendar(req: req)
	}

	private func deleteCalendarEntry(req: Request) async throws -> [AdministrationCalendarEntryResponse] {
		_ = try await requireAdministrator(req)
		guard let id = req.parameters.get("entryID", as: UUID.self), let entry = try await SchoolCalendarEntry.find(id, on: req.db) else {
			throw Abort(.notFound)
		}
		try await entry.delete(on: req.db); return try await calendar(req: req)
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
		EventTag(
			sectionID: try section.requireID(),
			slug: try validatedSlug(request.slug),
			displayName: try validatedDisplayName(request.displayName),
			category: section.category,
			symbol: request.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
			colorHex: request.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
			sortOrder: request.sortOrder,
			isArchived: request.isArchived
		)
	}

	private func apply(_ request: AdministrationEventTagRequest, to tag: EventTag, section: EventTagSection) throws {
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
		let names = try normalizedAssociatedNames(aliases, displayName: tag.displayName)
		try await EventTagAssociatedName.query(on: database)
			.filter(\.$eventTag.$id == tag.requireID())
			.delete()
		for name in names {
			try await EventTagAssociatedName(
				eventTagID: tag.requireID(),
				displayName: name.displayName,
				normalizedName: name.normalizedName
			).create(on: database)
		}
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

private extension String {
	var nilIfEmpty: String? {
		isEmpty ? nil : self
	}
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
	let email: String?
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
		badges = user.profileBadges
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

private struct AdministrationUserRawData: Content {
	let account: AdministrationRawAccount
	let ownerTimetables: [OwnerTimetable]
	let createdTimetables: [CreatedTimetable]
	let receivedTimetableImports: [ReceivedTimetableImport]
	let receivedPassMirrors: [ReceivedPassMirror]
	let receivedNameOverrides: [ReceivedNameOverride]
	let devices: [AdministrationRawDevice]
	let calendarEvents: [CalendarEvent]
	let schoolNotificationDeliveries: [SchoolNotificationDelivery]
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
