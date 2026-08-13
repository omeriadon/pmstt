import Fluent
import Vapor

final class CalendarEvent: Model, Content, @unchecked Sendable {
	static let schema = "calendar_events"

	@ID(key: .id) var id: UUID?
	@OptionalParent(key: "user_id") var user: User?
	@Field(key: "title") var title: String
	@OptionalField(key: "notes") var notes: String?
	@Field(key: "symbol") var symbol: String
	@Field(key: "event_date") var eventDate: String
	@Field(key: "is_global") var isGlobal: Bool
	@Field(key: "shows_weather") var showsWeather: Bool
	@Field(key: "revision") var revision: Int
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		userID: UUID?,
		title: String,
		notes: String?,
		symbol: String,
		eventDate: String,
		isGlobal: Bool,
		showsWeather: Bool = false,
		revision: Int = 1
	) {
		self.id = id
		$user.id = userID
		self.title = title
		self.notes = notes
		self.symbol = symbol
		self.eventDate = eventDate
		self.isGlobal = isGlobal
		self.showsWeather = showsWeather
		self.revision = revision
	}
}
