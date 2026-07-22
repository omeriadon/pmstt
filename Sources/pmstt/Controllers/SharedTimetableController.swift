import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import Vapor

struct SharedTimetableController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		routes.get("share", ":locator", use: publicPreview)
		routes.get("sharedtimetable", ":locator", use: publicPreview)
		let protected = routes.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		protected.get("v1", "shared-timetables", ":locator", use: authenticatedPreview)
		protected.get("v1", "timetables", "owner", "share-alias", use: getAlias)
		protected.get("v1", "timetables", "owner", "share-alias", "availability", use: aliasAvailability)
		protected.put("v1", "timetables", "owner", "share-alias", use: putAlias)
		protected.delete("v1", "timetables", "owner", "share-alias", use: deleteAlias)
		protected.get("v1", "timetables", "received", "authoritative", use: list)
		protected.post("v1", "timetables", "received", "import", use: importTimetable)
		protected.delete("v1", "timetables", "received", "authoritative", ":importID", use: deleteImport)
	}

	func publicPreview(req: Request) async throws -> Response {
		let key = req.remoteAddress?.ipAddress ?? "unknown"
		guard await SharedTimetableRateLimiter.shared.allow(key: "public:\(key)", limit: 120, window: 60) else {
			throw AppError(.tooManyRequests, code: .rateLimited, reason: "Too many timetable preview requests.")
		}
		let locator = try requireLocator(req)
		let source = try await AuthoritativeTimetableResolver.resolvePublic(locator: locator, on: req.db)
		let preview = try source.preview()
		if req.headers.first(name: .accept)?.contains("text/html") == true {
			return Self.browserFallback(locator: locator)
		}
		let response = Response(status: .ok)
		try response.content.encode(preview)
		response.headers.cacheControl = .init(isPublic: true, maxAge: 30)
		return response
	}

	func authenticatedPreview(req: Request) async throws -> SharedTimetablePreview {
		let payload = try req.auth.require(UserPayload.self)
		guard case let .available(source) = try await AuthoritativeTimetableResolver.resolveForViewer(locator: requireLocator(req), userID: payload.sub, on: req.db) else { throw Abort(.notFound) }
		return try source.preview()
	}

	func importTimetable(req: Request) async throws -> Response {
		let payload = try req.auth.require(UserPayload.self)
		let key = "\(payload.sub.uuidString):\(req.remoteAddress?.ipAddress ?? "unknown")"
		guard await SharedTimetableRateLimiter.shared.allow(key: key, limit: 30, window: 60) else {
			throw AppError(.tooManyRequests, code: .rateLimited, reason: "Too many timetable imports.")
		}
		let declaredLength = req.headers.first(name: "Content-Length").flatMap(Int.init)
		let actualLength = req.body.data?.readableBytes ?? 0
		if declaredLength.map({ $0 > 64 * 1024 }) == true || actualLength > 64 * 1024 {
			throw AppError(.badRequest, code: .invalidRequest, reason: "The import body is too large.")
		}

		let body: ReceivedTimetableImportRequest
		do { body = try req.content.decode(ReceivedTimetableImportRequest.self) }
		catch { throw AppError(.badRequest, code: .invalidRequest, reason: "The import body must contain exactly one timetable locator.", field: "timetableLocator") }

		let result: (AuthoritativeTimetableSource, ReceivedTimetableImport, Bool)
		do {
			result = try await req.db.transaction { database in
				let source = try await AuthoritativeTimetableResolver.resolveForImport(locator: body.locator, userID: payload.sub, on: database)
				let timetableID = try source.id
				if let existing = try await ReceivedTimetableImport.query(on: database)
					.filter(\.$user.$id == payload.sub).filter(\.$timetableID == timetableID).filter(\.$sourceKind == source.sourceKind).first()
				{
					if existing.revokedAt != nil {
						existing.revokedAt = nil; try await existing.save(on: database)
					}
					return (source, existing, false)
				}
				let relationship = ReceivedTimetableImport(userID: payload.sub, timetableID: timetableID, sourceKind: source.sourceKind)
				try await relationship.save(on: database)
				return (source, relationship, true)
			}
		} catch where isUniqueConstraintViolation(error) {
			// The database unique key is the race arbiter. Recovery must use the
			// complete relationship identity, including sourceKind.
			let source = try await AuthoritativeTimetableResolver.resolveForImport(locator: body.locator, userID: payload.sub, on: req.db)
			let timetableID = try source.id
			guard let relationship = try await ReceivedTimetableImport.query(on: req.db)
				.filter(\.$user.$id == payload.sub)
				.filter(\.$timetableID == timetableID)
				.filter(\.$sourceKind == source.sourceKind)
				.first()
			else { throw Abort(.conflict) }
			if relationship.revokedAt != nil {
				relationship.revokedAt = nil
				try await relationship.save(on: req.db)
			}
			result = (source, relationship, false)
		}

		let response = try ReceivedTimetableImportResponse(importID: result.1.requireID(), id: result.0.id, title: result.0.title, authorAccountID: result.0.author.requireID(), authorDisplayName: result.0.author.displayName, sourceKind: result.0.sourceKind, revision: result.0.revision, updatedAt: result.0.updatedAt, importedAt: result.1.importedAt, availability: .available)
		let responseValue = Response(status: result.2 ? .created : .ok)
		try responseValue.content.encode(response)
		return responseValue
	}

	func list(req: Request) async throws -> Response {
		let payload = try req.auth.require(UserPayload.self)
		let limit = try boundedQueryValue(req, name: "limit", default: 25, minimum: 1, maximum: 50)
		let offset = try boundedQueryValue(req, name: "offset", default: 0, minimum: 0, maximum: 100_000)
		let imports = try await ReceivedTimetableImport.query(on: req.db)
			.filter(\.$user.$id == payload.sub).filter(\.$revokedAt == nil)
			.sort(\.$importedAt, .ascending).sort(\.$id, .ascending)
			.range(offset ..< (offset + limit + 1)).all()
		let hasNextPage = imports.count > limit
		let page = hasNextPage ? Array(imports.prefix(limit)) : imports
		let sources = try await AuthoritativeTimetableResolver.resolveMany(ids: Set(page.map(\.timetableID)), on: req.db)
		var result: [AuthoritativeReceivedTimetableDTO] = []
		for relationship in page {
			guard let source = sources[.init(id: relationship.timetableID, sourceKind: relationship.sourceKind)] else { try result.append(tombstone(for: relationship)); continue }
			try result.append(AuthoritativeReceivedTimetableDTO(importID: relationship.requireID(), id: relationship.timetableID, title: source.title, authorAccountID: source.author.requireID(), authorDisplayName: source.author.displayName, sourceKind: source.sourceKind, subjects: source.subjects(), revision: source.revision, updatedAt: source.updatedAt, importedAt: relationship.importedAt, availability: .available))
		}
		let response = Response(status: .ok)
		if hasNextPage {
			response.headers.replaceOrAdd(name: "X-Next-Offset", value: String(offset + limit))
		}
		response.headers.replaceOrAdd(name: "X-Page-Limit", value: String(limit))
		try response.content.encode(result)
		return response
	}

	func deleteImport(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		guard let importID = req.parameters.get("importID").flatMap(UUID.init(uuidString:)) else { throw Abort(.notFound) }
		if let relationship = try await ReceivedTimetableImport.query(on: req.db)
			.filter(\.$id == importID).filter(\.$user.$id == payload.sub).filter(\.$revokedAt == nil).first()
		{
			relationship.revokedAt = Date()
			try await relationship.save(on: req.db)
		}
		return .noContent
	}

	private func boundedQueryValue(_ req: Request, name: String, default defaultValue: Int, minimum: Int, maximum: Int) throws -> Int {
		let value = req.query[Int.self, at: name] ?? defaultValue
		guard value >= minimum, value <= maximum else { throw AppError(.badRequest, code: .invalidRequest, reason: "The \(name) query value is out of bounds.") }
		return value
	}

	private func requireLocator(_ req: Request) throws -> String {
		guard let value = req.parameters.get("locator"), !value.isEmpty, value.utf8.count <= 64 else { throw Abort(.notFound) }
		return value
	}

	func getAlias(req: Request) async throws -> TimetableShareAliasResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let owner = try await OwnerTimetable.query(on: req.db).filter(\.$user.$id == payload.sub).first() else { return .init(alias: nil, timetableID: nil, url: nil) }
		guard let alias = try await TimetableShareAlias.query(on: req.db).filter(\.$ownerTimetable.$id == owner.requireID()).first() else { return .init(alias: nil, timetableID: owner.id, url: nil) }
		return .init(alias: alias.alias, timetableID: owner.id, url: Self.shareURL(for: alias.alias))
	}

	func aliasAvailability(req: Request) async throws -> TimetableShareAliasAvailabilityResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let raw = req.query[String.self, at: "alias"], raw.utf8.count <= 128 else { throw AppError(.badRequest, code: .invalidRequest, reason: "The alias query value is out of bounds.", field: "alias") }
		let normalized = TimetableShareAliasValidator.canonicalize(raw)
		if let validation = TimetableShareAliasValidator.validate(normalized) {
			return .init(normalizedAlias: normalized, isValid: false, isAvailable: false, isOwnedByCurrentUser: false, reason: .init(rawValue: validation.reason.rawValue))
		}
		let ownerID = try await OwnerTimetable.query(on: req.db).filter(\.$user.$id == payload.sub).first()?.requireID()
		let match = try await TimetableShareAlias.query(on: req.db).filter(\.$alias == normalized).with(\.$ownerTimetable).first()
		let owned = match?.$ownerTimetable.id == ownerID
		return .init(normalizedAlias: normalized, isValid: true, isAvailable: match == nil || owned, isOwnedByCurrentUser: owned, reason: match == nil || owned ? nil : .taken)
	}

	func putAlias(req: Request) async throws -> TimetableShareAliasResponse {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(TimetableShareAliasUpdateRequest.self)
		let canonical: String
		do { canonical = try TimetableShareAliasValidator.validateAndCanonicalize(body.alias) }
		catch let error as TimetableShareAliasValidationError { throw AppError(.badRequest, code: .invalidRequest, reason: error.reason.rawValue, field: "alias") }
		guard let owner = try await OwnerTimetable.query(on: req.db).filter(\.$user.$id == payload.sub).first() else { throw AppError(.notFound, code: .accountNotFound, reason: "Create your owner timetable before choosing a custom link.") }
		let ownerID = try owner.requireID()
		do {
			if let existing = try await TimetableShareAlias.query(on: req.db).filter(\.$ownerTimetable.$id == ownerID).first() {
				if existing.alias != canonical {
					existing.alias = canonical; try await existing.save(on: req.db)
				}
			} else {
				try await TimetableShareAlias(alias: canonical, ownerTimetableID: ownerID).save(on: req.db)
			}
		} catch where isUniqueConstraintViolation(error) {
			throw AppError(.conflict, code: .aliasTaken, reason: "That link is already taken.", field: "alias")
		}
		return .init(alias: canonical, timetableID: ownerID, url: Self.shareURL(for: canonical))
	}

	func deleteAlias(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		guard let owner = try await OwnerTimetable.query(on: req.db).filter(\.$user.$id == payload.sub).first() else { return .noContent }
		try await TimetableShareAlias.query(on: req.db).filter(\.$ownerTimetable.$id == owner.requireID()).delete()
		return .noContent
	}

	private static func shareURL(for alias: String) -> String {
		"https://timetable.adonis.pt/share/\(alias)"
	}

	private static func browserFallback(locator: String) -> Response {
		let response = Response(status: .found)
		response.headers.replaceOrAdd(name: .location, value: "timetable://share/\(locator)")
		response.headers.cacheControl = .init(isPublic: true, maxAge: 30)
		return response
	}

	private func tombstone(for relationship: ReceivedTimetableImport) throws -> AuthoritativeReceivedTimetableDTO {
		try AuthoritativeReceivedTimetableDTO(importID: relationship.requireID(), id: relationship.timetableID, title: nil, authorAccountID: nil, authorDisplayName: nil, sourceKind: relationship.sourceKind, subjects: [], revision: nil, updatedAt: nil, importedAt: relationship.importedAt, availability: .deleted)
	}
}

