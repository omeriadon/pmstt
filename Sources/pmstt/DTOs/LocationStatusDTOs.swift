import Foundation
import Vapor

struct LocationStatusUpdateRequest: Content {
	let state: LocationStatus
	let updatedAt: Date
}

struct LocationArrivalStatisticsResponse: Content {
	let averageArrivalSecondsSinceMidnight: Double?
}

struct AdministrationStatisticsResponse: Content {
	let totalUsers: Int
	let averageArrivalSecondsSinceMidnight: Double?
}
