import AsyncHTTPClient
import Fluent
import Foundation
import NIOCore
import NIOHTTP1
import Vapor

struct NotificationService {
	func sendToAdministrators(
		title: String,
		body: String,
		threadID: String,
		collapseID: String,
		on req: Request
	) async throws {
		let administrators = try await User.query(on: req.db).all()
		for administrator in administrators {
			guard administrator.resolvedAccountAuthority.isAdministrator,
			      let administratorID = administrator.id
			else {
				continue
			}

			_ = try await send(
				title: title,
				body: body,
				threadID: threadID,
				collapseID: collapseID,
				to: administratorID,
				on: req,
				notificationType: "administrationModeration"
			)
		}
	}

	static func apnsExpiration(sentAt: Date) -> Date {
		sentAt.addingTimeInterval(3 * 60)
	}

	func send(
		title: String,
		body: String,
		threadID: String? = nil,
		collapseID: String? = nil,
		to userID: UUID,
		on req: Request,
		badge: Int? = nil,
		notificationType: String? = nil
	) async throws -> Int {
		try await send(
			title: title,
			body: body,
			threadID: threadID,
			collapseID: collapseID,
			to: userID,
			on: req.db,
			logger: req.logger,
			badge: badge,
			notificationType: notificationType
		)
	}

	func send(
		title: String,
		body: String,
		threadID: String? = nil,
		collapseID: String? = nil,
		to userID: UUID,
		installationID: String,
		on req: Request,
		badge: Int? = nil,
		notificationType: String? = nil
	) async throws -> Int {
		try await send(
			title: title,
			body: body,
			threadID: threadID,
			collapseID: collapseID,
			to: userID,
			installationID: installationID,
			on: req.db,
			logger: req.logger,
			badge: badge,
			notificationType: notificationType
		)
	}

	func send(
		title: String,
		body: String,
		threadID: String? = nil,
		collapseID: String? = nil,
		to userID: UUID,
		on database: any Database,
		logger: Logger,
		badge: Int? = nil,
		notificationType: String? = nil
	) async throws -> Int {
		let devices = try await UserDevice.query(on: database)
			.filter(\.$user.$id == userID)
			.all()

		return try await send(
			title: title,
			body: body,
			threadID: threadID,
			collapseID: collapseID,
			to: userID,
			devices: devices,
			on: database,
			logger: logger,
			badge: badge,
			notificationType: notificationType
		)
	}

	func send(
		title: String,
		body: String,
		threadID: String? = nil,
		collapseID: String? = nil,
		to userID: UUID,
		installationID: String,
		on database: any Database,
		logger: Logger,
		badge: Int? = nil,
		notificationType: String? = nil
	) async throws -> Int {
		let devices = try await UserDevice.query(on: database)
			.filter(\.$user.$id == userID)
			.filter(\.$installationID == installationID)
			.all()

		return try await send(
			title: title,
			body: body,
			threadID: threadID,
			collapseID: collapseID,
			to: userID,
			devices: devices,
			on: database,
			logger: logger,
			badge: badge,
			notificationType: notificationType
		)
	}

	private func send(
		title: String,
		body: String,
		threadID: String?,
		collapseID: String?,
		to userID: UUID,
		devices: [UserDevice],
		on database: any Database,
		logger: Logger,
		broadcastID: UUID? = nil,
		isDeletion: Bool = false,
		badge: Int? = nil,
		notificationType: String? = nil
	) async throws -> Int {
		guard !devices.isEmpty else {
			return 0
		}

		let config = try configuration()
		let authorization = try await makeJWT(config: config)
		let expiration = Self.apnsExpiration(sentAt: Date())

		var deliveredCount = 0
		var sentTokens = Set<String>()

		for device in devices {
			guard let token = device.apnsToken else {
				continue
			}
			let tokenKey = "\(device.isDebug):\(token)"
			guard sentTokens.insert(tokenKey).inserted else {
				logger.warning(
					"Skipping duplicate APNs token",
					metadata: [
						"user_id": .string(userID.uuidString),
						"device_id": .string(device.id?.uuidString ?? "unknown"),
					]
				)
				continue
			}

			do {
				let response = try await send(
					title: title,
					subtitle: nil,
					body: body,
					threadID: threadID,
					collapseID: collapseID,
					token: token,
					isDebug: device.isDebug,
					authorization: authorization,
					config: config,
					expiration: expiration,
					broadcastID: broadcastID,
					isDeletion: isDeletion,
					badge: badge,
					notificationType: notificationType
				)

				logger.info("APNs notification response", metadata: [
					"user_id": .string(userID.uuidString),
					"device_id": .string(device.id?.uuidString ?? "unknown"),
					"status": .stringConvertible(response.status.code),
					"reason": .string(response.reason ?? "none"),
					"collapse_id": .string(collapseID ?? "none"),
					"apns_expiration": .stringConvertible(Int(expiration.timeIntervalSince1970)),
				])

				switch response.status {
					case .ok:
						deliveredCount += 1

					case .badRequest, .unauthorized, .forbidden, .notFound, .gone:
						device.apnsToken = nil
						try await device.save(on: database)

					default:
						logger.error(
							"APNs rejected a notification",
							metadata: [
								"status": .stringConvertible(response.status.code),
								"reason": .string(response.reason ?? "none"),
								"user_id": .string(userID.uuidString),
							]
						)
				}
			} catch {
				logger.report(
					error: error,
					metadata: [
						"notification_user_id": .string(userID.uuidString),
					]
				)
			}
		}

		return deliveredCount
	}

