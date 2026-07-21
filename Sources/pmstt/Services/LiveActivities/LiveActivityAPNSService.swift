import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import NIOHTTP1
import Vapor

struct LiveActivityAPNSService {
	struct Result {
		let status: HTTPResponseStatus
		let reason: String?

		var succeeded: Bool {
			status == .ok
		}

		var permanentlyInvalidToken: Bool {
			[.badRequest, .unauthorized, .forbidden, .notFound, .gone].contains(status)
		}
	}

	func sendStart(
		to token: String,
		isDebug: Bool,
		attributes: SchoolDayActivityAttributesPayload,
		projection: SchoolDayActivityProjection,
		logger: Logger
	) async throws -> Result {
		let now = Int(Date().timeIntervalSince1970)
		let payload = LiveActivityPayload(aps: .init(
			timestamp: now,
			event: .start,
			contentState: projection.content,
			staleDate: projection.staleDate.map { Int($0.timeIntervalSince1970) },
			dismissalDate: nil,
			attributesType: "SchoolDayActivityAttributes",
			attributes: attributes,
			inputPushToken: 1,
			alert: nil
		))
		return try await send(payload, to: token, isDebug: isDebug, priority: 10, collapseID: "live-activity-\(attributes.activityKey)-start", logger: logger)
	}

	func sendUpdate(to token: String, activityKey: String, isDebug: Bool, projection: SchoolDayActivityProjection, logger: Logger) async throws -> Result {
		let payload = LiveActivityPayload(aps: .init(
			timestamp: Int(Date().timeIntervalSince1970),
			event: .update,
			contentState: projection.content,
			staleDate: projection.staleDate.map { Int($0.timeIntervalSince1970) },
			dismissalDate: nil,
			attributesType: nil,
			attributes: nil,
			inputPushToken: nil,
			alert: nil
		))
		return try await send(payload, to: token, isDebug: isDebug, priority: 5, collapseID: "live-activity-\(activityKey)-update", logger: logger)
	}

	func sendEnd(to token: String, activityKey: String, isDebug: Bool, projection: SchoolDayActivityProjection, logger: Logger) async throws -> Result {
		let payload = LiveActivityPayload(aps: .init(
			timestamp: Int(Date().timeIntervalSince1970),
			event: .end,
			contentState: projection.content,
			staleDate: nil,
			dismissalDate: Int(Date().addingTimeInterval(30 * 60).timeIntervalSince1970),
			attributesType: nil,
			attributes: nil,
			inputPushToken: nil,
			alert: nil
		))
		return try await send(payload, to: token, isDebug: isDebug, priority: 5, collapseID: "live-activity-\(activityKey)-end", logger: logger)
	}

	private func send(_ payload: LiveActivityPayload, to token: String, isDebug: Bool, priority: Int, collapseID: String, logger: Logger) async throws -> Result {
		let config = try configuration()
		let authorization = try await makeJWT(config: config)
		let host = isDebug ? "api.sandbox.push.apple.com" : "api.push.apple.com"
		var request = HTTPClientRequest(url: "https://\(host)/3/device/\(token)")
		request.method = .POST
		request.headers.add(name: "apns-push-type", value: "liveactivity")
		request.headers.add(name: "apns-priority", value: String(priority))
		request.headers.add(name: "apns-topic", value: "\(config.bundleId).push-type.liveactivity")
		request.headers.add(name: "apns-collapse-id", value: collapseID)
		request.headers.add(name: "authorization", value: "bearer \(authorization)")
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		request.body = try .bytes(ByteBuffer(data: encoder.encode(payload)))
		let response = try await APNSClient().send(request: request)
		logger.info("APNs Live Activity response", metadata: [
			"status": .stringConvertible(response.status.code),
			"reason": .string(response.reason ?? "none"),
			"collapse_id": .string(collapseID),
			"event": .string(payload.aps.event.rawValue),
		])
		return Result(status: response.status, reason: response.reason)
	}

	private func configuration() throws -> APNSConfig {
		guard let teamID = Environment.get("APNS_TEAM_ID"),
		      let keyID = Environment.get("APNS_KEY_ID"),
		      let privateKeyPath = Environment.get("APNS_PRIVATE_KEY_PATH")
		else {
			throw AppError(.serviceUnavailable, code: .internalServerError, reason: "APNs is not configured.")
		}
		return APNSConfig(
			teamId: teamID,
			keyId: keyID,
			bundleId: Environment.get("APNS_BUNDLE_ID") ?? "com.omeriadon.Timetable",
			privateKeyPath: privateKeyPath
		)
	}
}
