import NIOCore
import Vapor

struct AuthRateLimitMiddleware: AsyncMiddleware {
	private let limit: Int
	private let window: TimeInterval

	init(
		limit: Int = AuthRateLimitPolicy.maxAttemptsPerIP,
		window: TimeInterval = AuthRateLimitPolicy.window
	) {
		self.limit = limit
		self.window = window
	}

	func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
		let key = request.remoteAddress?.ipAddress ?? "unknown"
		guard await AuthRateLimiter.shared.allow(key: key, limit: limit, window: window) else {
			throw AppError(.tooManyRequests, code: .rateLimited, reason: "Too many authentication attempts. Try again after the daily limit resets.")
		}
		return try await next.respond(to: request)
	}
}

enum AuthRateLimitPolicy {
	static let maxAttemptsPerIP = 100
	static let window: TimeInterval = 60 * 60 * 24
}

actor AuthRateLimiter {
	static let shared = AuthRateLimiter()

	private var attempts: [String: [Date]] = [:]

	func reset() {
		attempts.removeAll()
	}

	func allow(key: String, limit: Int, window: TimeInterval, now: Date = .now) -> Bool {
		let cutoff = now.addingTimeInterval(-window)
		let recent = (attempts[key] ?? []).filter { $0 > cutoff }
		guard recent.count < limit else {
			attempts[key] = recent
			return false
		}
		attempts[key] = recent + [now]
		if attempts.count > 10000 {
			attempts = attempts.filter { $0.value.contains { $0 > cutoff } }
		}
		return true
	}
}

extension AuthRateLimiter {
	func allowVerificationRequest(
		normalizedEmail: String,
		installationID: String,
		sourceIP: String,
		now: Date = .now
	) -> Bool {
		let requests = [
			("verification-email:\(normalizedEmail)", 3, 600.0),
			("verification-installation:\(installationID)", 5, 600.0),
			("verification-ip:\(sourceIP)", 10, 600.0),
		]

		for (key, limit, window) in requests {
			guard allow(key: key, limit: limit, window: window, now: now) else {
				return false
			}
		}

		return true
	}
}