	func broadcast(
		title: String,
		subtitle: String?,
		body: String?,
		sender: User,
		threadID: String? = nil,
		on req: Request
	) async throws -> BroadcastNotificationResponse {
		let record = BroadcastNotificationRecord(
			senderAccountID: sender.id,
			senderEmail: sender.email ?? "unknown",
			senderAuthority: sender.resolvedAccountAuthority,
			audience: "broadcastNotificationSubscribers",
			title: title,
			subtitle: subtitle,
			body: body
		)
		try await record.create(on: req.db)

		do {
			let users = try await User.query(on: req.db).all()
			let eligibleUserIDs = try users.compactMap { user -> UUID? in
				guard let userID = user.id else {
					return nil
				}

				let settings = try JSONDecoder().decode(
					AccountSettings.self,
					from: user.settingsData
				)

				return settings.broadcastNotificationsEnabled ? userID : nil
			}
			let eligibleDevices: [UserDevice]
			if eligibleUserIDs.isEmpty {
				eligibleDevices = []
			} else {
				let devices = try await UserDevice.query(on: req.db)
					.filter(\.$user.$id ~~ eligibleUserIDs)
					.all()
				eligibleDevices = devices.filter { $0.apnsToken != nil }
			}

			record.eligibleDeviceCount = eligibleDevices.count
			try await record.update(on: req.db)

			guard !eligibleDevices.isEmpty else {
				record.deliveryState = .completed
				try await record.update(on: req.db)
				return try response(for: record)
			}

			let config = try configuration()
			let authorization = try await makeJWT(config: config)
			let expiration = Self.apnsExpiration(sentAt: Date())
			let collapseID = "broadcast-\(UUID().uuidString)"

			for device in eligibleDevices {
				guard let token = device.apnsToken else {
					continue
				}

				do {
					let status = try await send(
						title: title,
						subtitle: subtitle,
						body: body ?? "",
						threadID: threadID,
						collapseID: collapseID,
						token: token,
						isDebug: device.isDebug,
						authorization: authorization,
						config: config,
						expiration: expiration,
						broadcastID: record.requireID()
					)

					req.logger.info("APNs broadcast response", metadata: [
						"device_id": .string(device.id?.uuidString ?? "unknown"),
						"status": .stringConvertible(status.status.code),
						"reason": .string(status.reason ?? "none"),
						"collapse_id": .string(collapseID),
						"apns_expiration": .stringConvertible(Int(expiration.timeIntervalSince1970)),
					])

					switch status.status {
						case .ok:
							record.deliveredDeviceCount += 1

						case .badRequest, .unauthorized, .forbidden, .notFound, .gone:
							device.apnsToken = nil
							try await device.save(on: req.db)
							record.invalidatedDeviceCount += 1

						default:
							record.failedDeviceCount += 1

							req.logger.error(
								"APNs rejected broadcast notification",
								metadata: [
									"status": .stringConvertible(status.status.code),
									"reason": .string(status.reason ?? "none"),
								]
							)
					}
				} catch {
					record.failedDeviceCount += 1
					req.logger.report(error: error)
				}
			}

			record.deliveryState = .completed
			try await record.update(on: req.db)
			return try response(for: record)
		} catch {
			record.deliveryState = .failed
			record.failureSummary = String(describing: error)
			try? await record.update(on: req.db)
			throw error
		}
	}

