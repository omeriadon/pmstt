import Fluent
import Foundation
import Vapor

final class SpecialProfileBadge: Model, Content, @unchecked Sendable {
	static let schema = "special_profile_badges"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "symbol")
	var symbol: String

	@OptionalField(key: "background_color_data")
	var backgroundColorData: Data?

	@OptionalField(key: "symbol_color_data")
	var symbolColorData: Data?

	@Field(key: "priority")
	var priority: Int

	@Field(key: "accessibility_label")
	var accessibilityLabel: String

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(
		id: UUID? = nil,
		symbol: String,
		backgroundColorData: Data?,
		symbolColorData: Data?,
		priority: Int,
		accessibilityLabel: String
	) {
		self.id = id
		self.symbol = symbol
		self.backgroundColorData = backgroundColorData
		self.symbolColorData = symbolColorData
		self.priority = priority
		self.accessibilityLabel = accessibilityLabel
	}

	var profileBadge: ProfileBadgeDTO {
		ProfileBadgeDTO(
			id: id ?? UUID(),
			symbol: symbol,
			backgroundColor: decodeColor(backgroundColorData),
			symbolColor: decodeColor(symbolColorData),
			priority: priority,
			accessibilityLabel: accessibilityLabel
		)
	}

	private func decodeColor(_ data: Data?) -> ProfileColorDTO? {
		guard let data else {
			return nil
		}

		return try? JSONDecoder().decode(ProfileColorDTO.self, from: data)
	}
}

final class UserSpecialProfileBadge: Model, Content, @unchecked Sendable {
	static let schema = "user_special_profile_badges"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: User

	@Parent(key: "badge_id")
	var badge: SpecialProfileBadge

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	init() {}

	init(id: UUID? = nil, userID: UUID, badgeID: UUID) {
		self.id = id
		$user.id = userID
		$badge.id = badgeID
	}
}
