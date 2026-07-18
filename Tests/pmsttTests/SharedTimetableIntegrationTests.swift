import Crypto
import Fluent
import FluentSQLiteDriver
import JWT
@testable import pmstt
import Vapor
import XCTest
import XCTVapor

final class SharedTimetableIntegrationTests: XCTestCase, @unchecked Sendable {
	func testSearchablePreviewIsBoundedAndMalformedUUIDIsIndistinguishable() async throws {
		let (app, owner, timetable) = try await makeFixture(platform: .iOS)

		let preview = try await request(app, .GET, "/sharedtimetable/\(timetable.id!.uuidString)")
		XCTAssertEqual(preview.status, .ok)
		let decoded = try preview.content.decode(SharedTimetablePreview.self)
		XCTAssertEqual(decoded.authorAccountID, owner.user.id)
		XCTAssertTrue(decoded.isImportable)
		var previewBody = preview.body
		XCTAssertFalse(previewBody.readString(length: previewBody.readableBytes)?.contains("subjectsData") ?? true)

		let malformed = try await request(app, .GET, "/sharedtimetable/not-a-uuid")
		XCTAssertEqual(malformed.status, .notFound)
	}

	func testShareAliasClaimPreviewImportAndDelete() async throws {
		let (app, owner, timetable) = try await makeFixture(platform: .iOS)
		let claim = try await request(app, .PUT, "/v1/timetables/owner/share-alias", token: owner.accessToken, body: TimetableShareAliasUpdateRequest(alias: "Adon-Home"))
		XCTAssertEqual(claim.status, .ok)
		XCTAssertEqual(try claim.content.decode(TimetableShareAliasResponse.self).alias, "adon-home")
		let preview = try await request(app, .GET, "/sharedtimetable/adon-home")
		XCTAssertEqual(preview.status, .ok)
		let importer = try await register(app, platform: .iOS)
		let imported = try await request(app, .POST, "/v1/timetables/received/import", token: importer.accessToken, body: ReceivedTimetableImportRequest(timetableLocator: "ADON-HOME"))
		XCTAssertEqual(imported.status, .created)
		XCTAssertEqual(try imported.content.decode(ReceivedTimetableImportResponse.self).id, timetable.id)
		let importerOwner = try OwnerTimetable(userID: importer.user.id, subjectsData: JSONEncoder().encode([TimetableSubjectDTO]()), revision: 1)
		try await importerOwner.save(on: app.db(.sqlite))
		let taken = try await request(app, .PUT, "/v1/timetables/owner/share-alias", token: importer.accessToken, body: TimetableShareAliasUpdateRequest(alias: "adon-home"))
		XCTAssertEqual(taken.status, .conflict)
		let removed = try await request(app, .DELETE, "/v1/timetables/owner/share-alias", token: owner.accessToken)
		XCTAssertEqual(removed.status, .noContent)
		let oldPreview = try await request(app, .GET, "/sharedtimetable/adon-home")
		XCTAssertEqual(oldPreview.status, .notFound)
	}

	func testShareAliasValidatorBoundariesAndReservedNames() {
		XCTAssertEqual(TimetableShareAliasValidator.validate("ab")?.reason, .tooShort)
		XCTAssertEqual(TimetableShareAliasValidator.validate(String(repeating: "a", count: 31))?.reason, .tooLong)
		XCTAssertEqual(TimetableShareAliasValidator.validate("-abc")?.reason, .leadingSeparator)
		XCTAssertEqual(TimetableShareAliasValidator.validate("abc-")?.reason, .trailingSeparator)
		XCTAssertEqual(TimetableShareAliasValidator.validate("a--b")?.reason, .consecutiveSeparators)
		XCTAssertEqual(TimetableShareAliasValidator.validate("health")?.reason, .reserved)
		XCTAssertEqual(TimetableShareAliasValidator.validate(UUID().uuidString)?.reason, .uuidShaped)
		XCTAssertEqual(TimetableShareAliasValidator.validate("ab c")?.reason, .invalidCharacter)
		XCTAssertNil(TimetableShareAliasValidator.validate("Ado_n-7"))
	}

	func testImportIsStrictSelfPrivateAndNonAuthoritative() async throws {
		let (app, owner, timetable) = try await makeFixture(platform: .iOS)
		let selfImport = try await request(app, .POST, "/v1/timetables/received/import", token: owner.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(timetable.id)))
		XCTAssertEqual(selfImport.status, .notFound)

