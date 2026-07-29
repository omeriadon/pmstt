import Fluent

final class AuthorityAuditRecord: Model, @unchecked Sendable {
	static let schema = "authority_audit_records"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "actor_user_id")
	var actorUserID: UUID

	@Field(key: "target_user_id")
	var targetUserID: UUID

	@Field(key: "old_authority")
	var oldAuthority: AccountAuthority

	@Field(key: "new_authority")
	var newAuthority: AccountAuthority

	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?

	init() {}

	init(
		actorUserID: UUID,
		targetUserID: UUID,
		oldAuthority: AccountAuthority,
		newAuthority: AccountAuthority
	) {
		self.actorUserID = actorUserID
		self.targetUserID = targetUserID
		self.oldAuthority = oldAuthority
		self.newAuthority = newAuthority
	}
}
