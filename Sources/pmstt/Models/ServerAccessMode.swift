import Fluent
import Vapor

final class ServerAccessMode: Model, Content, @unchecked Sendable {
	static let schema = "server_access_mode"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "development_access_only")
	var developmentAccessOnly: Bool

	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?

	init() {}

	init(id: UUID? = nil, developmentAccessOnly: Bool = false) {
		self.id = id
		self.developmentAccessOnly = developmentAccessOnly
	}
}