private func isUniqueConstraintViolation(_ error: any Error) -> Bool {
	if let sqlite = error as? SQLiteError {
		return sqlite.reason == .constraintUniqueFailed
	}
	if let postgres = error as? PostgresError {
		return postgres.code == .uniqueViolation
	}
	if let postgres = error as? PSQLError, case .server = postgres.code {
		return postgres.serverInfo?[.sqlState].map { $0 == "23505" } ?? false
	}
	return false
}

private actor SharedTimetableRateLimiter {
	static let shared = SharedTimetableRateLimiter(maxKeys: 10000)
	private struct Bucket {
		var attempts: [Date]
		var lastSeen: Date
	}

	private let maxKeys: Int
	private var buckets: [String: Bucket] = [:]

	init(maxKeys: Int) {
		self.maxKeys = maxKeys
	}

	func allow(key: String, limit: Int, window: TimeInterval, now: Date = .now) -> Bool {
		let cutoff = now.addingTimeInterval(-window)
		let recent = (buckets[key]?.attempts ?? []).filter { $0 > cutoff }
		guard recent.count < limit else {
			buckets[key] = Bucket(attempts: recent, lastSeen: now)
			return false
		}
		buckets[key] = Bucket(attempts: recent + [now], lastSeen: now)
		if buckets.count > maxKeys {
			let stale = buckets.filter { $0.value.attempts.allSatisfy { $0 <= cutoff } }.keys
			for key in stale {
				buckets.removeValue(forKey: key)
			}
			while buckets.count > maxKeys, let oldest = buckets.min(by: { $0.value.lastSeen < $1.value.lastSeen })?.key {
				buckets.removeValue(forKey: oldest)
			}
		}
		return true
	}
}
