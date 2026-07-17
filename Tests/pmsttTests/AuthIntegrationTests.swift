import Crypto
import Fluent
import FluentSQLiteDriver
import JWT
import Vapor
import XCTVapor
import XCTest
@testable import pmstt

final class AuthIntegrationTests: XCTestCase, @unchecked Sendable {
	func testPlatformAuthorityAndCapabilities() {
		XCTAssertEqual(ClientPlatform.iOS.authority, .authoritative)
		XCTAssertTrue(ClientPlatform.iOS.capabilities.contains(.mutateAccount))
		XCTAssertEqual(ClientPlatform.iPadOS.capabilities, [.read, .logout])
		XCTAssertEqual(ClientPlatform.watchOS.capabilities, [.read, .logout])
	}

	func testRegisterAndRefreshRotateTheSameSession() async throws {
		let app = try await makeApplication()

		let response = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "p1@example.com", password: "password", displayName: "P1", platform: "iOS", installationID: "iphone-1"))
		XCTAssertEqual(response.status, .ok)
		let first = try response.content.decode(TokenResponse.self)
		let firstPayload = try await app.jwt.keys.verify([UInt8](first.accessToken.utf8), as: UserPayload.self)
		let session = try await UserToken.find(firstPayload.sid, on: app.db(.sqlite))
		XCTAssertEqual(session?.platformValue, .iOS)

		let refreshed = try await request(app, .POST, "/v1/auth/refresh", body: RefreshRequest(refreshToken: first.refreshToken))
		XCTAssertEqual(refreshed.status, .ok)
		let second = try refreshed.content.decode(TokenResponse.self)
		let secondPayload = try await app.jwt.keys.verify([UInt8](second.accessToken.utf8), as: UserPayload.self)
		XCTAssertEqual(secondPayload.sid, firstPayload.sid)
		XCTAssertNotEqual(second.refreshToken, first.refreshToken)

		let replay = try await request(app, .POST, "/v1/auth/refresh", body: RefreshRequest(refreshToken: first.refreshToken))
		XCTAssertEqual(replay.status, .unauthorized)
		let currentHash = try await currentRefreshTokenHash(for: second, on: app)
		XCTAssertEqual(hashToken(second.refreshToken), currentHash)
	}

	func testRefreshRejectsMismatchedSignedClaims() async throws {
		let app = try await makeApplication()
		let response = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "claims@example.com", password: "password", displayName: nil, platform: "iOS", installationID: "iphone-claims"))
		let tokens = try response.content.decode(TokenResponse.self)
		let payload = try await app.jwt.keys.verify([UInt8](tokens.refreshToken.utf8), as: RefreshPayload.self)
		let mismatched = try await app.jwt.keys.sign(RefreshPayload(sub: payload.sub, sid: payload.sid, platform: payload.platform, installationID: "other-installation", authority: payload.authority, jti: payload.jti, typ: "refresh", iss: payload.iss, iat: payload.iat, exp: payload.exp))
		let result = try await request(app, .POST, "/v1/auth/refresh", body: RefreshRequest(refreshToken: mismatched))
		XCTAssertEqual(result.status, .unauthorized)
	}

	func testConcurrentRefreshReplayHasExactlyOneWinner() async throws {
		let app = try await makeApplication()
		let response = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "race@example.com", password: "password", displayName: nil, platform: "iOS", installationID: "iphone-race"))
		let tokens = try response.content.decode(TokenResponse.self)
		async let first = request(app, .POST, "/v1/auth/refresh", body: RefreshRequest(refreshToken: tokens.refreshToken))
		async let second = request(app, .POST, "/v1/auth/refresh", body: RefreshRequest(refreshToken: tokens.refreshToken))
		let results = try await [first, second]
		XCTAssertEqual(results.filter { $0.status == .ok }.count, 1)
		XCTAssertEqual(results.filter { $0.status == .unauthorized }.count, 1)
	}

	func testNonAuthoritativeSessionsCanReadButCannotMutate() async throws {
		let app = try await makeApplication()
		let response = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "ipad@example.com", password: "password", displayName: nil, platform: "iPadOS", installationID: "ipad-1"))
		let tokens = try response.content.decode(TokenResponse.self)

		let read = try await request(app, .GET, "/v1/account", token: tokens.accessToken, body: EmptyBody())
		XCTAssertEqual(read.status, .ok)
		let mutation = try await request(app, .PUT, "/v1/account", token: tokens.accessToken, body: UpdateAccountRequest(displayName: "blocked", email: nil))
		XCTAssertEqual(mutation.status, .forbidden)
	}

	func testWatchSessionIsParentBoundAndRevokedWithTheIPhone() async throws {
		let app = try await makeApplication()
		let phoneResponse = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "watch@example.com", password: "password", displayName: nil, platform: "iOS", installationID: "iphone-watch"))
		let phone = try phoneResponse.content.decode(TokenResponse.self)
		let watchResponse = try await request(app, .POST, "/v1/auth/watch-session", token: phone.accessToken, body: WatchSessionRequest(installationID: "watch-1"))
		XCTAssertEqual(watchResponse.status, .ok)
		let watch = try watchResponse.content.decode(TokenResponse.self)
		let watchPayload = try await app.jwt.keys.verify([UInt8](watch.accessToken.utf8), as: UserPayload.self)
		let watchSession = try await UserToken.find(watchPayload.sid, on: app.db(.sqlite))
		let phonePayload = try await app.jwt.keys.verify([UInt8](phone.accessToken.utf8), as: UserPayload.self)
		XCTAssertEqual(watchSession?.parentSessionID, phonePayload.sid)

		let watchCannotProvision = try await request(app, .POST, "/v1/auth/watch-session", token: watch.accessToken, body: WatchSessionRequest(installationID: "watch-2"))
		XCTAssertEqual(watchCannotProvision.status, .forbidden)

		let logout = try await request(app, .DELETE, "/v1/auth/logout", token: phone.accessToken, body: LogoutRequest(refreshToken: phone.refreshToken))
		XCTAssertEqual(logout.status, .noContent)
		let offlineRead = try await request(app, .GET, "/v1/account", token: watch.accessToken, body: EmptyBody())
		XCTAssertEqual(offlineRead.status, .unauthorized)
		let offlineRefresh = try await request(app, .POST, "/v1/auth/refresh", body: RefreshRequest(refreshToken: watch.refreshToken))
		XCTAssertEqual(offlineRefresh.status, .unauthorized)
	}

	func testWatchProvisioningRejectsAStaleAccessTokenAfterParentRevocation() async throws {
		let app = try await makeApplication()
		let phoneResponse = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "watch-stale@example.com", password: "password", displayName: nil, platform: "iOS", installationID: "iphone-watch-stale"))
		let phone = try phoneResponse.content.decode(TokenResponse.self)
		let payload = try await app.jwt.keys.verify([UInt8](phone.accessToken.utf8), as: UserPayload.self)
		guard let parent = try await UserToken.find(payload.sid, on: app.db(.sqlite)) else {
			return XCTFail("The registration must create a parent session")
		}
		parent.revokedAt = Date()
		try await parent.save(on: app.db(.sqlite))

		let watchResponse = try await request(app, .POST, "/v1/auth/watch-session", token: phone.accessToken, body: WatchSessionRequest(installationID: "watch-stale"))
		XCTAssertEqual(watchResponse.status, .unauthorized)
		let watchRows = try await UserToken.query(on: app.db(.sqlite))
			.filter(\.$clientPlatform == ClientPlatform.watchOS.rawValue)
			.all()
		XCTAssertTrue(watchRows.isEmpty)
	}

	func testRepeatedWatchProvisioningLeavesOneActiveSession() async throws {
		let app = try await makeApplication()
		let phoneResponse = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "watch-race@example.com", password: "password", displayName: nil, platform: "iOS", installationID: "iphone-watch-race"))
		let phone = try phoneResponse.content.decode(TokenResponse.self)
		let first = try await request(app, .POST, "/v1/auth/watch-session", token: phone.accessToken, body: WatchSessionRequest(installationID: "watch-race"))
		let second = try await request(app, .POST, "/v1/auth/watch-session", token: phone.accessToken, body: WatchSessionRequest(installationID: "watch-race"))
		let results = [first, second]
		XCTAssertTrue(results.allSatisfy { $0.status == .ok })
		let active = try await UserToken.query(on: app.db(.sqlite))
			.filter(\.$clientPlatform == ClientPlatform.watchOS.rawValue)
			.filter(\.$installationID == "watch-race")
			.filter(\.$revokedAt == nil)
			.all()
		XCTAssertEqual(active.count, 1)
		XCTAssertNotNil(active.first?.activeWatchKey)
	}

	func testWatchProvisioningAndParentRevocationAreOrderIndependent() async throws {
		let app = try await makeApplication()
		let provisionFirst = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "watch-provision-first@example.com", password: "password", displayName: nil, platform: "iOS", installationID: "iphone-provision-first")).content.decode(TokenResponse.self)
		let provisionResponse = try await request(app, .POST, "/v1/auth/watch-session", token: provisionFirst.accessToken, body: WatchSessionRequest(installationID: "watch-provision-first"))
		XCTAssertEqual(provisionResponse.status, .ok)
		let logoutAfterProvision = try await request(app, .DELETE, "/v1/auth/logout", token: provisionFirst.accessToken, body: LogoutRequest(refreshToken: provisionFirst.refreshToken))
		XCTAssertEqual(logoutAfterProvision.status, .noContent)
		let activeAfterLogout = try await UserToken.query(on: app.db(.sqlite)).filter(\.$installationID == "watch-provision-first").filter(\.$revokedAt == nil).count()
		XCTAssertEqual(activeAfterLogout, 0)

		let revokeFirst = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "watch-revoke-first@example.com", password: "password", displayName: nil, platform: "iOS", installationID: "iphone-revoke-first")).content.decode(TokenResponse.self)
		let logoutBeforeProvision = try await request(app, .DELETE, "/v1/auth/logout", token: revokeFirst.accessToken, body: LogoutRequest(refreshToken: revokeFirst.refreshToken))
		XCTAssertEqual(logoutBeforeProvision.status, .noContent)
		let rejectedProvision = try await request(app, .POST, "/v1/auth/watch-session", token: revokeFirst.accessToken, body: WatchSessionRequest(installationID: "watch-revoke-first"))
		XCTAssertEqual(rejectedProvision.status, .unauthorized)
		let activeAfterRejectedProvision = try await UserToken.query(on: app.db(.sqlite)).filter(\.$installationID == "watch-revoke-first").filter(\.$revokedAt == nil).count()
		XCTAssertEqual(activeAfterRejectedProvision, 0)
	}

	func testRouteCapabilityMatrixAndRepresentativeReads() async throws {
		let app = try await makeApplication()
		let phone = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "matrix-phone@example.com", password: "password", displayName: nil, platform: "iOS", installationID: "matrix-phone")).content.decode(TokenResponse.self)
		let ipad = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "matrix-ipad@example.com", password: "password", displayName: nil, platform: "iPadOS", installationID: "matrix-ipad")).content.decode(TokenResponse.self)
		let mac = try await request(app, .POST, "/v1/auth/register", body: RegisterRequest(email: "matrix-mac@example.com", password: "password", displayName: nil, platform: "macOS", installationID: "matrix-mac")).content.decode(TokenResponse.self)
		let watch = try await request(app, .POST, "/v1/auth/watch-session", token: phone.accessToken, body: WatchSessionRequest(installationID: "matrix-watch")).content.decode(TokenResponse.self)
		let legacyPayload = LegacyUserPayload(sub: phone.user.id, email: phone.user.email, exp: .init(value: Date().addingTimeInterval(900)))
		let legacy = try await app.jwt.keys.sign(legacyPayload)
		let mutationRoutes: [(HTTPMethod, String)] = [
			(.PUT, "/v1/account"), (.DELETE, "/v1/account"), (.PUT, "/v1/settings"),
			(.PUT, "/v1/timetables/owner"), (.PUT, "/v1/timetables/owner/visibility"),
			(.POST, "/v1/timetables/authored"), (.PUT, "/v1/timetables/received"),
			(.DELETE, "/v1/timetables/received/legacy"), (.PUT, "/v1/received-name-overrides/legacy"),
			(.DELETE, "/v1/received-name-overrides/legacy"), (.PUT, "/v1/devices/current"),
			(.DELETE, "/v1/devices/current"), (.POST, "/v1/notifications/test"),
			(.PUT, "/v1/devices/current/live-activity-token"), (.DELETE, "/v1/devices/current/live-activity-token"),
			(.PUT, "/v1/live-activities/00000000-0000-0000-0000-000000000000/update-token"),
			(.POST, "/v1/live-activities/current/reconcile"), (.POST, "/v1/report/user"),
			(.POST, "/v1/report/feedback"), (.POST, "/v1/auth/watch-session")
		]
		for token in [ipad.accessToken, mac.accessToken, watch.accessToken, legacy] {
			for (method, path) in mutationRoutes {
				let result = try await request(app, method, path, token: token)
				XCTAssertEqual(result.status, .forbidden, "\(method) \(path)")
			}
		}
		for token in [ipad.accessToken, mac.accessToken, watch.accessToken, legacy] {
			for path in ["/v1/account", "/v1/settings"] {
				let result = try await request(app, .GET, path, token: token)
				XCTAssertNotEqual(result.status, .unauthorized, "\(path)")
				XCTAssertNotEqual(result.status, .forbidden, "\(path)")
			}
		}
	}

	func testLegacyOpaqueRefreshAndLogoutRevokeOrphanedWatchRows() async throws {
		let app = try await makeApplication()
		let user = User(email: "legacy@example.com", passwordHash: nil, appleSubject: nil, displayName: "Legacy", selfPassSerialNumber: UUID().uuidString, settingsData: try JSONEncoder().encode(AccountSettings.default))
		try await user.save(on: app.db(.sqlite))
		let userID = try user.requireID()
		let legacyRefresh = "legacy-opaque-refresh"
		let legacySession = UserToken(tokenHash: SHA256.hash(data: Data(legacyRefresh.utf8)).map { String(format: "%02x", $0) }.joined(), userID: userID, expiresAt: Date().addingTimeInterval(3600))
		try await legacySession.save(on: app.db(.sqlite))
		let orphan = UserToken(tokenHash: "orphan", userID: userID, expiresAt: Date().addingTimeInterval(3600), clientPlatform: ClientPlatform.watchOS.rawValue, installationID: "watch-orphan", parentSessionID: UUID(), refreshJTI: UUID())
		try await orphan.save(on: app.db(.sqlite))
		let access = try await app.jwt.keys.sign(LegacyUserPayload(sub: userID, email: user.email, exp: .init(value: Date().addingTimeInterval(900))))
		let refreshed = try await request(app, .POST, "/v1/auth/refresh", body: RefreshRequest(refreshToken: legacyRefresh))
		XCTAssertEqual(refreshed.status, .ok)
		let refreshedTokens = try refreshed.content.decode(TokenResponse.self)
		XCTAssertFalse(refreshedTokens.refreshToken.contains("."))
		let logout = try await request(app, .DELETE, "/v1/auth/logout", token: access, body: LogoutRequest(refreshToken: refreshedTokens.refreshToken))
		XCTAssertEqual(logout.status, .noContent)
		let storedOrphan = try await UserToken.find(orphan.requireID(), on: app.db(.sqlite))
		XCTAssertNotNil(storedOrphan?.revokedAt)
	}

	func testProductionAuthorityMigrationBackfillsUnknownAndLegacyWatchRows() async throws {
		let app = try await Application.make(.testing)
		addTeardownBlock { try await app.asyncShutdown() }
		app.databases.use(.sqlite(.memory), as: .sqlite)
		var migrations = sqliteCompatibleMigrationList()
		let userID = UUID()
		migrations.insert(SeedLegacyTokenRows(userID: userID), at: 3)
		app.migrations.add(migrations)
		try await app.migrator.setupIfNeeded().flatMap { app.migrator.prepareBatch() }.get()
		let tokens = try await UserToken.query(on: app.db(.sqlite)).all()
		XCTAssertEqual(tokens.filter { $0.clientPlatform == ClientPlatform.legacy.rawValue }.count, 2)
		XCTAssertEqual(tokens.first(where: { $0.tokenHash == "unknown" })?.clientPlatform, ClientPlatform.legacy.rawValue)
		XCTAssertNotNil(tokens.first(where: { $0.clientPlatform == ClientPlatform.watchOS.rawValue })?.revokedAt)

		XCTAssertEqual(tokens.first(where: { $0.tokenHash == "unknown" })?.platformValue, .legacy)
		let first = UserToken(tokenHash: "migration-watch-key", userID: userID, expiresAt: Date().addingTimeInterval(3600), clientPlatform: ClientPlatform.watchOS.rawValue, installationID: "migration-watch", activeWatchKey: "migration-duplicate-key")
		try await first.save(on: app.db(.sqlite))
		let duplicate = UserToken(tokenHash: "migration-duplicate", userID: userID, expiresAt: Date().addingTimeInterval(3600), clientPlatform: ClientPlatform.watchOS.rawValue, installationID: "migration-watch-duplicate", activeWatchKey: "migration-duplicate-key")
		var rejectedDuplicate = false
		do {
			try await duplicate.save(on: app.db(.sqlite))
		} catch {
			rejectedDuplicate = true
		}
		XCTAssertTrue(rejectedDuplicate, "The active_watch_key index must reject duplicate active keys")
	}

	private func makeApplication() async throws -> Application {
		await AuthRateLimiter.shared.reset()
		let app = try await Application.make(.testing)
		addTeardownBlock { try await app.asyncShutdown() }
		app.databases.use(.sqlite(.memory), as: .sqlite)
		await app.jwt.keys.add(hmac: HMACKey(from: "test-session-secret"), digestAlgorithm: .sha256)
		app.migrations.add(sqliteCompatibleMigrationList())
		try routes(app)
		try await app.migrator.setupIfNeeded().flatMap { app.migrator.prepareBatch() }.get()
		return app
	}

	private func currentRefreshTokenHash(for response: TokenResponse, on app: Application) async throws -> String {
		let payload = try await app.jwt.keys.verify([UInt8](response.refreshToken.utf8), as: RefreshPayload.self)
		let session = try await UserToken.find(payload.sid, on: app.db(.sqlite))
		return session?.tokenHash ?? ""
	}

	private func request(_ app: Application, _ method: HTTPMethod, _ path: String, token: String? = nil) async throws -> XCTHTTPResponse {
		try await request(app, method, path, token: token, body: EmptyBody())
	}

	private func hashToken(_ token: String) -> String {
		SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
	}

	private func request<T: Content>(_ app: Application, _ method: HTTPMethod, _ path: String, token: String? = nil, body: T? = nil) async throws -> XCTHTTPResponse {
		var result: XCTHTTPResponse?
		try await app.test(method, path, beforeRequest: { request async throws in
			if let token { request.headers.bearerAuthorization = .init(token: token) }
			if let body {
				request.headers.contentType = .json
				try request.content.encode(body)
			}
		}, afterResponse: { response in
			result = response
		})
		return result!
	}
}

