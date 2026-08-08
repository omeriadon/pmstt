import Foundation
import Vapor

struct LocationStatusUpdateRequest: Content {
	let state: LocationStatus
	let updatedAt: Date
}

struct LocationStatusCurrentResponse: Content {
	let item: LocationStatusItem?
}

struct LocationArrivalStatisticsResponse: Content {
	let averageArrivalSecondsSinceMidnight: Double?
}

struct AdministrationStatisticsResponse: Content {
	let totalUsers: Int
	let usersWithOwnerTimetable: Int
	let totalAssessments: Int
	let averageAssessmentsPerUser: Double?
	let averageAssessmentsPerUserWithMultipleAssessments: Double?
	let totalDevices: Int
	let activeDevicesLast30Days: Int
	let iPhoneDevices: Int
	let iPadDevices: Int
	let macDevices: Int
	let watchDevices: Int
	let legacyDevices: Int
	let acceptedFriendships: Int
	let averageFriendsPerUser: Double?
	let averageFriendsPerUserWithFriends: Double?
	let totalCalendarEvents: Int
	let globalCalendarEvents: Int
	let personalCalendarEvents: Int
	let activeEventTagSubscriptions: Int
	let averageArrivalSecondsSinceMidnight: Double?
}
