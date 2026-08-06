import Foundation
import Vapor

struct LocationStatusUpdateRequest: Content {
	let state: LocationStatus
	let updatedAt: Date
}

struct LocationArrivalStatisticsResponse: Content {
	let averageArrivalSecondsSinceMidnight: Double?
}
