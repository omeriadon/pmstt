import AsyncHTTPClient
import Fluent
import Foundation
import NIOCore
import NIOHTTP1
import Vapor

struct NotificationService {
	func send(title: String, body: String, to userID: UUID, on req: Request) async throws -> Int {
		try await send(title: title, body: body, to: userID, on: req.db, logger: req.logger)
	}

	func send(title: String, body: String, to userID: UUID, installationID: String, on req: Request) async throws -> Int {
		try await send(title: title, body: body, to: userID, installationID: installationID, on: req.db, logger: req.logger)
	}

	func send(title: String, body: String, to userID: UUID, on database: any Database, logger: Logger) async throws -> Int {
		let devices = try await UserDevice.query(on: database).filter(\.$user.$id == userID).all()
		return try await send(title: title, body: body, to: userID, devices: devices, on: database, logger: logger)
	}

	func send(title: String, body: String, to userID: UUID, installationID: String, on database: any Database, logger: Logger) async throws -> Int {
		let devices = try await UserDevice.query(on: database)
			.filter(\.$user.$id == userID)
			.filter(\.$installationID == installationID)
			.all()
		return try await send(title: title, body: body, to: userID, devices: devices, on: database, logger: logger)
	}

	private func send(title: String, body: String, to userID: UUID, devices: [UserDevice], on database: any Database, logger: Logger) async throws -> Int {
		guard !devices.isEmpty else { return 0 }
		let config = try configuration()
		let authorization = try await makeJWT(config: config)
		var deliveredCount = 0

		for device in devices {
			guard let token = device.apnsToken else { continue }
			do {
				let status = try await send(title: title, subtitle: nil, body: body, token: token, isDebug: device.isDebug, authorization: authorization, config: config)
				switch status {
					case .ok:
						deliveredCount += 1
					case .badRequest, .gone:
						device.apnsToken = nil
						try await device.save(on: database)
					default:
						logger.error("APNs rejected a notification", metadata: ["status": .stringConvertible(status.code), "user_id": .string(userID.uuidString)])
				}
			} catch {
				logger.report(error: error, metadata: ["notification_user_id": .string(userID.uuidString)])
			}
		}
		return deliveredCount
	}

	func broadcast(title: String, subtitle: String, body: String, on req: Request) async throws -> BroadcastNotificationResponse {
		let users = try await User.query(on: req.db).all()
		var eligibleUserIDs: [UUID] = []
		for user in users {
			guard let userID = user.id else { continue }
			let settings = try JSONDecoder().decode(AccountSettings.self, from: user.settingsData)
			if settings.broadcastNotificationsEnabled {
				eligibleUserIDs.append(userID)
			}
		}

		guard !eligibleUserIDs.isEmpty else {
			return BroadcastNotificationResponse(eligibleDeviceCount: 0, deliveredDeviceCount: 0, invalidatedDeviceCount: 0, failedDeviceCount: 0)
		}

		let devices = try await UserDevice.query(on: req.db)
			.filter(\.$user.$id ~~ eligibleUserIDs)
			.all()
		let eligibleDevices = devices.filter { $0.apnsToken != nil }
		guard !eligibleDevices.isEmpty else {
			return BroadcastNotificationResponse(eligibleDeviceCount: 0, deliveredDeviceCount: 0, invalidatedDeviceCount: 0, failedDeviceCount: 0)
		}

		let config = try configuration()
		let authorization = try await makeJWT(config: config)
		var deliveredCount = 0
		var invalidatedCount = 0
		var failedCount = 0

		for device in eligibleDevices {
			guard let token = device.apnsToken else { continue }
			do {
				let status = try await send(title: title, subtitle: subtitle, body: body, token: token, isDebug: device.isDebug, authorization: authorization, config: config)
				switch status {
					case .ok:
						deliveredCount += 1
					case .badRequest, .gone:
						device.apnsToken = nil
						try await device.save(on: req.db)
						invalidatedCount += 1
					default:
						failedCount += 1
						req.logger.error("APNs rejected broadcast notification with status \(status.code).")
				}
			} catch {
				failedCount += 1
				req.logger.report(error: error)
			}
		}

		return BroadcastNotificationResponse(
			eligibleDeviceCount: eligibleDevices.count,
			deliveredDeviceCount: deliveredCount,
			invalidatedDeviceCount: invalidatedCount,
			failedDeviceCount: failedCount
		)
	}

	private func send(
		title: String,
		subtitle: String?,
		body: String,
		token: String,
		isDebug: Bool,
		authorization: String,
		config: APNSConfig
	) async throws -> HTTPResponseStatus {
		let host = isDebug ? "api.sandbox.push.apple.com" : "api.push.apple.com"
		var request = HTTPClientRequest(url: "https://\(host)/3/device/\(token)")
		request.method = .POST
		request.headers.add(name: "apns-push-type", value: "alert")
		request.headers.add(name: "apns-priority", value: "10")
		request.headers.add(name: "apns-topic", value: config.bundleId)
		request.headers.add(name: "authorization", value: "bearer \(authorization)")
		request.body = try .bytes(ByteBuffer(data: JSONEncoder().encode(
			NotificationPayload(aps: .init(alert: .init(title: title, subtitle: subtitle, body: body), sound: "default"))
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
		let subtitle: String?
		let body: String
	}
}
