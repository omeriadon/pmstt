import Fluent
import Vapor

final class AppVersionRequirement: Model, Content, @unchecked Sendable {
	static let schema = "app_version_requirements"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "app_version")
	var appVersion: String

	@Field(key: "app_build")
	var appBuild: Int

	@Field(key: "mac_version")
	var macVersion: String

	@Field(key: "mac_build")
	var macBuild: Int

	init() {}

	init(
		id: UUID? = nil,
		appVersion: String = "0.0.0",
		appBuild: Int = 0,
		macVersion: String = "0.0.0",
		macBuild: Int = 0
	) {
		self.id = id
		self.appVersion = appVersion
		self.appBuild = appBuild
		self.macVersion = macVersion
		self.macBuild = macBuild
	}
}
