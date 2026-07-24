import Fluent
import Foundation
import Logging
import NIOCore
import Vapor

struct SchoolDayActivityScheduler {
	private let schoolCalendar: SchoolCalendar
	private let projector: SchoolDayActivityProjector
	private let apns: LiveActivityAPNSService
	private let now: @Sendable () -> Date

	init(
		schoolCalendar: SchoolCalendar = .configured,
		projector: SchoolDayActivityProjector = .init(),
		apns: LiveActivityAPNSService = .init(),
		now: @escaping @Sendable () -> Date = Date.init
	) {
		self.schoolCalendar = schoolCalendar
		self.projector = projector
		self.apns = apns
		self.now = now
	}

	func tick(on app: Application) async {
		await tick(at: now(), database: app.db, logger: app.logger)
	}

	func tick(at date: Date, database: any Database, logger: Logger) async {
		await endActivities(
			at: date,
			dayIndex: schoolCalendar.dayIndex(for: date) ?? 0,
			includeCurrentSchoolDate: false,
			database: database,
			logger: logger
		)

		guard schoolCalendar.isSchoolDay(date),
		      let dayIndex = schoolCalendar.dayIndex(for: date)
		else { return }

		let hasReachedDismissal = SchoolDayTransition.hasReachedDismissal(
			at: date,
			dayIndex: dayIndex,
			calendar: schoolCalendar.calendar
		)
		await endActivities(
			at: date,
			dayIndex: dayIndex,
			includeCurrentSchoolDate: hasReachedDismissal,
			database: database,
			logger: logger
		)
		if hasReachedDismissal {
			return
		}

		guard let transition = SchoolDayTransition.due(at: date, dayIndex: dayIndex, calendar: schoolCalendar.calendar) else { return }

		if transition == .morning {
			await startActivities(at: date, dayIndex: dayIndex, database: database, logger: logger)
		} else {
			await updateActivities(at: date, transition: transition, dayIndex: dayIndex, database: database, logger: logger)
		}
	}

	func startCurrentActivity(
		for device: UserDevice,
		localActivityKeys: Set<String>?,
		at date: Date,
		database: any Database,
		logger: Logger
	) async throws -> Bool {
		guard schoolCalendar.isSchoolDay(date),
		      let dayIndex = schoolCalendar.dayIndex(for: date),
		      let transition = SchoolDayTransition.current(at: date, dayIndex: dayIndex, calendar: schoolCalendar.calendar),
		      transition != .finished,
		      let token = device.liveActivityPushToStartToken,
		      let user = try await User.find(device.$user.id, on: database),
		      try JSONDecoder().decode(AccountSettings.self, from: user.settingsData).liveActivitiesEnabled,
		      let timetable = try await OwnerTimetable.query(on: database).filter(\.$user.$id == device.$user.id).first()
		else { return false }

		let deviceID = try device.requireID()
		let schoolDate = schoolDateKey(date)
		let existingActivities = try await SchoolDayLiveActivity.query(on: database)
			.filter(\.$userDevice.$id == deviceID)
			.filter(\.$schoolDate == schoolDate)
			.filter(\.$status == .active)
			.all()
		if let localActivityKeys {
			guard !existingActivities.contains(where: { localActivityKeys.contains($0.activityKey) }) else { return false }
		} else {
			guard existingActivities.isEmpty else { return false }
		}

		for activity in existingActivities {
			activity.status = .ended
			activity.currentTransition = SchoolDayTransition.finished.rawValue
			activity.lastAPNSTimestamp = date
			try await activity.save(on: database)
		}

		let subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: timetable.subjectsData)
		let projection = projector.projection(for: transition, on: date, dayIndex: dayIndex, subjects: subjects)
		let activity = SchoolDayLiveActivity(
			userDeviceID: deviceID,
			activityKey: UUID().uuidString,
			schoolDate: schoolDate,
			currentTransition: "pending"
		)
		try await activity.create(on: database)