	func deleteBroadcast(_ record: BroadcastNotificationRecord, on req: Request) async throws {
		let devices = try await UserDevice.query(on: req.db).all()
		guard !devices.isEmpty else {
			return
		}

		let config = try configuration()
		let authorization = try await makeJWT(config: config)
		let expiration = Self.apnsExpiration(sentAt: Date())
		let broadcastID = try record.requireID()
		var sentTokens = Set<String>()

		for device in devices {
			guard let token = device.apnsToken else {
				continue
			}

			let tokenKey = "\(device.isDebug):\(token)"
			guard sentTokens.insert(tokenKey).inserted else {
				continue
			}

			let response = try await send(
				title: "",
				subtitle: nil,
				body: "",
				threadID: nil,
				collapseID: "broadcast-delete-\(broadcastID.uuidString)",
				token: token,
				isDebug: device.isDebug,
				authorization: authorization,
				config: config,
				expiration: expiration,
				broadcastID: broadcastID,
				isDeletion: true
			)

			if [.badRequest, .unauthorized, .forbidden, .notFound, .gone].contains(response.status) {
				device.apnsToken = nil
				try await device.save(on: req.db)
			}
		}
	}

	private func response(for record: BroadcastNotificationRecord) throws -> BroadcastNotificationResponse {
		try BroadcastNotificationResponse(
			id: record.requireID(),
			eligibleDeviceCount: record.eligibleDeviceCount,
			deliveredDeviceCount: record.deliveredDeviceCount,
			invalidatedDeviceCount: record.invalidatedDeviceCount,
			failedDeviceCount: record.failedDeviceCount
		)
	}

	private func send(
		title: String,
		subtitle: String?,
		body: String,
		threadID: String?,
		collapseID: String?,
		token: String,
		isDebug: Bool,
		authorization: String,
		config: APNSConfig,
		expiration: Date,
		broadcastID: UUID? = nil,
		isDeletion: Bool = false,
		badge: Int? = nil,
		notificationType: String? = nil
	) async throws -> APNSClient.Response {
		let host = isDebug
			? "api.sandbox.push.apple.com"
			: "api.push.apple.com"

		var request = HTTPClientRequest(
			url: "https://\(host)/3/device/\(token)"
		)

		request.method = .POST

		request.headers.add(
			name: "apns-push-type",
			value: isDeletion ? "background" : "alert"
		)

		request.headers.add(
			name: "apns-priority",
			value: isDeletion ? "5" : "10"
		)

		request.headers.add(
			name: "apns-topic",
			value: config.bundleId
		)

		request.headers.add(
			name: "apns-collapse-id",
			value: collapseID ?? UUID().uuidString
		)

		request.headers.add(
			name: "apns-expiration",
			value: String(Int(expiration.timeIntervalSince1970))
		)

		request.headers.add(
			name: "authorization",
			value: "bearer \(authorization)"
		)

		let payload = NotificationPayload(
			broadcastID: broadcastID,
			notificationType: notificationType,
			aps: .init(
				alert: isDeletion ? nil : .init(
					title: title,
					subtitle: subtitle,
					body: body
				),
				sound: isDeletion ? nil : "default",
				threadID: threadID,
				contentAvailable: isDeletion ? 1 : nil,
				badge: isDeletion ? nil : badge
			)
		)

		request.body = try .bytes(
			ByteBuffer(
				data: JSONEncoder().encode(payload)
			)
		)

		return try await APNSClient().send(request: request)
	}

	private func configuration() throws -> APNSConfig {
		guard
			let teamID = Environment.get("APNS_TEAM_ID"),
			let keyID = Environment.get("APNS_KEY_ID"),
			let privateKeyPath = Environment.get("APNS_PRIVATE_KEY_PATH")
		else {
			throw AppError(
				.serviceUnavailable,
				code: .internalServerError,
				reason: "APNs is not configured."
			)
		}

		return APNSConfig(
			teamId: teamID,
			keyId: keyID,
			bundleId: Environment.get("APNS_BUNDLE_ID")
				?? "com.omeriadon.Timetable",
			privateKeyPath: privateKeyPath
		)
	}
}

private struct NotificationPayload: Encodable {
	let broadcastID: UUID?
	let notificationType: String?
	let aps: APS

	enum CodingKeys: String, CodingKey {
		case broadcastID = "broadcast-id"
		case notificationType = "notification-type"
		case aps
	}

	struct APS: Encodable {
		let alert: Alert?
		let sound: String?
		let threadID: String?
		let contentAvailable: Int?
		let badge: Int?

		enum CodingKeys: String, CodingKey {
			case alert
			case sound
			case threadID = "thread-id"
			case contentAvailable = "content-available"
			case badge
		}
	}

	struct Alert: Encodable {
		let title: String
		let subtitle: String?
		let body: String
	}
}
