import Crypto
import Fluent
import JWT
import Vapor

struct AuthController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let auth = routes.grouped("v1", "auth")
		auth.post("register", use: register)
		auth.post("login", use: login)
		auth.post("refresh", use: refresh)

		let protected = auth.grouped(UserPayload.authenticator(), UserPayload.guardMiddleware())
		protected.delete("logout", use: logout)
	}

	// MARK: - Handlers

	func register(req: Request) async throws -> TokenResponse {
		// Validate request
		try RegisterRequest.validate(content: req)
		let body = try req.content.decode(RegisterRequest.self)

		guard !body.email.isEmpty, body.email.contains("@") else {
			throw Abort(.badRequest, reason: "Invalid email format.")
		}

		guard body.password.count >= 8 else {
			throw Abort(.badRequest, reason: "Password must be at least 8 characters long.")
		}

		// Check if user already exists
		let existing = try await User.query(on: req.db)
			.filter(\.$email == body.email.lowercased())
			.first()

		if existing != nil {
			throw Abort(.conflict, reason: "Email is already registered.")
		}

		// Create user
		let passwordHash = try req.password.hash(body.password)
		let user = User(
			email: body.email,
			passwordHash: passwordHash,
			displayName: body.displayName
		)

		try await user.save(on: req.db)

		return try await generateTokens(for: user, on: req)
	}

	func login(req: Request) async throws -> TokenResponse {
		let body = try req.content.decode(LoginRequest.self)

		// Find user
		guard let user = try await User.query(on: req.db)
			.filter(\.$email == body.email.lowercased())
			.first()
		else {
			throw Abort(.unauthorized, reason: "Invalid email or password.")
		}

		// Verify password
		let isPasswordValid = try req.password.verify(body.password, created: user.passwordHash)
		guard isPasswordValid else {
			throw Abort(.unauthorized, reason: "Invalid email or password.")
		}

		return try await generateTokens(for: user, on: req)
	}

	func refresh(req: Request) async throws -> TokenResponse {
		let body = try req.content.decode(RefreshRequest.self)
		let tokenHash = hashToken(body.refreshToken)

		// Find active, unexpired token
		guard let userToken = try await UserToken.query(on: req.db)
			.filter(\.$tokenHash == tokenHash)
			.with(\.$user)
			.first()
		else {
			throw Abort(.unauthorized, reason: "Invalid or expired session.")
		}

		guard userToken.expiresAt > Date() else {
			try await userToken.delete(on: req.db)
			throw Abort(.unauthorized, reason: "Session has expired.")
		}

		// Rotate token: delete old, create new
		try await userToken.delete(on: req.db)

		return try await generateTokens(for: userToken.user, on: req)
	}

	func logout(req: Request) async throws -> HTTPStatus {
		// Log out needs to revoke the specific refresh token. We expect it in the body.
		struct LogoutBody: Decodable {
			let refreshToken: String
		}

		let body = try req.content.decode(LogoutBody.self)
		let tokenHash = hashToken(body.refreshToken)

		if let userToken = try await UserToken.query(on: req.db)
			.filter(\.$tokenHash == tokenHash)
			.first()
		{
			// Verify it belongs to the authenticated user
			let payload = try req.auth.require(UserPayload.self)
			if userToken.$user.id == payload.sub {
				try await userToken.delete(on: req.db)
			}
		}

		return .noContent
	}

	// MARK: - Helpers

	private func generateTokens(for user: User, on req: Request) async throws -> TokenResponse {
		let userID = try user.requireID()

		// Generate access token (stateless JWT expiring in 15 minutes)
		let payload = UserPayload(
			sub: userID,
			email: user.email,
			exp: .init(value: Date().addingTimeInterval(15 * 60))
		)
		let accessToken = try await req.jwt.sign(payload)

		// Generate long-lived rotating refresh token (expiring in 30 days)
		let rawRefreshToken = generateRandomToken()
		let tokenHash = hashToken(rawRefreshToken)
		let expiresAt = Date().addingTimeInterval(60 * 60 * 24 * 90) // 90 days

		let userToken = UserToken(
			tokenHash: tokenHash,
			userID: userID,
			expiresAt: expiresAt
		)
		try await userToken.save(on: req.db)

		let profile = UserProfileResponse(
			id: userID,
			email: user.email,
			displayName: user.displayName,
			createdAt: user.createdAt
		)

		return TokenResponse(
			accessToken: accessToken,
			refreshToken: rawRefreshToken,
			user: profile
		)
	}

	private func hashToken(_ token: String) -> String {
		let hash = SHA256.hash(data: Data(token.utf8))
		return hash.compactMap { String(format: "%02x", $0) }.joined()
	}

	private func generateRandomToken() -> String {
		let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
		return Data(bytes).base64EncodedString()
	}
}

// MARK: - Validation

extension RegisterRequest: Validatable {
	static func validations(_ validations: inout Validations) {
		validations.add("email", as: String.self, is: .email)
		validations.add("password", as: String.self, is: .count(8...))
	}
}