private func sqliteCompatibleMigrationList() -> [any Migration] {
	pmsttMigrationList().map { migration in
		if migration is AddUserTokenClientIdentity { return SQLiteAddUserTokenClientIdentity() }
		if migration is AddAppleAccountState { return SQLiteAddAppleAccountState() }
		return migration
	}
}

private struct SQLiteAddUserTokenClientIdentity: AsyncMigration {
	var name: String { "pmsttTests.SQLiteAddUserTokenClientIdentity" }

	func prepare(on database: any Database) async throws {
		try await database.schema(UserToken.schema).field("client_platform", .string).update()
		try await database.schema(UserToken.schema).field("installation_id", .string).update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(UserToken.schema).deleteField("installation_id").update()
		try await database.schema(UserToken.schema).deleteField("client_platform").update()
	}
}

private struct SQLiteAddAppleAccountState: AsyncMigration {
	var name: String { "pmsttTests.SQLiteAddAppleAccountState" }

	func prepare(on database: any Database) async throws {
		try await database.schema(User.schema).field("apple_email_forwarding_enabled", .bool).update()
		try await database.schema(User.schema).field("apple_authorization_revoked_at", .datetime).update()
	}

	func revert(on database: any Database) async throws {
		try await database.schema(User.schema).deleteField("apple_authorization_revoked_at").update()
		try await database.schema(User.schema).deleteField("apple_email_forwarding_enabled").update()
	}
}

