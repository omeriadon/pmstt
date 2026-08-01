import Fluent
import Vapor

enum ServerAccessModeService {
	static func requirePermittedAccount(_ user: User, on database: any Database) async throws {
		try await requirePermittedEmail(user.email, on: database)
	}

	static func requirePermittedEmail(_ email: String?, on database: any Database) async throws {
		guard try await developmentAccessOnly(on: database) else {
			return
		}

		let normalizedEmail = email?
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		guard let normalizedEmail, AccountAuthority.systemOwnerEmails.contains(normalizedEmail) else {
			throw AppError(
				.forbidden,
				code: .developmentAccessRestricted,
				reason: "Server is being maintained. Please try again later."
			)
		}
	}

	static func developmentAccessOnly(on database: any Database) async throws -> Bool {
		try await ServerAccessMode.query(on: database)
			.first()?
			.developmentAccessOnly ?? false
	}

	static func update(
		developmentAccessOnly: Bool,
		on database: any Database
	) async throws -> ServerAccessMode {
		if let mode = try await ServerAccessMode.query(on: database).first() {
			mode.developmentAccessOnly = developmentAccessOnly
			try await mode.update(on: database)
			return mode
		}

		let mode = ServerAccessMode(developmentAccessOnly: developmentAccessOnly)
		try await mode.create(on: database)
		return mode
	}
}
