import Fluent

struct CreateEventTags: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema(EventTagSection.schema)
			.id()
			.field("category", .string, .required)
			.field("display_name", .string, .required)
			.field("sort_order", .int, .required)
			.field("is_archived", .bool, .required)
			.field("revision", .int, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "category")
			.create()

		try await database.schema(EventTag.schema)
			.id()
			.field("section_id", .uuid, .required, .references(EventTagSection.schema, "id", onDelete: .restrict))
			.field("slug", .string, .required)
			.field("display_name", .string, .required)
			.field("category", .string, .required)
			.field("symbol", .string)
			.field("color_hex", .string)
			.field("sort_order", .int, .required)
			.field("is_archived", .bool, .required)
			.field("revision", .int, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "slug")
			.create()

		try await database.schema(EventTagAssociatedName.schema)
			.id()
			.field("event_tag_id", .uuid, .required, .references(EventTag.schema, "id", onDelete: .cascade))
			.field("display_name", .string, .required)
			.field("normalized_name", .string, .required)
			.field("created_at", .datetime)
			.unique(on: "event_tag_id", "normalized_name")
			.create()

		try await database.schema(AccountEventTagSubscription.schema)
			.id()
			.field("account_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
			.field("event_tag_id", .uuid, .required, .references(EventTag.schema, "id", onDelete: .restrict))
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.unique(on: "account_id", "event_tag_id")
			.create()

		try await database.schema(CalendarEventTag.schema)
			.id()
			.field("calendar_event_id", .uuid, .required, .references(CalendarEvent.schema, "id", onDelete: .cascade))
			.field("event_tag_id", .uuid, .required, .references(EventTag.schema, "id", onDelete: .restrict))
			.field("created_at", .datetime)
			.unique(on: "calendar_event_id", "event_tag_id")
			.create()

		try await seedInitialCatalogue(on: database)
	}

	func revert(on database: any Database) async throws {
		try await database.schema(CalendarEventTag.schema).delete()
		try await database.schema(AccountEventTagSubscription.schema).delete()
		try await database.schema(EventTagAssociatedName.schema).delete()
		try await database.schema(EventTag.schema).delete()
		try await database.schema(EventTagSection.schema).delete()
	}

	private func seedInitialCatalogue(on database: any Database) async throws {
		var sectionsByCategory: [EventTagCategory: UUID] = [:]
		for (index, category) in EventTagCategory.allCases.enumerated() {
			let section = EventTagSection(
				category: category,
				displayName: displayName(for: category),
				sortOrder: index
			)
			try await section.create(on: database)
			sectionsByCategory[category] = try section.requireID()
		}

		let yearTags = [
			("year-7", "Year 7", "7"),
			("year-8", "Year 8", "8"),
			("year-9", "Year 9", "9"),
			("year-10", "Year 10", "10"),
			("year-11", "Year 11", "11"),
			("year-12", "Leavers", "12"),
		]

		for (index, tag) in yearTags.enumerated() {
			let eventTag = EventTag(
				sectionID: sectionsByCategory[.yearGroup]!,
				slug: tag.0,
				displayName: tag.1,
				category: .yearGroup,
				sortOrder: index
			)
			try await eventTag.create(on: database)
			try await EventTagAssociatedName(
				eventTagID: eventTag.requireID(),
				displayName: "Year \(tag.2)",
				normalizedName: "year \(tag.2)"
			).create(on: database)
		}

		let generalTag = EventTag(
			sectionID: sectionsByCategory[.general]!,
			slug: "general",
			displayName: "General",
			category: .general,
			sortOrder: 0
		)
		try await generalTag.create(on: database)
		try await EventTagAssociatedName(
			eventTagID: generalTag.requireID(),
			displayName: "General",
			normalizedName: "general"
		).create(on: database)

		let users = try await User.query(on: database).all()
		let generalTagID = try generalTag.requireID()
		for user in users {
			try await AccountEventTagSubscription(
				accountID: user.requireID(),
				eventTagID: generalTagID
			).create(on: database)
		}
	}

	private func displayName(for category: EventTagCategory) -> String {
		switch category {
			case .yearGroup:
				"Year Groups"
			case .subject:
				"Subjects"
			case .sport:
				"Sport"
			case .general:
				"General"
		}
	}
}