private struct EmptyBody: Content {}
private struct LogoutRequest: Content { let refreshToken: String }

final class SeedLegacyTokenRows: AsyncMigration {
	let userID: UUID

	init(userID: UUID) { self.userID = userID }

	func prepare(on database: any Database) async throws {
		let user = LegacyUser(id: userID, email: "migration@example.com", displayName: "Migration", selfPassSerialNumber: UUID().uuidString, settingsData: try JSONEncoder().encode(AccountSettings.default))
		try await user.save(on: database)
		let legacy = LegacyToken(id: UUID(), tokenHash: "legacy", userID: userID, expiresAt: Date().addingTimeInterval(3600), clientPlatform: nil, installationID: nil)
		let unknown = LegacyToken(id: UUID(), tokenHash: "unknown", userID: userID, expiresAt: Date().addingTimeInterval(3600), clientPlatform: "futureOS", installationID: "future-installation")
		let watch = LegacyToken(id: UUID(), tokenHash: "watch", userID: userID, expiresAt: Date().addingTimeInterval(3600), clientPlatform: ClientPlatform.watchOS.rawValue, installationID: "watch-legacy")
		try await legacy.save(on: database)
		try await unknown.save(on: database)
		try await watch.save(on: database)
	}

	func revert(on database: any Database) async throws {}
}

