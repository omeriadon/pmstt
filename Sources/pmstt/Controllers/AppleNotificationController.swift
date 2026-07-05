import Fluent
import JWT
import Vapor

struct AppleNotificationController: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		routes.post("v1", "auth", "apple", "notifications", use: receiveNotification)
	}

	func receiveNotification(req: Request) async throws -> HTTPStatus {
		let body = try req.content.decode(AppleServerNotificationRequest.self)
		let notification: AppleServerNotificationPayload

		do {
			let keys = try await req.application.jwt.apple.keys(on: req)
			notification = try await keys.verify(body.payload, as: AppleServerNotificationPayload.self)
			if let applicationIdentifier = req.application.jwt.apple.applicationIdentifier {
				try notification.audience.verifyIntendedAudience(includes: applicationIdentifier)
			}
		} catch {
			req.logger.warning("Rejected invalid Sign in with Apple server notification")
			throw Abort(.unauthorized)
		}

		guard let user = try await User.query(on: req.db)
			.filter(\.$appleSubject == notification.events.subject)
			.first()
		else {
			return .ok
		}

		switch notification.events.type {
			case .emailEnabled:
				user.appleEmailForwardingEnabled = true
				try await user.save(on: req.db)
			case .emailDisabled:
				user.appleEmailForwardingEnabled = false
				try await user.save(on: req.db)
			case .consentRevoked:
				let userID = try user.requireID()
				try await UserToken.query(on: req.db)
					.filter(\.$user.$id == userID)
					.delete()
				user.appleSubject = nil
				user.appleAuthorizationRevokedAt = Date()
				try await user.save(on: req.db)
			case .accountDelete:
				try await user.delete(on: req.db)
			case .unknown:
				req.logger.notice("Ignored unknown Sign in with Apple event", metadata: ["event_type": .string(notification.events.rawType)])
		}

		return .ok
	}
}

private struct AppleServerNotificationRequest: Content {
	let payload: String
}

private struct AppleServerNotificationPayload: JWTPayload {
	let issuer: IssuerClaim
	let audience: AudienceClaim
	let expires: ExpirationClaim
	let issuedAt: IssuedAtClaim
	let id: IDClaim
	let events: AppleServerNotificationEvent

	private enum CodingKeys: String, CodingKey {
		case events
		case issuer = "iss"
		case audience = "aud"
		case expires = "exp"
		case issuedAt = "iat"
		case id = "jti"
	}

	func verify(using _: some JWTAlgorithm) throws {
		guard issuer.value == "https://appleid.apple.com" else {
			throw JWTError.claimVerificationFailure(failedClaim: issuer, reason: "Notification not provided by Apple")
		}
		try expires.verifyNotExpired()
	}
}

private struct AppleServerNotificationEvent: Codable {
	let rawType: String
	let subject: String
	let email: String?
	let isPrivateEmail: String?
	let eventTime: Int?

	var type: EventType {
		EventType(rawValue: rawType) ?? .unknown
	}

	private enum CodingKeys: String, CodingKey {
		case rawType = "type"
		case subject = "sub"
		case email
		case isPrivateEmail = "is_private_email"
		case eventTime = "event_time"
	}

	enum EventType: String {
		case emailEnabled = "email-enabled"
		case emailDisabled = "email-disabled"
		case consentRevoked = "consent-revoked"
		case accountDelete = "account-delete"
		case unknown
	}
}
