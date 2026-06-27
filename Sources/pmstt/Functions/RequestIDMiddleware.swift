import Vapor

struct RequestIDMiddleware: AsyncMiddleware {
	static let headerName = "X-Request-ID"

	func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
		let requestID = request.headers.first(name: Self.headerName) ?? UUID().uuidString
		request.storage[RequestIDKey.self] = requestID
		request.logger[metadataKey: "request_id"] = .string(requestID)

		let response = try await next.respond(to: request)
		response.headers.replaceOrAdd(name: Self.headerName, value: requestID)
		return response
	}
}

private struct RequestIDKey: StorageKey {
	typealias Value = String
}

extension Request {
	var requestID: String {
		storage[RequestIDKey.self] ?? "missing-request-id"
	}
}
