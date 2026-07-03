import Fluent
import Foundation

final class SchoolDayLiveActivityTransition: Model, @unchecked Sendable {
	static let schema = "school_day_live_activity_transitions"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "live_activity_id")
	var liveActivity: SchoolDayLiveActivity

	@Field(key: "transition")
	var transition: String

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	init() {}

	init(liveActivityID: SchoolDayLiveActivity.IDValue, transition: String) {
		$liveActivity.id = liveActivityID
		self.transition = transition
	}
}
