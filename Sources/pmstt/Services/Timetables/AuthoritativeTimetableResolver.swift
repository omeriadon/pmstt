import Fluent
import Foundation
import Vapor

enum AuthoritativeTimetableSource {
	case owner(OwnerTimetable)
	case created(CreatedTimetable)

	var id: UUID {
		get throws { try modelID() }
	}

	var author: User {
		switch self { case let .owner(value): value.user; case let .created(value): value.author }
	}

	var sourceKind: SourceKind {
		switch self { case .owner: .accountOwner; case .created: .createdForThirdParty }
	}

	var title: String {
		switch self { case let .owner(value): "\(value.user.displayName)"; case let .created(value): value.subjectDisplayName }
	}

	var subjectsData: Data {
		switch self { case let .owner(value): value.subjectsData; case let .created(value): value.subjectsData }
	}

	var revision: Int {
		switch self { case let .owner(value): value.revision; case let .created(value): value.revision }
	}

	var isSearchable: Bool {
		switch self { case let .owner(value): value.isSearchable; case let .created(value): value.isSearchable }
	}

	var updatedAt: Date? {
		switch self { case let .owner(value): value.updatedAt; case let .created(value): value.updatedAt }
	}

	func subjects() throws -> [TimetableSubjectDTO] {
		guard subjectsData.count <= 1_048_576 else { throw AppError(.internalServerError, code: .internalServerError, reason: "Stored timetable data is too large.") }
		do {
			let values = try JSONDecoder().decode([TimetableSubjectDTO].self, from: subjectsData)
			guard values.count <= 250 else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Too many subjects.")) }
			return values
		} catch let error as AppError { throw error } catch {
			throw AppError(.internalServerError, code: .internalServerError, reason: "Stored timetable data is invalid.")
		}
	}

	func preview() throws -> SharedTimetablePreview {
		let values = try subjects()
		return try SharedTimetablePreview(id: id, title: title, authorAccountID: author.requireID(), authorDisplayName: author.displayName, sourceKind: sourceKind, revision: revision, updatedAt: updatedAt, subjectCount: values.count, weeklyLessonCount: values.reduce(0) { $0 + $1.slots.count }, isImportable: isSearchable)
	}

	private func modelID() throws -> UUID {
		switch self { case let .owner(value): try value.requireID(); case let .created(value): try value.requireID() }
	}
}

enum AuthoritativeTimetableResolution {
	case available(AuthoritativeTimetableSource)
	case privateSource(AuthoritativeTimetableSource)
	case missing
	case ambiguous
}

enum AuthoritativeTimetableResolver {
	struct SourceKey: Hashable {
		let id: UUID
		let sourceKind: SourceKind
	}

	static func resolveMany(ids: Set<UUID>, on database: any Database) async throws -> [SourceKey: AuthoritativeTimetableSource] {
		guard !ids.isEmpty else { return [:] }
		let owners = try await OwnerTimetable.query(on: database).filter(\.$id ~~ ids).with(\.$user).all()
		let created = try await CreatedTimetable.query(on: database).filter(\.$id ~~ ids).with(\.$author).all()
		var result: [SourceKey: AuthoritativeTimetableSource] = [:]
		for owner in owners {
			try result[SourceKey(id: owner.requireID(), sourceKind: .accountOwner)] = .owner(owner)
		}
		for value in created {
			try result[SourceKey(id: value.requireID(), sourceKind: .createdForThirdParty)] = .created(value)
		}
		return result
	}

	static func resolve(id: UUID, on database: any Database) async throws -> AuthoritativeTimetableResolution {
		let owner = try await OwnerTimetable.query(on: database).filter(\.$id == id).with(\.$user).first()
		let created = try await CreatedTimetable.query(on: database).filter(\.$id == id).with(\.$author).first()
		if owner != nil, created != nil {
			return .ambiguous
		}
		if let owner {
			return .available(.owner(owner))
		}
		if let created {
			return created.isSearchable ? .available(.created(created)) : .privateSource(.created(created))
		}
		return .missing
	}

	static func resolvePublic(id: UUID, on database: any Database) async throws -> AuthoritativeTimetableSource {
		guard case let .available(source) = try await resolve(id: id, on: database) else { throw Abort(.notFound) }
		return source
	}

	static func resolvePublic(locator: String, on database: any Database) async throws -> AuthoritativeTimetableSource {
		if let id = UUID(uuidString: locator) {
			return try await resolvePublic(id: id, on: database)
		}
		let alias = try await resolveAlias(locator: locator, on: database)
		return try await resolvePublic(id: alias.$ownerTimetable.id, on: database)
	}

	static func resolveForImport(id: UUID, userID: UUID, on database: any Database) async throws -> AuthoritativeTimetableSource {
		switch try await resolve(id: id, on: database) {
			case let .available(source):
				guard try source.author.requireID() != userID else { throw Abort(.notFound) }
				return source
			case .ambiguous: throw Abort(.conflict)
			case .privateSource, .missing: throw Abort(.notFound)
		}
	}

	static func resolveForImport(locator: String, userID: UUID, on database: any Database) async throws -> AuthoritativeTimetableSource {
		if let id = UUID(uuidString: locator) {
			return try await resolveForImport(id: id, userID: userID, on: database)
		}
		let alias = try await resolveAlias(locator: locator, on: database)
		return try await resolveForImport(id: alias.$ownerTimetable.id, userID: userID, on: database)
	}

	static func resolveForViewer(id: UUID, userID: UUID, on database: any Database) async throws -> AuthoritativeTimetableResolution {
		switch try await resolve(id: id, on: database) {
			case let .available(source): return .available(source)
			case let .privateSource(source):
				let isAuthor = try source.author.requireID() == userID
				let isImported = try await hasImport(userID: userID, id: id, kind: source.sourceKind, on: database)
				if isAuthor || isImported {
					return .available(source)
				}
				return .privateSource(source)
			case .missing, .ambiguous: return try await hasImport(userID: userID, id: id, kind: nil, on: database) ? .missing : resolve(id: id, on: database)
		}
	}

	static func resolveForViewer(locator: String, userID: UUID, on database: any Database) async throws -> AuthoritativeTimetableResolution {
		if let id = UUID(uuidString: locator) {
			return try await resolveForViewer(id: id, userID: userID, on: database)
		}
		let alias = try await resolveAlias(locator: locator, on: database)
		return try await resolveForViewer(id: alias.$ownerTimetable.id, userID: userID, on: database)
	}

	private static func resolveAlias(locator: String, on database: any Database) async throws -> TimetableShareAlias {
		let canonical: String
		do { canonical = try TimetableShareAliasValidator.validateAndCanonicalize(locator) }
		catch { throw Abort(.notFound) }
		guard let alias = try await TimetableShareAlias.query(on: database).filter(\.$alias == canonical).first() else {
			throw Abort(.notFound)
		}
		return alias
	}

	static func hasImport(userID: UUID, id: UUID, kind: SourceKind?, on database: any Database) async throws -> Bool {
		var query = ReceivedTimetableImport.query(on: database).filter(\.$user.$id == userID).filter(\.$timetableID == id).filter(\.$revokedAt == nil)
		if let kind {
			query = query.filter(\.$sourceKind == kind)
		}
		return try await query.first() != nil
	}
}
