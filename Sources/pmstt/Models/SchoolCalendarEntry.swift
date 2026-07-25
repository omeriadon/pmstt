import Fluent
import Vapor

final class SchoolCalendarEntry: Model, Content, @unchecked Sendable {
	static let schema = "school_calendar_entries"
	@ID(key: .id) var id: UUID?
	@Field(key: "kind") var kind: String
	@Field(key: "label") var label: String
	@Field(key: "start_date") var startDate: String
	@OptionalField(key: "end_date") var endDate: String?

	init() {}
	init(kind: String, label: String, startDate: String, endDate: String? = nil) {
		self.kind = kind; self.label = label; self.startDate = startDate; self.endDate = endDate
	}
}
