import Fluent
import Foundation
import Vapor

enum ClientPlatform: String, Codable, Sendable {
	case iOS
	case iPadOS
	case macOS
	case watchOS
	case legacy

	// This is a client-declared policy identity used for capability decisions.
	// It is not hardware attestation and must not be treated as proof of origin.

	var signupAllowed: Bool {
		switch self {
			case .iOS, .iPadOS, .macOS: true
			case .watchOS, .legacy: false
		}
	}

	var loginAllowed: Bool {
		switch self {
			case .iOS, .iPadOS, .macOS: true
			case .watchOS, .legacy: false
		}
	}
}

enum Capability: String, Codable, Sendable {
	case read
	case logout
	case mutateAccount
	case mutateSettings
	case mutateOwnerTimetable
	case mutateNotifications
	case mutateLiveActivities
	case createWatchSession
}

extension ClientPlatform {
	var capabilities: [Capability] {
		switch self {
			case .iOS, .iPadOS, .macOS:
				[.read, .logout, .mutateAccount, .mutateSettings, .mutateOwnerTimetable, .mutateNotifications]
					+ (self == .iOS ? [.mutateLiveActivities, .createWatchSession] : [])
			case .watchOS:
				[.read, .logout]
			case .legacy:
				[.read, .logout]
		}
	}
}

enum SessionAuthorityResolver {
	static func validate(_ payload: UserPayload, on request: Request) async throws {
		guard let user = try await User.find(payload.sub, on: request.db) else {
			throw AppError(.notFound, code: .accountNotFound, reason: "Your account could not be found.")
		}
		try await ServerAccessModeService.requirePermittedAccount(user, on: request.db)
		guard payload.platformValue != .legacy else { return }
		guard let session = try await UserToken.find(payload.sid, on: request.db),
		      session.revokedAt == nil,
		      session.expiresAt > Date(),
		      session.$user.id == payload.sub,
		      session.platformValue == payload.platformValue,
		      session.installationID == payload.installationID
		else { throw Abort(.unauthorized) }

		if payload.platformValue == .watchOS {
			guard let parentID = session.parentSessionID,
			      let parent = try await UserToken.find(parentID, on: request.db),
			      parent.revokedAt == nil,
			      parent.expiresAt > Date(),
			      parent.platformValue == .iOS
			else { throw Abort(.unauthorized) }
		}
	}

	static func authorize(_ capability: Capability, _ payload: UserPayload, on request: Request) async throws {
		try await validate(payload, on: request)
		guard payload.platformValue.capabilities.contains(capability) else {
			throw Abort(.forbidden)
		}
	}
}

struct CapabilityMiddleware: AsyncMiddleware {
	func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
		let payload = try request.auth.require(UserPayload.self)
		try await SessionAuthorityResolver.authorize(requiredCapability(for: request), payload, on: request)
		return try await next.respond(to: request)
	}

	private func requiredCapability(for request: Request) -> Capability {
		let path = request.url.path.split(separator: "/").map(String.init)
		guard path.first == "v1" else { return .read }
		if path.dropFirst().first == "auth" {
			return path.last == "logout" ? .logout : .createWatchSession
		}
		guard request.method == .PUT || request.method == .POST || request.method == .DELETE else { return .read }
		switch path.dropFirst().first {
			case "account", "report": return .mutateAccount
			case "settings":
				return path.dropFirst(2).first == "notifications" ? .mutateNotifications : .mutateSettings
			case "events": return .mutateNotifications
			case "timetables":
				return path.dropFirst(2).first == "owner" ? .mutateOwnerTimetable : .read
			case "devices":
				if path.contains("synchronize") || (request.method == .DELETE && path == ["v1", "devices", "current"]) {
					return .read
				}
				return path.contains("live-activity-token") ? .mutateLiveActivities : .mutateNotifications
			case "notifications": return .mutateNotifications
			case "live-activities": return .mutateLiveActivities
			default: return .read
		}
	}
}
