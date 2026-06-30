import AsyncHTTPClient
import Fluent
import Foundation
import NIOCore
import NIOHTTP1
import Vapor

enum WalletPushService {
	static func sendUpdate(for serialNumber: String, req: Request) async throws {
		let registrations = try await PassRegistration.query(on: req.db).filter(\.$serialNumber == serialNumber).all()
		guard !registrations.isEmpty else { return }
		guard let teamID = Environment.get("APNS_TEAM_ID"), let keyID = Environment.get("APNS_KEY_ID"), let privateKeyPath = Environment.get("APNS_PRIVATE_KEY_PATH") else { return }
		let config = APNSConfig(teamId: teamID, keyId: keyID, bundleId: Environment.get("PASS_TYPE_IDENTIFIER") ?? "pass.com.omeriadon.Timetable", privateKeyPath: privateKeyPath)
		let authorization = try await makeJWT(config: config)
		let host = Environment.get("APNS_USE_SANDBOX") == "true" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com"
		for registration in registrations {
			var request = HTTPClientRequest(url: "\(host)/3/device/\(registration.pushToken)")
			request.method = .POST
			request.headers.add(name: "apns-push-type", value: "background")
			request.headers.add(name: "apns-priority", value: "5")
			request.headers.add(name: "apns-topic", value: config.bundleId)
			request.headers.add(name: "authorization", value: "bearer \(authorization)")
			request.body = .bytes(ByteBuffer(string: "{}"))
			let status = try await APNSClient().send(request: request)
			if status == .gone || status == .badRequest { try await registration.delete(on: req.db) }
		}
	}
}
