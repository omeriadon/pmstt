import Fluent
import Vapor

final class AboutContributor: Model, Content, @unchecked Sendable {
	static let schema = "about_contributors"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "name")
	var name: String

	@Field(key: "role")
	var role: String

	@Field(key: "sort_order")
	var sortOrder: Int

	init() {}

	init(
		id: UUID? = nil,
		name: String,
		role: String,
		sortOrder: Int
	) {
		self.id = id
		self.name = name
		self.role = role
		self.sortOrder = sortOrder
	}
}
