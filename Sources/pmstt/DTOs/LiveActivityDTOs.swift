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

struct ReconcileLiveActivityRequest: Content {
	let installationID: String
	let activeActivityKeys: [String]?
}

struct ReconcileLiveActivityResponse: Content {
	let started: Bool
}

struct LiveActivityDebugStateResponse: Content {
	let isActive: Bool
	let canUpdate: Bool
}

struct LiveActivityDebugRequest: Content {
	let installationID: String
}

struct LiveActivityDebugUpdateRequest: Content {
	let installationID: String
	let transition: String
}
