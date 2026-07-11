import NIOCore
import Vapor

struct AuthRateLimitMiddleware: AsyncMiddleware {
	private let limit: Int
	private let window: TimeInterval

	init(limit: Int = 12, window: TimeInterval = 60) {
		self.limit = limit
		self.window = window
	}

	func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
		let key = request.remoteAddress?.ipAddress ?? "unknown"
		guard await AuthRateLimiter.shared.allow(key: key, limit: limit, window: window) else {
			throw AppError(.tooManyRequests, code: .rateLimited, reason: "Too many authentication attempts. Try again shortly.")
		}
		return try await next.respond(to: request)
	}
}

private actor AuthRateLimiter {
	static let shared = AuthRateLimiter()

	private var attempts: [String: [Date]] = [:]

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
