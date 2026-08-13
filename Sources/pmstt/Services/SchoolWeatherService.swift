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
				cached.precipitationChance = weather.precipitationChance
				cached.observedAt = weather.asOf
				cached.fetchedAt = now
				try await cached.update(on: request.db)
				return SchoolWeatherResponse(cached, isStale: false)
			}

			let cache = SchoolWeatherCache(
				temperatureCelsius: weather.temperature,
				conditionCode: weather.conditionCode,
				uvIndex: weather.uvIndex,
				precipitationChance: weather.precipitationChance,
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

	func daily(for date: SchoolCalendarDate, on request: Request) async throws -> SchoolWeatherResponse? {
		guard let interval = dateInterval(for: date) else {
			return nil
		}

		let token = try developerToken()
		let uri = weatherURI(
			dataSets: "forecastDaily",
			dailyStart: interval.start,
			dailyEnd: interval.end
		)
		let response = try await weatherKitResponse(for: uri, token: token, on: request)
		guard let day = response.forecastDaily?.days.first else {
			return nil
		}

		return SchoolWeatherResponse(day: day)
	}

	private func fetch(on request: Request) async throws -> CurrentSchoolWeather {
		let token = try developerToken()
		let uri = weatherURI(
			dataSets: "currentWeather,forecastDaily"
		)
		let weather = try await weatherKitResponse(for: uri, token: token, on: request)
		guard let current = weather.currentWeather,
		      let today = weather.forecastDaily?.days.first
		else {
			throw Abort(.badGateway, reason: "WeatherKit omitted current or daily weather.")
		}

		return CurrentSchoolWeather(
			asOf: current.asOf,
			conditionCode: current.conditionCode,
			temperature: current.temperature,
			uvIndex: current.uvIndex,
			precipitationChance: today.precipitationChance
		)
	}

	private func weatherKitResponse(
		for uri: URI,
		token: String,
		on request: Request
	) async throws -> WeatherKitResponse {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		let response = try await request.client.get(uri, headers: headers)
		guard response.status == .ok else {
			throw Abort(.badGateway, reason: "WeatherKit returned HTTP \(response.status.code).")
		}
		return try response.content.decode(WeatherKitResponse.self)
	}

	private func weatherURI(
		dataSets: String,
		dailyStart: Date? = nil,
		dailyEnd: Date? = nil
	) -> URI {
		var components = URLComponents(
			string: "https://weatherkit.apple.com/api/v1/weather/en-AU/\(Self.latitude)/\(Self.longitude)"
		)!
		var queryItems = [
			URLQueryItem(name: "countryCode", value: "AU"),
			URLQueryItem(name: "dataSets", value: dataSets),
			URLQueryItem(name: "timezone", value: "Australia/Perth"),
		]
		if let dailyStart, let dailyEnd {
			queryItems.append(URLQueryItem(name: "dailyStart", value: dailyStart.ISO8601Format()))
			queryItems.append(URLQueryItem(name: "dailyEnd", value: dailyEnd.ISO8601Format()))
		}
		components.queryItems = queryItems
		return URI(string: components.url!.absoluteString)
	}

	private func dateInterval(for date: SchoolCalendarDate) -> DateInterval? {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "Australia/Perth")!
		guard let start = calendar.date(
			from: DateComponents(year: date.year, month: date.month, day: date.day)
		), let end = calendar.date(byAdding: .day, value: 1, to: start) else {
			return nil
		}
		return DateInterval(start: start, end: end)
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
	let precipitationChance: Double
	let observedAt: Date
	let fetchedAt: Date
	let isStale: Bool

	init(_ cache: SchoolWeatherCache, isStale: Bool) {
		temperatureCelsius = cache.temperatureCelsius
		conditionCode = cache.conditionCode
		uvIndex = cache.uvIndex
		precipitationChance = cache.precipitationChance
		observedAt = cache.observedAt
		fetchedAt = cache.fetchedAt
		self.isStale = isStale
	}

	fileprivate init(day: WeatherKitDayWeather) {
		temperatureCelsius = day.temperatureMax
		conditionCode = day.conditionCode
		uvIndex = day.maxUvIndex
		precipitationChance = day.precipitationChance
		observedAt = day.forecastStart
		fetchedAt = .now
		isStale = false
	}
}

private struct WeatherKitResponse: Decodable {
	let currentWeather: WeatherKitCurrentWeather?
	let forecastDaily: WeatherKitDailyForecast?
}

private struct WeatherKitCurrentWeather: Decodable {
	let asOf: Date
	let conditionCode: String
	let temperature: Double
	let uvIndex: Int
}

private struct WeatherKitDailyForecast: Decodable {
	let days: [WeatherKitDayWeather]
}

private struct WeatherKitDayWeather: Decodable {
	let forecastStart: Date
	let conditionCode: String
	let temperatureMax: Double
	let maxUvIndex: Int
	let precipitationChance: Double
}

private struct CurrentSchoolWeather {
	let asOf: Date
	let conditionCode: String
	let temperature: Double
	let uvIndex: Int
	let precipitationChance: Double
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
