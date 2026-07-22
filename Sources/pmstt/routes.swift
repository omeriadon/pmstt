import Vapor

func routes(_ app: Application) throws {
	app.get(".well-known", "apple-app-site-association") { _ -> Response in
		let response = Response(status: .ok)
		response.headers.contentType = .json
		response.headers.replaceOrAdd(name: "Cache-Control", value: "public, max-age=3600")
		response.body = .init(string: """
		{
		  "applinks": {
		    "details": [
		      {
		        "appIDs": ["P6PV2R9443.com.omeriadon.Timetable"],
		        "components": [
		          { "/": "/*" }
		        ]
		      }
		    ]
		  }
		}
		""")
		return response
	}

	app.get("health") { req async -> HealthResponse in
		req.logger.debug("Health check completed")
		return HealthResponse(
			status: "ok",
			uptime: Int(ProcessInfo.processInfo.systemUptime)
		)
	}

	try app.register(collection: AuthController())
	try app.register(collection: AppleNotificationController())
	try app.register(collection: AccountController())
	try app.register(collection: OwnerTimetableController())
	try app.register(collection: SettingsController())
	try app.register(collection: NotificationController())
	try app.register(collection: LiveActivityController())
	try app.register(collection: ReportController())
	try app.register(collection: AuthoredTimetableController())
	try app.register(collection: TimetableDiscoveryController())
	try app.register(collection: SharedTimetableController())
}

struct HealthResponse: Content {
	let status: String
	let uptime: Int
}
