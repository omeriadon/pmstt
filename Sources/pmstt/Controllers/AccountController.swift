import Fluent
import Vapor

struct AccountController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		let account = routes.grouped("v1", "account")
		let protected = account.grouped(SessionAuthenticator(), UserPayload.guardMiddleware(), CapabilityMiddleware())

		protected.get(use: getAccount)
		protected.put(use: updateAccount)
		protected.delete(use: deleteAccount)
	}

	func getAccount(req: Request) async throws -> UserAccountResponse {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}

		return try UserAccountResponse(
			id: user.requireID(),
			email: user.email,
			displayName: user.displayName,
			createdAt: user.createdAt
		)
	}

	func updateAccount(req: Request) async throws -> UserAccountResponse {
		let payload = try req.auth.require(UserPayload.self)
		let body = try req.content.decode(UpdateAccountRequest.self)

		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}

		if let displayName = body.displayName, !displayName.isEmpty {
			user.displayName = displayName
		}

		if let email = body.email {
			guard !email.isEmpty, email.contains("@") else {
				throw AppError(.badRequest, code: .invalidRequest, reason: "Invalid email format.", field: "email")
			}
			let normalizedEmail = email.lowercased()
			if normalizedEmail != user.email {
				let existing = try await User.query(on: req.db)
					.filter(\.$email == normalizedEmail)
					.first()
				if existing != nil {
					throw AppError(.conflict, code: .emailAlreadyExists, reason: "Email is already registered.", field: "email")
				}
				user.email = normalizedEmail
			}
		}

		try await user.save(on: req.db)

		return try UserAccountResponse(
			id: user.requireID(),
			email: user.email,
			displayName: user.displayName,
			createdAt: user.createdAt
		)
	}

	func deleteAccount(req: Request) async throws -> HTTPStatus {
		let payload = try req.auth.require(UserPayload.self)
		guard let user = try await User.find(payload.sub, on: req.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "User not found.")
		}

		await SchoolDayActivityCoordinator().endActivities(forUserID: payload.sub, database: req.db, logger: req.logger)
		try await user.delete(on: req.db)
		return .noContent
	}
}
