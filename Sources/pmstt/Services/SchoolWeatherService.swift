import Crypto
import Fluent
import Vapor

struct SchoolWeatherService {
	private static let latitude = -31.944462605584388
	private static let longitude = 115.8380028573902
	private static let refreshInterval: TimeInterval = 5 * 60

	func current(on request: Request) async throws -> SchoolWeatherResponse {
		let cached = try await SchoolWeatherCache.query(on: request.db).first()
		if let cached, Date().timeIntervalSince(cached.fetchedAt) < Self.refreshInterval {
			return SchoolWeatherResponse(cached, isStale: false)
		}

		do {
			let weather = try await fetch(on: request)
			let now = Date()
			if let cached {
				cached.temperatureCelsius = weather.temperature
				cached.conditionCode = weather.conditionCode
				cached.uvIndex = weather.uvIndex
				cached.observedAt = weather.asOf
				cached.fetchedAt = now
				try await cached.update(on: request.db)
				return SchoolWeatherResponse(cached, isStale: false)
			}

			let cache = SchoolWeatherCache(
				temperatureCelsius: weather.temperature,
				conditionCode: weather.conditionCode,
				uvIndex: weather.uvIndex,
				observedAt: weather.asOf,
				fetchedAt: now
			)
			try await cache.create(on: request.db)
			return SchoolWeatherResponse(cache, isStale: false)
		} catch {
			if let cached {
				request.logger.warning("WeatherKit refresh failed; returning stale weather", metadata: [
					"error": .string(error.localizedDescription),
				])
				return SchoolWeatherResponse(cached, isStale: true)
			}
			throw error
		}
	}

	private func fetch(on request: Request) async throws -> WeatherKitCurrentWeather {
		let token = try developerToken()
		let uri = URI(
			string: "https://weatherkit.apple.com/api/v1/weather/en-AU/\(Self.latitude)/\(Self.longitude)?countryCode=AU&dataSets=currentWeather&timezone=Australia%2FPerth"
		)
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		let response = try await request.client.get(uri, headers: headers)
		guard response.status == .ok else {
			throw Abort(.badGateway, reason: "WeatherKit returned HTTP \(response.status.code).")
		}
		return try response.content.decode(WeatherKitResponse.self).currentWeather
	}

	private func developerToken() throws -> String {
		guard let teamID = Environment.get("WEATHERKIT_TEAM_ID"),
		      let keyID = Environment.get("WEATHERKIT_KEY_ID"),
		      let serviceID = Environment.get("WEATHERKIT_SERVICE_ID")
		else {
			throw Abort(.serviceUnavailable, reason: "WeatherKit credentials are not configured.")
		}
		let privateKeyValue: String
		if let privateKeyPath = Environment.get("WEATHERKIT_PRIVATE_KEY_PATH") {
			privateKeyValue = try String(contentsOfFile: privateKeyPath, encoding: .utf8)
		} else if let configuredPrivateKey = Environment.get("WEATHERKIT_PRIVATE_KEY") {
			privateKeyValue = configuredPrivateKey
		} else {
			throw Abort(.serviceUnavailable, reason: "WeatherKit credentials are not configured.")
		}

		let now = Int(Date().timeIntervalSince1970)
		let header = WeatherKitTokenHeader(
			alg: "ES256",
			kid: keyID,
			id: "\(teamID).\(serviceID)"
		)
		let payload = WeatherKitTokenPayload(
			iss: teamID,
			iat: now,
			exp: now + 3600,
			sub: serviceID
		)
		let encoder = JSONEncoder()
		let headerPart = try encoder.encode(header).base64URLEncodedString()
		let payloadPart = try encoder.encode(payload).base64URLEncodedString()
		let signingInput = "\(headerPart).\(payloadPart)"
		let privateKey = try P256.Signing.PrivateKey(
			pemRepresentation: privateKeyValue.replacingOccurrences(of: "\\n", with: "\n")
		)
		let signature = try privateKey.signature(for: Data(signingInput.utf8))
		return "\(signingInput).\(signature.rawRepresentation.base64URLEncodedString())"
	}
}

struct SchoolWeatherResponse: Content {
	let temperatureCelsius: Double
	let conditionCode: String
	let uvIndex: Int
	let observedAt: Date
	let fetchedAt: Date
	let isStale: Bool

	init(_ cache: SchoolWeatherCache, isStale: Bool) {
		temperatureCelsius = cache.temperatureCelsius
		conditionCode = cache.conditionCode
		uvIndex = cache.uvIndex
		observedAt = cache.observedAt
		fetchedAt = cache.fetchedAt
		self.isStale = isStale
	}
}

private struct WeatherKitResponse: Decodable {
	let currentWeather: WeatherKitCurrentWeather
}

private struct WeatherKitCurrentWeather: Decodable {
	let asOf: Date
	let conditionCode: String
	let temperature: Double
	let uvIndex: Int
}

private struct WeatherKitTokenHeader: Encodable {
	let alg: String
	let kid: String
	let id: String
}

private struct WeatherKitTokenPayload: Encodable {
	let iss: String
	let iat: Int
	let exp: Int
	let sub: String
}

private extension Data {
	func base64URLEncodedString() -> String {
		base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}
}
