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

	let api = app.grouped("api")
	try api.register(collection: AuthController())
	try api.register(collection: AppleNotificationController())
	try api.register(collection: AccountController())
	try api.register(collection: OwnerTimetableController())
	try api.register(collection: SettingsController())
	try api.register(collection: CalendarEventsController())
	try api.register(collection: AdministrationController())
	try api.register(collection: NotificationController())
	try api.register(collection: LiveActivityController())
	try api.register(collection: ReportController())
	try api.register(collection: CreatedTimetableController())
	try api.register(collection: TimetableDiscoveryController())
	try api.register(collection: SharedTimetableController())
}

struct HealthResponse: Content {
	let status: String
	let uptime: Int
}