		timetable.isSearchable = false
		try await timetable.save(on: app.db(.sqlite))
		let privatePreview = try await request(app, .GET, "/sharedtimetable/\(timetable.id!.uuidString)")
		XCTAssertEqual(privatePreview.status, .notFound)

		let ipad = try await register(app, platform: .iPadOS)
		let forged = ForgedImportBody(timetableID: UUID(), sourceKind: .accountOwner, title: "forged")
		let strict = try await request(app, .POST, "/v1/timetables/received/import", token: ipad.accessToken, body: forged)
		XCTAssertEqual(strict.status, .forbidden)

		let author = try await register(app, platform: .iOS)
		let publicSource = try await makePublicSource(app: app, authorID: author.user.id)
		let ipadImport = try await request(app, .POST, "/v1/timetables/received/import", token: ipad.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(publicSource.id)))
		XCTAssertEqual(ipadImport.status, .forbidden)
	}

	func testImportRejectsForgedFieldsAndIsIdempotent() async throws {
		let (app, owner, _) = try await makeFixture(platform: .iOS)
		let author = try await register(app, platform: .iOS)
		let source = try await makePublicSource(app: app, authorID: author.user.id)
		let forged = try ForgedImportBody(timetableID: XCTUnwrap(source.id), sourceKind: .accountOwner, title: "forged")
		let rejected = try await request(app, .POST, "/v1/timetables/received/import", token: owner.accessToken, body: forged)
		XCTAssertEqual(rejected.status, .badRequest)

		let first = try await request(app, .POST, "/v1/timetables/received/import", token: owner.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(source.id)))
		let second = try await request(app, .POST, "/v1/timetables/received/import", token: owner.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(source.id)))
		XCTAssertEqual(first.status, .created)
		XCTAssertEqual(second.status, .ok)
		let importCount = try await ReceivedTimetableImport.query(on: app.db(.sqlite)).count()
		XCTAssertEqual(importCount, 1)
	}

	func testAuthoredSourceIsImportedByAuthoritativeClient() async throws {
		let (app, importer, _) = try await makeFixture(platform: .iOS)
		let author = try await register(app, platform: .iOS)
		let source = try AuthoredTimetable(authorUserID: author.user.id, subjectDisplayName: "Shared", passSerialNumber: UUID().uuidString, subjectsData: JSONEncoder().encode([TimetableSubjectDTO]()), revision: 3)
		try await source.save(on: app.db(.sqlite))
		let response = try await request(app, .POST, "/v1/timetables/received/import", token: importer.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(source.id)))
		XCTAssertEqual(response.status, .created)
		let decoded = try response.content.decode(ReceivedTimetableImportResponse.self)
		XCTAssertEqual(decoded.sourceKind, .authoredForThirdParty)
	}

	func testAmbiguousUUIDIsRejectedWithoutChoosingASourceNamespace() async throws {
		let (app, importer, timetable) = try await makeFixture(platform: .iOS)
		let author = try await register(app, platform: .iOS)
		let duplicate = try AuthoredTimetable(id: XCTUnwrap(timetable.id), authorUserID: author.user.id, subjectDisplayName: "Ambiguous", passSerialNumber: UUID().uuidString, subjectsData: JSONEncoder().encode([TimetableSubjectDTO]()), revision: 1)
		try await duplicate.save(on: app.db(.sqlite))
		let response = try await request(app, .POST, "/v1/timetables/received/import", token: importer.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(timetable.id)))
		XCTAssertEqual(response.status, .conflict)
		let importCount = try await ReceivedTimetableImport.query(on: app.db(.sqlite)).count()
		XCTAssertEqual(importCount, 0)
	}

	func testOnlyIOSMayMutateAndOtherRegisteredPlatformsAreForbidden() async throws {
		let (app, importer, _) = try await makeFixture(platform: .iOS)
		let author = try await register(app, platform: .iOS)
		let source = try await makePublicSource(app: app, authorID: author.user.id)
		let allowed = try await request(app, .POST, "/v1/timetables/received/import", token: importer.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(source.id)))
		XCTAssertEqual(allowed.status, .created)
		for platform in [ClientPlatform.iPadOS, .macOS] {
			let client = try await register(app, platform: platform)
			let forbidden = try await request(app, .DELETE, "/v1/timetables/received/authoritative/\(source.id!.uuidString)", token: client.accessToken)
			XCTAssertEqual(forbidden.status, .forbidden)
		}
	}

	func testPrivateSourceRemainsReadableToImporterAfterAuthorRevokesSearchability() async throws {
		let (app, importer, _) = try await makeFixture(platform: .iOS)
		let author = try await register(app, platform: .iOS)
		let source = try await makePublicSource(app: app, authorID: author.user.id)
		let imported = try await request(app, .POST, "/v1/timetables/received/import", token: importer.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(source.id)))
		XCTAssertEqual(imported.status, .created)
		source.isSearchable = false
		try await source.save(on: app.db(.sqlite))
		let read = try await request(app, .GET, "/v1/shared-timetables/\(source.id!.uuidString)", token: importer.accessToken)
		XCTAssertEqual(read.status, .ok)
	}

	func testDeleteIsIdempotentAndReimportReactivatesExactRelationship() async throws {
		let (app, importer, _) = try await makeFixture(platform: .iOS)
		let author = try await register(app, platform: .iOS)
		let source = try await makePublicSource(app: app, authorID: author.user.id)
		_ = try await request(app, .POST, "/v1/timetables/received/import", token: importer.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(source.id)))
		let relationshipValue = try await ReceivedTimetableImport.query(on: app.db(.sqlite)).first()
		let relationship = try XCTUnwrap(relationshipValue)
		let firstDelete = try await request(app, .DELETE, "/v1/timetables/received/authoritative/\(relationship.id!.uuidString)", token: importer.accessToken)
		let secondDelete = try await request(app, .DELETE, "/v1/timetables/received/authoritative/\(relationship.id!.uuidString)", token: importer.accessToken)
		XCTAssertEqual(firstDelete.status, .noContent)
		XCTAssertEqual(secondDelete.status, .noContent)
		let reimport = try await request(app, .POST, "/v1/timetables/received/import", token: importer.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(source.id)))
		XCTAssertEqual(reimport.status, .ok)
		let importCount = try await ReceivedTimetableImport.query(on: app.db(.sqlite)).count()
		XCTAssertEqual(importCount, 1)
	}

	func testDeleteRevokesOnlyTheRelationshipNamedByImportIDAcrossUUIDNamespaces() async throws {
		let (app, importer, timetable) = try await makeFixture(platform: .iOS)
		let authored = try AuthoredTimetable(id: XCTUnwrap(timetable.id), authorUserID: importer.user.id, subjectDisplayName: "Collision", passSerialNumber: UUID().uuidString, subjectsData: JSONEncoder().encode([TimetableSubjectDTO]()), revision: 1)
		try await authored.save(on: app.db(.sqlite))
		let ownerImport = try ReceivedTimetableImport(userID: importer.user.id, timetableID: XCTUnwrap(timetable.id), sourceKind: .accountOwner)
		let authoredImport = try ReceivedTimetableImport(userID: importer.user.id, timetableID: XCTUnwrap(timetable.id), sourceKind: .authoredForThirdParty)
		try await ownerImport.save(on: app.db(.sqlite)); try await authoredImport.save(on: app.db(.sqlite))
		_ = try await request(app, .DELETE, "/v1/timetables/received/authoritative/\(ownerImport.id!.uuidString)", token: importer.accessToken)
		let ownerAfterValue = try await ReceivedTimetableImport.find(XCTUnwrap(ownerImport.id), on: app.db(.sqlite))
		let authoredAfterValue = try await ReceivedTimetableImport.find(XCTUnwrap(authoredImport.id), on: app.db(.sqlite))
		let ownerAfter = try XCTUnwrap(ownerAfterValue)
		let authoredAfter = try XCTUnwrap(authoredAfterValue)
		XCTAssertNotNil(ownerAfter.revokedAt)
		XCTAssertNil(authoredAfter.revokedAt)
	}

	func testAuthoritativeListIsBoundedAndPaginated() async throws {
		let (app, importer, _) = try await makeFixture(platform: .iOS)
		for index in 0 ..< 51 {
			let relationship = ReceivedTimetableImport(userID: importer.user.id, timetableID: UUID(), sourceKind: .accountOwner, importedAt: Date(timeIntervalSince1970: Double(index)))
			try await relationship.save(on: app.db(.sqlite))
		}
		let first = try await request(app, .GET, "/v1/timetables/received/authoritative?limit=50", token: importer.accessToken)
		XCTAssertEqual(first.status, .ok)
		XCTAssertEqual(try first.content.decode([AuthoritativeReceivedTimetableDTO].self).count, 50)
		XCTAssertEqual(first.headers.first(name: "X-Next-Offset"), "50")
		let second = try await request(app, .GET, "/v1/timetables/received/authoritative?limit=50&offset=50", token: importer.accessToken)
		XCTAssertEqual(try second.content.decode([AuthoritativeReceivedTimetableDTO].self).count, 1)
		XCTAssertNil(second.headers.first(name: "X-Next-Offset"))
		let rejected = try await request(app, .GET, "/v1/timetables/received/authoritative?limit=51", token: importer.accessToken)
		XCTAssertEqual(rejected.status, .badRequest)
		let zeroLimit = try await request(app, .GET, "/v1/timetables/received/authoritative?limit=0", token: importer.accessToken)
		XCTAssertEqual(zeroLimit.status, .badRequest)
	}

	func testMalformedStoredJSONFailsClosedInsteadOfServingPartialData() async throws {
		let (app, importer, _) = try await makeFixture(platform: .iOS)
		let author = try await register(app, platform: .iOS)
		let source = try await makePublicSource(app: app, authorID: author.user.id)
		_ = try await request(app, .POST, "/v1/timetables/received/import", token: importer.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(source.id)))
		source.subjectsData = Data("not-json".utf8)
		try await source.save(on: app.db(.sqlite))
		let response = try await request(app, .GET, "/v1/timetables/received/authoritative", token: importer.accessToken)
		XCTAssertEqual(response.status, .internalServerError)
	}

	func testRawUnknownKeyAndChunkedOversizedImportBodiesAreRejected() async throws {
		let (app, owner, _) = try await makeFixture(platform: .iOS)
		let unknown = Data("{\"timetableID\":\"\(UUID().uuidString)\",\"extra\":true}".utf8)
		let unknownResponse = try await rawRequest(app, .POST, "/v1/timetables/received/import", token: owner.accessToken, body: unknown)
		XCTAssertEqual(unknownResponse.status, .badRequest)
		let oversized = Data(repeating: 0x20, count: 64 * 1024 + 1)
		let oversizedResponse = try await rawRequest(app, .POST, "/v1/timetables/received/import", token: owner.accessToken, body: oversized, omitContentLength: true)
		XCTAssertEqual(oversizedResponse.status, .badRequest)
	}

	func testUniqueConstraintDefinesDeterministicDuplicateSemantics_PostgreSQLConcurrencyBoundary() async throws {
		let (app, importer, _) = try await makeFixture(platform: .iOS)
		let author = try await register(app, platform: .iOS)
		let source = try await makePublicSource(app: app, authorID: author.user.id)
		let first = try ReceivedTimetableImport(userID: importer.user.id, timetableID: XCTUnwrap(source.id), sourceKind: .accountOwner)
		try await first.save(on: app.db(.sqlite))
		let duplicate = try ReceivedTimetableImport(userID: importer.user.id, timetableID: XCTUnwrap(source.id), sourceKind: .accountOwner)
		var duplicateFailed = false
		do { try await duplicate.save(on: app.db(.sqlite)) } catch { duplicateFailed = true }
		XCTAssertTrue(duplicateFailed)
		let importCount = try await ReceivedTimetableImport.query(on: app.db(.sqlite)).count()
		XCTAssertEqual(importCount, 1)
		// This is intentionally sequential on SQLite. PostgreSQL concurrency is
		// covered by the database unique index and the import recovery path.
	}

	func testBackfillIsResolvedOrSkippedAndDoesNotMutateWalletMirror() async throws {
		let (app, owner, _) = try await makeFixture(platform: .iOS)
		guard let ownerRecord = try await User.find(owner.user.id, on: app.db(.sqlite)) else { XCTFail("owner missing"); return }
		let mirror = ReceivedPassMirror(userID: owner.user.id, passSerialNumber: ownerRecord.selfPassSerialNumber, issuerAccountID: owner.user.id.uuidString, sourceKind: .accountOwner, signedDisplayName: "Signed", authorDisplayName: "Author", subjectsData: Data("wallet".utf8), walletRevision: 7, receivedAt: Date(timeIntervalSince1970: 10), passUpdatedAt: Date(timeIntervalSince1970: 11), contentRevision: 9)
		try await mirror.save(on: app.db(.sqlite))
		let unresolved = ReceivedPassMirror(userID: owner.user.id, passSerialNumber: "missing", issuerAccountID: UUID().uuidString, sourceKind: .accountOwner, signedDisplayName: "Unchanged", subjectsData: Data("raw".utf8), walletRevision: 8, receivedAt: .now, passUpdatedAt: .now, contentRevision: 10)
		try await unresolved.save(on: app.db(.sqlite))
		let deletedAuthor = try await register(app, platform: .iOS)
		_ = try await makePublicSource(app: app, authorID: deletedAuthor.user.id)
		guard let deletedAuthorRecord = try await User.find(deletedAuthor.user.id, on: app.db(.sqlite)) else { XCTFail("deleted author missing"); return }
		let deleted = ReceivedPassMirror(userID: owner.user.id, passSerialNumber: deletedAuthorRecord.selfPassSerialNumber, issuerAccountID: deletedAuthor.user.id.uuidString, sourceKind: .accountOwner, signedDisplayName: "Deleted", subjectsData: Data("deleted".utf8), isDeleted: true, walletRevision: 9, receivedAt: .now, passUpdatedAt: .now, contentRevision: 11)
		try await deleted.save(on: app.db(.sqlite))
		let beforeDisplayName = mirror.signedDisplayName
		let beforeSubjects = mirror.subjectsData
		let beforeWalletRevision = mirror.walletRevision
		let beforeContentRevision = mirror.contentRevision
		try await BackfillReceivedTimetableImports().prepare(on: app.db(.sqlite))
		let importCount = try await ReceivedTimetableImport.query(on: app.db(.sqlite)).count()
		XCTAssertEqual(importCount, 1)
		let afterValue = try await ReceivedPassMirror.find(XCTUnwrap(mirror.id), on: app.db(.sqlite))
		let after = try XCTUnwrap(afterValue)
		XCTAssertEqual(after.signedDisplayName, beforeDisplayName)
		XCTAssertEqual(after.subjectsData, beforeSubjects)
		XCTAssertEqual(after.walletRevision, beforeWalletRevision)
		XCTAssertEqual(after.contentRevision, beforeContentRevision)
	}

	func testDeletingUserCascadesReceivedImportRelationships() async throws {
		let (app, importer, _) = try await makeFixture(platform: .iOS)
		let author = try await register(app, platform: .iOS)
		let source = try await makePublicSource(app: app, authorID: author.user.id)
		_ = try await request(app, .POST, "/v1/timetables/received/import", token: importer.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(source.id)))
		guard let importedUser = try await User.find(importer.user.id, on: app.db(.sqlite)) else { XCTFail("importer missing"); return }
		try await importedUser.delete(on: app.db(.sqlite))
		let importCount = try await ReceivedTimetableImport.query(on: app.db(.sqlite)).count()
		XCTAssertEqual(importCount, 0)
	}

	func testAuthoritativeFetchUsesCurrentSubjectsAndReturnsDeletedTombstone() async throws {
		let (app, importer, _) = try await makeFixture(platform: .iOS)
		let author = try await register(app, platform: .iOS)
		let source = try await makePublicSource(app: app, authorID: author.user.id)
		let imported = try await request(app, .POST, "/v1/timetables/received/import", token: importer.accessToken, body: ReceivedTimetableImportRequest(timetableID: XCTUnwrap(source.id)))
		XCTAssertEqual(imported.status, .created)

		source.revision = 2
		source.subjectsData = try JSONEncoder().encode([TimetableSubjectDTO(id: "current", symbol: "Current", colour: .init(r: 1, g: 0, b: 0, a: 1), slots: [], classroom: .unknown(rawLocation: "Room"), teacher: .unknown(rawNotes: "Teacher"))])
		try await source.save(on: app.db(.sqlite))
		let current = try await request(app, .GET, "/v1/timetables/received/authoritative", token: importer.accessToken)
		let rows = try current.content.decode([AuthoritativeReceivedTimetableDTO].self)
		XCTAssertEqual(rows.first?.revision, 2)
		XCTAssertEqual(rows.first?.subjects.first?.id, "current")

		try await source.delete(on: app.db(.sqlite))
		let tombstone = try await request(app, .GET, "/v1/timetables/received/authoritative", token: importer.accessToken)
		let deleted = try tombstone.content.decode([AuthoritativeReceivedTimetableDTO].self)
		XCTAssertEqual(deleted.first?.availability, .deleted)
		XCTAssertTrue(deleted.first?.subjects.isEmpty ?? false)
	}

	private func makeFixture(platform: ClientPlatform) async throws -> (Application, TokenResponse, OwnerTimetable) {
		let app = try await makeApplication()
		let owner = try await register(app, platform: platform)
		let timetable = try OwnerTimetable(userID: owner.user.id, subjectsData: JSONEncoder().encode([TimetableSubjectDTO]()), revision: 1, isSearchable: true)
		try await timetable.save(on: app.db(.sqlite))
		return (app, owner, timetable)
	}

	private func makePublicSource(app: Application, authorID: UUID) async throws -> OwnerTimetable {
		let source = try OwnerTimetable(userID: authorID, subjectsData: JSONEncoder().encode([TimetableSubjectDTO]()), revision: 1, isSearchable: true)
		try await source.save(on: app.db(.sqlite))
		return source
	}

	private func makeApplication() async throws -> Application {
		let app = try await Application.make(.testing)
		addTeardownBlock { try await app.asyncShutdown() }
		await AuthRateLimiter.shared.reset()
		app.databases.use(.sqlite(.memory), as: .sqlite)
		await app.jwt.keys.add(hmac: HMACKey(from: "test-session-secret"), digestAlgorithm: .sha256)
		app.migrations.add(sqliteMigrations())
		try routes(app)
		try await app.migrator.setupIfNeeded().flatMap { app.migrator.prepareBatch() }.get()
		return app
	}

	private func sqliteMigrations() -> [any Migration] {
		pmsttMigrationList().map { migration in
			if migration is AddUserTokenClientIdentity {
				return SQLiteClientIdentityMigration()
			}
			if migration is AddAppleAccountState {
				return SQLiteAppleStateMigration()
			}
			return migration
		}
	}

	private func register(_ app: Application, platform: ClientPlatform) async throws -> TokenResponse {
		let email = "\(UUID())@example.com"
		let installationID = UUID().uuidString
		if platform == .iOS {
			let response = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: email, password: "password", displayName: "User", platform: platform.rawValue, installationID: installationID))
			return try response.content.decode(TokenResponse.self)
		}
		_ = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: email, password: "password", displayName: "User", platform: "iOS", installationID: "iphone-\(installationID)"))
		let response = try await request(app, .POST, "/v1/auth/login", body: LoginRequest(email: email, password: "password", platform: platform.rawValue, installationID: installationID))
		return try response.content.decode(TokenResponse.self)
	}

	private func request(_ app: Application, _ method: HTTPMethod, _ path: String, token: String? = nil) async throws -> XCTHTTPResponse {
		try await request(app, method, path, token: token, body: EmptyBody())
	}

	private func request(_ app: Application, _ method: HTTPMethod, _ path: String, token: String? = nil, body: (some Content)? = nil) async throws -> XCTHTTPResponse {
		var result: XCTHTTPResponse?
		try await app.test(method, path, beforeRequest: { req async throws in
			if let token {
				req.headers.bearerAuthorization = .init(token: token)
			}
			if let body {
				req.headers.contentType = .json; try req.content.encode(body)
			}
		}, afterResponse: { result = $0 })
		return result!
	}

	private func rawRequest(_ app: Application, _ method: HTTPMethod, _ path: String, token: String? = nil, body: Data, omitContentLength: Bool = false) async throws -> XCTHTTPResponse {
		var result: XCTHTTPResponse?
		try await app.test(method, path, beforeRequest: { req async throws in
			if let token {
				req.headers.bearerAuthorization = .init(token: token)
			}
			req.headers.contentType = .json
			if !omitContentLength {
				req.headers.replaceOrAdd(name: .contentLength, value: body.count.description)
			}
			req.body = .init(data: body)
		}, afterResponse: { result = $0 })
		return result!
	}
}

private struct EmptyBody: Content {}

private struct ForgedImportBody: Content {
	let timetableID: UUID
	let sourceKind: SourceKind
	let title: String
}

private struct SQLiteClientIdentityMigration: AsyncMigration {
	var name: String {
		"pmsttTests.P2SQLiteClientIdentity"
	}

	func prepare(on database: any Database) async throws {
		try await database.schema(UserToken.schema).field("client_platform", .string).update()
		try await database.schema(UserToken.schema).field("installation_id", .string).update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(UserToken.schema).deleteField("installation_id").update()
		try await database.schema(UserToken.schema).deleteField("client_platform").update()
	}
}

private struct SQLiteAppleStateMigration: AsyncMigration {
	var name: String {
		"pmsttTests.P2SQLiteAppleState"
	}

	func prepare(on database: any Database) async throws {
		try await database.schema(User.schema).field("apple_email_forwarding_enabled", .bool).update()
		try await database.schema(User.schema).field("apple_authorization_revoked_at", .datetime).update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema).deleteField("apple_authorization_revoked_at").update()
		try await database.schema(User.schema).deleteField("apple_email_forwarding_enabled").update()
	}
}
