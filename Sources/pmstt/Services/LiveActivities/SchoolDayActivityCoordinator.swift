import Fluent
import Foundation
import Logging

struct SchoolDayActivityCoordinator {
	private let apns = LiveActivityAPNSService()
	private let projector = SchoolDayActivityProjector()

	func endActivities(forUserID userID: UUID, database: any Database, logger: Logger) async {
		do {
			let devices = try await UserDevice.query(on: database).filter(\.$user.$id == userID).all()
			for device in devices {
				await endActivities(for: device, database: database, logger: logger)
			}
		} catch {
			logger.report(error: error, metadata: ["live_activity_user_id": .string(userID.uuidString)])
		}
	}

	func endActivities(for device: UserDevice, database: any Database, logger: Logger) async {
		do {
			let activities = try await SchoolDayLiveActivity.query(on: database)
				.filter(\.$userDevice.$id == device.requireID())
				.filter(\.$status == .active)
				.all()
			let now = Date()
			let projection = projector.projection(for: .finished, on: now, dayIndex: 0, subjects: [])
			for activity in activities {
				if let token = activity.updateToken {
					do {
						_ = try await apns.sendEnd(to: token, activityKey: activity.activityKey, isDebug: device.isDebug, projection: projection, logger: logger)
					} catch {
						logger.report(error: error, metadata: ["live_activity_id": .string(activity.id?.uuidString ?? "unknown")])
					}
				}
				activity.status = .ended
				activity.currentTransition = SchoolDayTransition.finished.rawValue
				activity.lastAPNSTimestamp = now
				try await activity.save(on: database)
			}
		} catch {
			logger.report(error: error, metadata: ["live_activity_device_id": .string(device.id?.uuidString ?? "unknown")])
		}
	}
}
