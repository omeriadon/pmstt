import Fluent
import Vapor

final class SchoolWeatherCache: Model, Content, @unchecked Sendable {
	static let schema = "school_weather_cache"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "temperature_celsius")
	var temperatureCelsius: Double

	@Field(key: "condition_code")
	var conditionCode: String

	@Field(key: "uv_index")
	var uvIndex: Int

	@Field(key: "precipitation_chance")
	var precipitationChance: Double

	@Field(key: "observed_at")
	var observedAt: Date

	@Field(key: "fetched_at")
	var fetchedAt: Date

	init() {}

	init(
		temperatureCelsius: Double,
		conditionCode: String,
		uvIndex: Int,
		precipitationChance: Double,
		observedAt: Date,
		fetchedAt: Date
	) {
		self.temperatureCelsius = temperatureCelsius
		self.conditionCode = conditionCode
		self.uvIndex = uvIndex
		self.precipitationChance = precipitationChance
		self.observedAt = observedAt
		self.fetchedAt = fetchedAt
	}
}
