import AsyncHTTPClient
import Fluent
import Foundation
import NIOCore
import NIOHTTP1
import Vapor

struct NotificationService {
	func send(title: String, body: String, to userID: UUID, on req: Request) async throws -> Int {
		let devices = try await UserDevice.query(on: req.db).filter(\.$user.$id == userID).all()
		guard !devices.isEmpty else { return 0 }
		let config = try configuration()
		let authorization = try await makeJWT(config: config)
		var deliveredCount = 0

		for device in devices {
			guard let token = device.apnsToken else { continue }
			let status = try await send(title: title, body: body, token: token, authorization: authorization, config: config)
			switch status {
				case .ok:
					deliveredCount += 1
				case .badRequest, .gone:
					device.apnsToken = nil
					try await device.save(on: req.db)
				default:
					throw AppError(.badGateway, code: .internalServerError, reason: "APNs rejected the notification with status \(status.code).")
			}
		}
		return deliveredCount
	}

	private func send(
		title: String,
		body: String,
		token: String,
		authorization: String,
		config: APNSConfig
	) async throws -> HTTPResponseStatus {
		let host = Environment.get("APNS_USE_SANDBOX") == "true" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com"
		var request = HTTPClientRequest(url: "\(host)/3/device/\(token)")
		request.method = .POST
		request.headers.add(name: "apns-push-type", value: "alert")
		request.headers.add(name: "apns-priority", value: "10")
		request.headers.add(name: "apns-topic", value: config.bundleId)
		request.headers.add(name: "authorization", value: "bearer \(authorization)")
		request.body = try .bytes(ByteBuffer(data: JSONEncoder().encode(
			NotificationPayload(aps: .init(alert: .init(title: title, body: body), sound: "default"))
		)))
		return try await APNSClient().send(request: request)
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

private struct NotificationPayload: Encodable {
	let aps: APS

	struct APS: Encodable {
		let alert: Alert
		let sound: String
	}

	struct Alert: Encodable {
		let title: String
		let body: String
	}
}
