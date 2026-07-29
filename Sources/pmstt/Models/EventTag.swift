import Fluent
import Vapor

enum EventTagCategory: String, Codable, CaseIterable, Sendable {
	case yearGroup
	case subject
	case sport
	case general
}

final class EventTagSection: Model, Content, @unchecked Sendable {
	static let schema = "event_tag_sections"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "category")
	var category: EventTagCategory

	@Field(key: "display_name")
	var displayName: String

	@Field(key: "sort_order")
	var sortOrder: Int

	@Field(key: "is_archived")
	var isArchived: Bool

	@Field(key: "revision")
	var revision: Int

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		category: EventTagCategory,
		displayName: String,
		sortOrder: Int,
		isArchived: Bool = false,
		revision: Int = 1
	) {
		self.id = id
		self.category = category
		self.displayName = displayName
		self.sortOrder = sortOrder
		self.isArchived = isArchived
		self.revision = revision
	}
}

final class EventTag: Model, Content, @unchecked Sendable {
	static let schema = "event_tags"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "section_id")
	var section: EventTagSection

	@Field(key: "slug")
	var slug: String

	@Field(key: "display_name")
	var displayName: String

	@Field(key: "category")
	var category: EventTagCategory

	@OptionalField(key: "symbol")
	var symbol: String?

	@OptionalField(key: "color_hex")
	var colorHex: String?

	@Field(key: "sort_order")
	var sortOrder: Int

	@Field(key: "is_archived")
	var isArchived: Bool

	@Field(key: "revision")
	var revision: Int

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		sectionID: UUID,
		slug: String,
		displayName: String,
		category: EventTagCategory,
		symbol: String? = nil,
		colorHex: String? = nil,
		sortOrder: Int,
		isArchived: Bool = false,
		revision: Int = 1
	) {
		self.id = id
		$section.id = sectionID
		self.slug = slug
		self.displayName = displayName
		self.category = category
		self.symbol = symbol
		self.colorHex = colorHex
		self.sortOrder = sortOrder
		self.isArchived = isArchived
		self.revision = revision
	}
}

final class EventTagAssociatedName: Model, Content, @unchecked Sendable {
	static let schema = "event_tag_associated_names"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "event_tag_id")
	var eventTag: EventTag

	@Field(key: "display_name")
	var displayName: String

	@Field(key: "normalized_name")
	var normalizedName: String

	@Field(key: "category")
	var category: EventTagCategory

	@Field(key: "is_active")
	var isActive: Bool

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		eventTagID: UUID,
		displayName: String,
		normalizedName: String,
		category: EventTagCategory,
		isActive: Bool
	) {
		self.id = id
		$eventTag.id = eventTagID
		self.displayName = displayName
		self.normalizedName = normalizedName
		self.category = category
		self.isActive = isActive
	}
}

final class AccountEventTagSubscription: Model, Content, @unchecked Sendable {
	static let schema = "account_event_tag_subscriptions"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "account_id")
	var account: User

	@Parent(key: "event_tag_id")
	var eventTag: EventTag

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(id: UUID? = nil, accountID: UUID, eventTagID: UUID) {
		self.id = id
		$account.id = accountID
		$eventTag.id = eventTagID
	}
}

final class CalendarEventTag: Model, Content, @unchecked Sendable {
	static let schema = "calendar_event_tags"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "calendar_event_id")
	var calendarEvent: CalendarEvent

	@Parent(key: "event_tag_id")
	var eventTag: EventTag

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	init() {}

	init(id: UUID? = nil, calendarEventID: UUID, eventTagID: UUID) {
		self.id = id
		$calendarEvent.id = calendarEventID
		$eventTag.id = eventTagID
	}
}