private final class LegacyToken: Model, @unchecked Sendable {
	static let schema = UserToken.schema
	@ID(key: .id) var id: UUID?
	@Field(key: "token_hash") var tokenHash: String
	@Parent(key: "user_id") var user: User
	@Field(key: "expires_at") var expiresAt: Date
	@OptionalField(key: "client_platform") var clientPlatform: String?
	@OptionalField(key: "installation_id") var installationID: String?
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
	init() {}
	init(id: UUID, tokenHash: String, userID: UUID, expiresAt: Date, clientPlatform: String?, installationID: String?) {
		self.id = id; self.tokenHash = tokenHash; self.$user.id = userID; self.expiresAt = expiresAt; self.clientPlatform = clientPlatform; self.installationID = installationID
	}
}

private final class LegacyUser: Model, @unchecked Sendable {
	static let schema = User.schema
	@ID(key: .id) var id: UUID?
	@Field(key: "email") var email: String?
	@Field(key: "password_hash") var passwordHash: String?
	@Field(key: "apple_subject") var appleSubject: String?
	@Field(key: "display_name") var displayName: String
	@Field(key: "self_pass_serial_number") var selfPassSerialNumber: String
	@Field(key: "settings_data") var settingsData: Data
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
	init() {}
	init(id: UUID, email: String, displayName: String, selfPassSerialNumber: String, settingsData: Data) {
		self.id = id; self.email = email; self.passwordHash = nil; self.appleSubject = nil; self.displayName = displayName; self.selfPassSerialNumber = selfPassSerialNumber; self.settingsData = settingsData
	}
}
