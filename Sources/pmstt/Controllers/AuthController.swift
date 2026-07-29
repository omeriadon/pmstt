import Crypto
import Fluent
import JWT
import SQLKit
import Vapor

struct AuthController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let auth = routes.grouped("v1", "auth").grouped(AuthRateLimitMiddleware())
		auth.post("register", use: register)
		auth.post("request-code", use: requestVerificationCode)
		auth.post("verify-code-register", use: verifyCodeAndRegister)
		auth.post("login", use: login)
		auth.post("refresh", use: refresh)

		let protected = auth.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())
		protected.delete("logout", use: logout)
		protected.post("watch-session", use: createWatchSession)
	}

	func register(req: Request) async throws -> TokenResponse {
		try RegisterRequest.validate(content: req)
		let body = try req.content.decode(RegisterRequest.self)
		let platform = try validatedClient(platform: body.platform, installationID: body.installationID)
		guard !body.email.isEmpty, body.email.contains("@") else { throw AppError(.badRequest, code: .invalidRequest, reason: "Invalid email format.", field: "email") }
		try await ServerAccessModeService.requirePermittedEmail(body.email, on: req.db)
		guard body.password.count >= 8 else { throw AppError(.badRequest, code: .invalidRequest, reason: "Password must be at least 8 characters long.", field: "password") }
		guard try await User.query(on: req.db).filter(\.$email == body.email.lowercased()).first() == nil else {
			throw AppError(.conflict, code: .emailAlreadyExists, reason: "Email is already registered.", field: "email")
		}
		let user = try User(email: body.email, passwordHash: req.password.hash(body.password), appleSubject: nil, displayName: body.displayName ?? "User", selfPassSerialNumber: UUID().uuidString, settingsData: JSONEncoder().encode(AccountSettings.default))
		try await req.db.transaction { database in
			try await user.save(on: database)
			try await EventTagSubscriptionService.subscribeNewAccount(
				user.requireID(),
				on: database
			)
		}
		return try await issueNewSession(for: user, platform: platform, installationID: normalizedInstallationID(body.installationID), on: req)
	}

	func requestVerificationCode(req: Request) async throws -> HTTPStatus {
		let body = try req.content.decode(VerificationCodeRequest.self)
		let email = body.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard email.hasSuffix("@student.education.wa.edu.au") else { throw Abort(.badRequest) }
		guard try await User.query(on: req.db).filter(\.$email == email).first() == nil else { throw Abort(.conflict) }
		let code = String(format: "%06d", Int.random(in: 0 ... 999_999))
		let now = Date()
		try await req.db.transaction { database in
			try await EmailVerificationChallenge.query(on: database)
				.filter(\.$normalizedEmail == email)
				.filter(\.$usedAt == nil)
				.set(\.$usedAt, to: now)
				.update()
			let challenge = EmailVerificationChallenge(normalizedEmail: email, codeHash: code.sha256Digest, installationID: body.installationID, sourceIP: req.remoteAddress?.ipAddress ?? "unknown", expiresAt: now.addingTimeInterval(600), resendAvailableAt: now.addingTimeInterval(120))
			try await challenge.create(on: database)
		}
		try await sendVerificationEmail(code: code, to: email, req: req)
		return .accepted
	}

	func verifyCodeAndRegister(req: Request) async throws -> TokenResponse {
		let body = try req.content.decode(VerificationRegistrationRequest.self)
		let platform = try validatedClient(platform: body.platform, installationID: body.installationID)
		let email = body.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard email.hasSuffix("@student.education.wa.edu.au"), body.code.count == 6, body.password.count >= 8 else {
			throw Abort(.badRequest)
		}
		guard try await User.query(on: req.db).filter(\.$email == email).first() == nil else {
			throw AppError(.conflict, code: .emailAlreadyExists, reason: "Email is already registered.", field: "email")
		}

		let now = Date()
		let user = try await req.db.transaction { database -> User in
			guard let challenge = try await EmailVerificationChallenge.query(on: database)
				.filter(\.$normalizedEmail == email)
				.filter(\.$installationID == body.installationID)
				.filter(\.$usedAt == nil)
				.sort(\.$createdAt, .descending)
				.first(), challenge.expiresAt > now, challenge.failedAttemptCount < 5
			else { throw Abort(.unauthorized) }
			challenge.lastAttemptAt = now
			guard challenge.codeHash == body.code.sha256Digest else {
				challenge.failedAttemptCount += 1
				try await challenge.save(on: database)
				throw Abort(.unauthorized)
			}
			challenge.usedAt = now
			try await challenge.save(on: database)
			let user = try User(email: email, passwordHash: req.password.hash(body.password), displayName: derivedDisplayName(from: email), selfPassSerialNumber: UUID().uuidString, settingsData: JSONEncoder().encode(AccountSettings.default))
			try await user.save(on: database)
			try await EventTagSubscriptionService.subscribeNewAccount(user.requireID(), on: database)
			return user
		}
		return try await issueNewSession(for: user, platform: platform, installationID: normalizedInstallationID(body.installationID), on: req)
	}

	func login(req: Request) async throws -> TokenResponse {
		let body = try req.content.decode(LoginRequest.self)
		let platform = try validatedSessionClient(platform: body.platform, installationID: body.installationID)
		guard let user = try await User.query(on: req.db).filter(\.$email == body.email.lowercased()).first(),
		      let passwordHash = user.passwordHash,
		      try req.password.verify(body.password, created: passwordHash)
		else { throw AppError(.unauthorized, code: .invalidCredentials, reason: "Invalid email or password.") }
		try await ServerAccessModeService.requirePermittedAccount(user, on: req.db)
		return try await issueNewSession(for: user, platform: platform, installationID: normalizedInstallationID(body.installationID), on: req)
	}


	func refresh(req: Request) async throws -> TokenResponse {
		let body = try req.content.decode(RefreshRequest.self)
		let submittedHash = hashToken(body.refreshToken)
		let signedPayload = try? await req.jwt.verify(body.refreshToken, as: RefreshPayload.self)
		let session: UserToken?
		if let signedPayload {
			session = try await UserToken.query(on: req.db).filter(\.$id == signedPayload.sid).with(\.$user).first()
			guard let session,
			      session.tokenHash == submittedHash,
			      session.refreshJTI == signedPayload.jti,
			      session.$user.id == signedPayload.sub,
			      session.platformValue.rawValue == signedPayload.platform,
			      session.installationID == signedPayload.installationID,
			      session.platformValue.authority.rawValue == signedPayload.authority
			else { throw AppError(.unauthorized, code: .sessionExpired, reason: "Invalid or expired session.") }
			try await SessionAuthorityResolver.validate(UserPayload(sub: signedPayload.sub, sid: signedPayload.sid, platform: session.platformValue, installationID: signedPayload.installationID, expiresAt: Date().addingTimeInterval(60)), on: req)
		} else {
			session = try await UserToken.query(on: req.db).filter(\.$tokenHash == submittedHash).with(\.$user).first()
		}
		guard let session, session.revokedAt == nil, session.expiresAt > Date() else { throw AppError(.unauthorized, code: .sessionExpired, reason: "Invalid or expired session.") }
		let refreshUser = try await session.$user.get(on: req.db)
		try await ServerAccessModeService.requirePermittedAccount(refreshUser, on: req.db)
		if session.platformValue == .watchOS {
			try await requireActiveParent(session, on: req)
		}

		let oldJTI = session.refreshJTI
		let newJTI = session.platformValue == .legacy ? nil : UUID()
		let newExpiresAt = Date().addingTimeInterval(refreshLifetime(for: session.platformValue))
		let refresh = try await newRefreshToken(for: session, jti: newJTI, legacy: session.platformValue == .legacy, on: req)
		let rotated = try await req.db.transaction { database -> UserToken in
			let query = try UserToken.query(on: database)
				.filter(\.$id == (session.requireID()))
				.filter(\.$tokenHash == submittedHash)
				.filter(\.$revokedAt == nil)
			if let oldJTI {
				query.filter(\.$refreshJTI == oldJTI)
			} else {
				query.filter(\.$refreshJTI == nil)
			}
			query.set(\.$tokenHash, to: hashToken(refresh))
				.set(\.$expiresAt, to: newExpiresAt)
			if let newJTI {
				query.set(\.$refreshJTI, to: newJTI)
			} else {
				query.set(\.$refreshJTI, to: nil)
			}
			try await query.update()
			guard let rotated = try await UserToken.find(session.requireID(), on: database),
			      rotated.tokenHash == hashToken(refresh), rotated.refreshJTI == newJTI
			else {
				throw AppError(.unauthorized, code: .sessionExpired, reason: "Invalid or expired session.")
			}
			return rotated
		}
		return try await response(for: rotated, on: req, refreshToken: refresh)
	}

	func createWatchSession(req: Request) async throws -> TokenResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard payload.platformValue == .iOS else { throw Abort(.forbidden) }
		let body = try req.content.decode(WatchSessionRequest.self)
		let installationID = try normalizedInstallation(body.installationID)
		let session = UserToken(id: UUID(), tokenHash: "pending", userID: payload.sub, expiresAt: Date().addingTimeInterval(refreshLifetime(for: .watchOS)), clientPlatform: ClientPlatform.watchOS.rawValue, installationID: installationID, parentSessionID: payload.sid, refreshJTI: UUID(), activeWatchKey: AddUserTokenAuthority.watchKey(userID: payload.sub, installationID: installationID))
		let refresh = try await makeRefreshToken(for: session, jti: session.refreshJTI!, on: req)
		session.tokenHash = hashToken(refresh)
		try await req.db.transaction { database in
			guard let parent = try await lockSession(payload.sid, on: database),
			      parent.revokedAt == nil,
			      parent.expiresAt > Date(),
			      parent.$user.id == payload.sub,
			      parent.platformValue == .iOS
			else { throw Abort(.unauthorized) }
			guard try await User.find(payload.sub, on: database) != nil else {
				throw AppError(.notFound, code: .accountNotFound, reason: "Your account could not be found.")
			}
			try await UserToken.query(on: database)
				.filter(\.$activeWatchKey == session.activeWatchKey)
				.set(\.$revokedAt, to: Date())
				.set(\.$activeWatchKey, to: nil)
				.update()
			try await session.save(on: database)
		}
		return try await response(for: session, on: req, refreshToken: refresh)
	}

	func logout(req: Request) async throws -> HTTPStatus {
		struct LogoutBody: Decodable { let refreshToken: String }
		let body = try req.content.decode(LogoutBody.self)
		let payload = try req.auth.require(UserPayload.self)
		if payload.platformValue == .legacy {
			if let token = try await UserToken.query(on: req.db).filter(\.$tokenHash == hashToken(body.refreshToken)).with(\.$user).first(), token.$user.id == payload.sub {
				token.revokedAt = Date(); try await token.save(on: req.db)
				try await revokeOrphanedWatchSessions(userID: payload.sub, on: req.db)
			}
			return .noContent
		}
		guard let session = try await UserToken.find(payload.sid, on: req.db), session.$user.id == payload.sub, session.tokenHash == hashToken(body.refreshToken) else { throw Abort(.unauthorized) }
		try await req.db.transaction { database in
			guard let lockedSession = try await lockSession(payload.sid, on: database), lockedSession.$user.id == payload.sub, lockedSession.tokenHash == hashToken(body.refreshToken) else { throw Abort(.unauthorized) }
			lockedSession.revokedAt = Date()
			try await lockedSession.save(on: database)
			if payload.platformValue == .iOS {
				try await UserToken.query(on: database).filter(\.$parentSessionID == payload.sid).set(\.$revokedAt, to: Date()).set(\.$activeWatchKey, to: nil).update()
			}
		}
		return .noContent
	}

	private func issueNewSession(for user: User, platform: ClientPlatform, installationID: String, parentSessionID: UUID? = nil, on req: Request) async throws -> TokenResponse {
		try await ServerAccessModeService.requirePermittedAccount(user, on: req.db)
		let session = try UserToken(id: UUID(), tokenHash: "pending", userID: user.requireID(), expiresAt: Date().addingTimeInterval(refreshLifetime(for: platform)), clientPlatform: platform.rawValue, installationID: installationID, parentSessionID: parentSessionID, refreshJTI: UUID())
		let refresh = try await makeRefreshToken(for: session, jti: session.refreshJTI!, on: req)
		session.tokenHash = hashToken(refresh)
		try await session.save(on: req.db)
		return try await response(for: session, on: req, refreshToken: refresh)
	}

	private func response(for session: UserToken, on req: Request, refreshToken: String? = nil) async throws -> TokenResponse {
		let user = try await session.$user.get(on: req.db)
		let access = try await req.jwt.sign(UserPayload(sub: user.requireID(), sid: session.requireID(), platform: session.platformValue, installationID: session.installationID ?? "", capabilities: session.platformValue.capabilities, expiresAt: Date().addingTimeInterval(60 * 15)))
		let refresh: String = if let refreshToken {
			refreshToken
		} else {
			try await makeRefreshToken(for: session, jti: session.refreshJTI!, on: req)
		}
		return try TokenResponse(
			accessToken: access,
			refreshToken: refresh,
			user: UserAccountResponse(
				id: user.requireID(),
				email: user.email,
				displayName: user.displayName,
				createdAt: user.createdAt,
				authority: AccountAuthority.resolved(for: user.email, storedAuthority: user.accountAuthority)
			)
		)
	}

	private func makeRefreshToken(for session: UserToken, jti: UUID, on req: Request) async throws -> String {
		try await req.jwt.sign(RefreshPayload(sub: session.$user.id, sid: session.requireID(), platform: session.platformValue.rawValue, installationID: session.installationID ?? "", authority: session.platformValue.authority.rawValue, jti: jti, typ: "refresh", iss: .init(value: "pmstt"), iat: .init(value: Date()), exp: .init(value: Date().addingTimeInterval(refreshLifetime(for: session.platformValue)))))
	}

	private func newRefreshToken(for session: UserToken, jti: UUID?, legacy: Bool, on req: Request) async throws -> String {
		if legacy {
			return Data((0 ..< 32).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
		}
		return try await makeRefreshToken(for: session, jti: jti!, on: req)
	}

	private func revokeOrphanedWatchSessions(userID: UUID, on database: any Database) async throws {
		let watches = try await UserToken.query(on: database)
			.filter(\.$user.$id == userID)
			.filter(\.$clientPlatform == ClientPlatform.watchOS.rawValue)
			.all()
		let tokens = try await UserToken.query(on: database).all()
		let byID = Dictionary(uniqueKeysWithValues: tokens.compactMap { token in token.id.map { ($0, token) } })
		for watch in watches {
			let parent = watch.parentSessionID.flatMap { byID[$0] }
			if parent == nil || parent?.revokedAt != nil || parent?.platformValue != .iOS {
				watch.revokedAt = watch.revokedAt ?? Date()
				watch.activeWatchKey = nil
				try await watch.save(on: database)
			}
		}
	}

	private func requireActiveParent(_ session: UserToken, on req: Request) async throws {
		guard let parentID = session.parentSessionID, let parent = try await UserToken.find(parentID, on: req.db), parent.revokedAt == nil, parent.expiresAt > Date(), parent.platformValue == .iOS else { throw Abort(.unauthorized) }
	}

	private func lockSession(_ id: UUID, on database: any Database) async throws -> UserToken? {
		guard let sqlDatabase = database as? any SQLDatabase,
		      try await sqlDatabase.select().column("id").from(UserToken.schema).where("id", .equal, id).for(.update).first() != nil else { return nil }
		return try await UserToken.find(id, on: database)
	}

	private func refreshLifetime(for platform: ClientPlatform) -> TimeInterval {
		platform == .watchOS ? 60 * 60 * 24 * 30 : 60 * 60 * 24 * 90
	}

	private func validatedClient(platform raw: String, installationID: String) throws -> ClientPlatform {
		guard let platform = ClientPlatform(rawValue: raw), platform.signupAllowed else { throw AppError(.forbidden, code: .invalidRequest, reason: "Only iOS can create accounts.", field: "platform") }; _ = try normalizedInstallation(installationID); return platform
	}

	private func validatedSessionClient(platform raw: String, installationID: String) throws -> ClientPlatform {
		guard let platform = ClientPlatform(rawValue: raw), platform.loginAllowed else { throw AppError(.forbidden, code: .invalidRequest, reason: "This client platform cannot create a session.", field: "platform") }; _ = try normalizedInstallation(installationID); return platform
	}

	private func normalizedInstallationID(_ value: String) -> String {
		value.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func normalizedInstallation(_ value: String) throws -> String {
		let result = normalizedInstallationID(value); guard !result.isEmpty, result.count <= 200 else { throw AppError(.badRequest, code: .invalidRequest, reason: "The installation identifier is invalid.", field: "installationID") }; return result
	}

	private func hashToken(_ token: String) -> String {
		SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
	}

	private func derivedDisplayName(from email: String) -> String {
		let parts = email.split(separator: "@", maxSplits: 1).first?.split(separator: ".") ?? []
		guard parts.count >= 2 else {
			return "User"
		}
		let firstName = String(parts[0]).capitalized
		let lastName = String(parts[1]).trimmingCharacters(in: .decimalDigits).capitalized
		guard !firstName.isEmpty, !lastName.isEmpty else {
			return "User"
		}
		return "\(firstName) \(lastName)"
	}
}

private struct VerificationCodeRequest: Content {
	let email: String
	let installationID: String
}

private struct VerificationRegistrationRequest: Content {
	let email: String
	let code: String
	let password: String
	let platform: String
	let installationID: String
}

private extension String {
	var sha256Digest: String {
		SHA256.hash(data: Data(utf8)).map { String(format: "%02x", $0) }.joined()
	}
}

extension RegisterRequest: Validatable {
	static func validations(_ validations: inout Validations) {
		validations.add("email", as: String.self, is: .email); validations.add("password", as: String.self, is: .count(8...))
	}
}