		do {
			guard let claim = try await claim(activity: activity, transition: transition, database: database) else {
				try await activity.delete(on: database)
				return false
			}
			let attributes = SchoolDayActivityAttributesPayload(
				activityKey: activity.activityKey,
				schoolDate: activity.schoolDate
			)
			let result = try await apns.sendStart(
				to: token,
				isDebug: device.isDebug,
				attributes: attributes,
				projection: projection,
				logger: logger
			)
			guard result.succeeded else {
				try await claim.delete(on: database)
				try await activity.delete(on: database)
				if result.permanentlyInvalidToken {
					device.liveActivityPushToStartToken = nil
					try await device.save(on: database)
				}
				return false
			}

			activity.currentTransition = transition.rawValue
			activity.lastAPNSTimestamp = date
			try await activity.save(on: database)
			logger.info(
				"Reconciled school-day Live Activity",
				metadata: ["activity_key": .string(activity.activityKey), "user_id": .string(device.$user.id.uuidString)]
			)
			return true
		} catch {
			try? await activity.delete(on: database)
			throw error
		}
	}

	private func startActivities(at date: Date, dayIndex: Int, database: any Database, logger: Logger) async {
		do {
			let devices = try await UserDevice.query(on: database)
				.filter(\.$liveActivityPushToStartToken != nil)
				.all()
			for device in devices {
				do {
					guard let token = device.liveActivityPushToStartToken,
					      let user = try await User.find(device.$user.id, on: database),
					      try JSONDecoder().decode(AccountSettings.self, from: user.settingsData).liveActivitiesEnabled,
					      let timetable = try await OwnerTimetable.query(on: database).filter(\.$user.$id == device.$user.id).first()
					else { continue }

					let subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: timetable.subjectsData)
					let projection = projector.projection(for: .morning, on: date, dayIndex: dayIndex, subjects: subjects)
					let activity = try await activityRecord(for: device, date: date, database: database)
					guard let claim = try await claim(activity: activity, transition: .morning, database: database) else { continue }

					let attributes = SchoolDayActivityAttributesPayload(activityKey: activity.activityKey, schoolDate: activity.schoolDate)
					let result = try await apns.sendStart(to: token, isDebug: device.isDebug, attributes: attributes, projection: projection, logger: logger)
					guard result.succeeded else {
						try await claim.delete(on: database)
						if result.permanentlyInvalidToken {
							device.liveActivityPushToStartToken = nil
							try await device.save(on: database)
						}
						continue
					}

					activity.currentTransition = SchoolDayTransition.morning.rawValue
					activity.lastAPNSTimestamp = date
					try await activity.save(on: database)
					logger.info("Started school-day Live Activity", metadata: ["activity_key": .string(activity.activityKey), "user_id": .string(device.$user.id.uuidString)])
				} catch {
					logger.report(error: error, metadata: ["live_activity_device_id": .string(device.id?.uuidString ?? "unknown")])
				}
			}
		} catch {
			logger.report(error: error, metadata: ["live_activity_transition": .string(SchoolDayTransition.morning.rawValue)])
		}
	}

	private func updateActivities(at date: Date, transition: SchoolDayTransition, dayIndex: Int, database: any Database, logger: Logger) async {
		do {
			let activities = try await SchoolDayLiveActivity.query(on: database)
				.filter(\.$status == .active)
				.with(\.$userDevice)
				.all()

			for activity in activities {
				do {
					let device = activity.userDevice
					guard let user = try await User.find(device.$user.id, on: database) else { continue }
					let settings = try JSONDecoder().decode(AccountSettings.self, from: user.settingsData)
					guard settings.liveActivitiesEnabled else {
						activity.status = .ended
						try await activity.save(on: database)
						continue
					}
					guard let token = activity.updateToken,
					      let timetable = try await OwnerTimetable.query(on: database).filter(\.$user.$id == device.$user.id).first()
					else { continue }

					let subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: timetable.subjectsData)
					let projection = projector.projection(for: transition, on: date, dayIndex: dayIndex, subjects: subjects)
					guard let claim = try await claim(activity: activity, transition: transition, database: database) else { continue }
					let result = transition == .finished
						? try await apns.sendEnd(to: token, activityKey: activity.activityKey, isDebug: device.isDebug, projection: projection, logger: logger)
						: try await apns.sendUpdate(to: token, activityKey: activity.activityKey, isDebug: device.isDebug, projection: projection, logger: logger)

					guard result.succeeded else {
						try await claim.delete(on: database)
						if result.permanentlyInvalidToken {
							activity.updateToken = nil
							activity.status = .ended
							try await activity.save(on: database)
						}
						continue
					}

					activity.currentTransition = transition.rawValue
					activity.lastAPNSTimestamp = date
					if transition == .finished {
						activity.status = .ended
					}
					try await activity.save(on: database)
				} catch {
					logger.report(error: error, metadata: ["live_activity_id": .string(activity.id?.uuidString ?? "unknown"), "transition": .string(transition.rawValue)])
				}
			}
		} catch {
			logger.report(error: error, metadata: ["live_activity_transition": .string(transition.rawValue)])
		}
	}

	private func endActivities(
		at date: Date,
		dayIndex: Int,
		includeCurrentSchoolDate: Bool,
		database: any Database,
		logger: Logger
	) async {
		do {
			let activities = try await SchoolDayLiveActivity.query(on: database)
				.filter(\.$status == .active)
				.with(\.$userDevice)
				.all()
			let projection = projector.projection(for: .finished, on: date, dayIndex: dayIndex, subjects: [])
			let currentSchoolDate = schoolDateKey(date)

			for activity in activities
				where includeCurrentSchoolDate || activity.schoolDate != currentSchoolDate
			{
				let device = activity.userDevice
				guard let token = activity.updateToken else {
					logger.warning(
						"Cannot end Live Activity until its update token is registered",
						metadata: ["activity_key": .string(activity.activityKey)]
					)
					continue
				}

				do {
					let result = try await apns.sendEnd(
						to: token,
						activityKey: activity.activityKey,
						isDebug: device.isDebug,
						projection: projection,
						logger: logger
					)

					guard result.succeeded || result.permanentlyInvalidToken else { continue }
					if result.permanentlyInvalidToken {
						activity.updateToken = nil
					}
					activity.status = .ended
					activity.currentTransition = SchoolDayTransition.finished.rawValue
					activity.lastAPNSTimestamp = date
					try await activity.save(on: database)
				} catch {
					logger.report(
						error: error,
						metadata: [
							"live_activity_id": .string(activity.id?.uuidString ?? "unknown"),
							"transition": .string(SchoolDayTransition.finished.rawValue),
						]
					)
				}
			}
		} catch {
			logger.report(error: error, metadata: ["live_activity_transition": .string(SchoolDayTransition.finished.rawValue)])
		}
	}

	private func activityRecord(for device: UserDevice, date: Date, database: any Database) async throws -> SchoolDayLiveActivity {
		let deviceID = try device.requireID()
		let schoolDate = schoolDateKey(date)
		if let existing = try await SchoolDayLiveActivity.query(on: database)
			.filter(\.$userDevice.$id == deviceID)
			.filter(\.$schoolDate == schoolDate)
			.first()
		{
			return existing
		}

		let activity = SchoolDayLiveActivity(
			userDeviceID: deviceID,
			activityKey: UUID().uuidString,
			schoolDate: schoolDate,
			currentTransition: "pending"
		)
		do {
			try await activity.create(on: database)
			return activity
		} catch {
			if let existing = try await SchoolDayLiveActivity.query(on: database)
				.filter(\.$userDevice.$id == deviceID)
				.filter(\.$schoolDate == schoolDate)
				.first()
			{
				return existing
			}
			throw error
		}
	}

	private func claim(activity: SchoolDayLiveActivity, transition: SchoolDayTransition, database: any Database) async throws -> SchoolDayLiveActivityTransition? {
		let activityID = try activity.requireID()
		let claim = SchoolDayLiveActivityTransition(liveActivityID: activityID, transition: transition.rawValue)
		do {
			try await claim.create(on: database)
			return claim
		} catch {
			if try await SchoolDayLiveActivityTransition.query(on: database)
				.filter(\.$liveActivity.$id == activityID)
				.filter(\.$transition == transition.rawValue)
				.first() != nil
			{
				return nil
			}
			throw error
		}
	}

	private func schoolDateKey(_ date: Date) -> String {
		let components = schoolCalendar.dayComponents(for: date)
		return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
	}
}

actor SchoolDayActivitySchedulerLifecycle: LifecycleHandler {
	private var task: Task<Void, Never>?

	func didBootAsync(_ application: Application) async throws {
		let scheduler = SchoolDayActivityScheduler()
		task = Task {
			while !Task.isCancelled {
				await scheduler.tick(on: application)
				let seconds = 60 - Calendar.current.component(.second, from: Date())
				try? await Task.sleep(for: .seconds(seconds))
			}
		}
	}

	func shutdownAsync(_ application: Application) async {
		_ = application
		task?.cancel()
		task = nil
	}
}
