import Vapor

struct LiveActivityPushToStartTokenRequest: Content {
	let installationID: String
	let token: String
	let isDebug: Bool
}

struct RemoveLiveActivityTokenRequest: Content {
	let installationID: String
}

struct LiveActivityUpdateTokenRequest: Content {
	let installationID: String
	let token: String
	let isDebug: Bool
}
