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
	let debugDevices: Int
	let betaDevices: Int
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
	let usersWithAssessments: Int
	let usersWithLocationStatus: Int
	let totalLocationStatusUpdates: Int
	let deviceTypes: [AdministrationStatisticCount]
	let osVersions: [AdministrationStatisticCount]
	let deviceOSVersions: [AdministrationDeviceOSVersionCount]
}

struct AdministrationStatisticCount: Content, Identifiable {
	let label: String
	let count: Int

	var id: String {
		label
	}
}

struct AdministrationDeviceOSVersionCount: Content, Identifiable {
	let platform: String
	let osMajorVersion: Int
	let osMinorVersion: Int
	let isDebug: Bool
	let count: Int

	var id: String {
		"\(platform)-\(osMajorVersion)-\(osMinorVersion)-\(isDebug)"
	}
}
