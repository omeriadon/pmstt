import Fluent
import Foundation
import Logging
import NIOCore
import Vapor

struct SchoolNotificationScheduler {
	private let schoolCalendar: SchoolCalendar
	private let now: @Sendable () -> Date

	init(schoolCalendar: SchoolCalendar = .configured, now: @escaping @Sendable () -> Date = Date.init) {
		self.schoolCalendar = schoolCalendar
		self.now = now
	}

	func tick(on app: Application) async {
		await tick(at: now(), database: app.db, logger: app.logger)
	}

	func tick(at date: Date, database: any Database, logger: Logger) async {
		guard schoolCalendar.isSchoolDay(date),
		      let event = dueEvent(at: date),
		      let dayIndex = schoolCalendar.dayIndex(for: date)
		else { return }

		do {
			let devices = try await UserDevice.query(on: database)
				.filter(\.$apnsToken != nil)
				.all()
			let userIDs = Set(devices.map(\.$user.id))

			for userID in userIDs {
				do {
					guard let user = try await User.find(userID, on: database) else { continue }
					let settings = try JSONDecoder().decode(AccountSettings.self, from: user.settingsData)
					guard settings.notificationsEnabled,
					      event.isDue(hour: schoolCalendar.calendar.component(.hour, from: date),
					                  minute: schoolCalendar.calendar.component(.minute, from: date),
					                  leadMinutes: settings.notificationLeadTime.minutes)
					else { continue }

					let dateKey = schoolDateKey(date)
					guard try await claimDelivery(userID: userID, schoolDate: dateKey, event: event.id, database: database) else { continue }

					guard let timetable = try await OwnerTimetable.query(on: database)
						.filter(\.$user.$id == userID)
						.first()
					else {
						logger.warning("Skipping scheduled notification because the owner timetable is missing", metadata: ["user_id": .string(userID.uuidString)])
						continue
					}

					let subjects = try JSONDecoder().decode([TimetableSubjectDTO].self, from: timetable.subjectsData)
					let content = event.content(dayIndex: dayIndex, subjects: subjects, leadMinutes: settings.notificationLeadTime.minutes)
					_ = try await NotificationService().send(
						title: content.title,
						body: content.body,
						threadID: dateKey,
						to: userID,
						on: database,
						logger: logger
					)
				} catch {
					logger.report(error: error, metadata: ["school_notification_user_id": .string(userID.uuidString), "event": .string(event.id)])
				}
			}
		} catch {
			logger.report(error: error, metadata: ["school_notification_event": .string(event.id)])
		}
	}

	private func dueEvent(at date: Date) -> SchoolNotificationEvent? {
		let hour = schoolCalendar.calendar.component(.hour, from: date)
		let minute = schoolCalendar.calendar.component(.minute, from: date)
		return SchoolNotificationEvent.allCases.first { $0.couldBeDue(hour: hour, minute: minute) }
	}

	private func schoolDateKey(_ date: Date) -> String {
		let components = schoolCalendar.dayComponents(for: date)
		return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
	}

	private func claimDelivery(userID: UUID, schoolDate: String, event: String, database: any Database) async throws -> Bool {
		if try await SchoolNotificationDelivery.query(on: database)
			.filter(\.$user.$id == userID)
			.filter(\.$schoolDate == schoolDate)
			.filter(\.$event == event)
			.first() != nil
		{
			return false
		}

		do {
			try await SchoolNotificationDelivery(userID: userID, schoolDate: schoolDate, event: event).create(on: database)
			return true
		} catch {
			let alreadyClaimed = try await SchoolNotificationDelivery.query(on: database)
				.filter(\.$user.$id == userID)
				.filter(\.$schoolDate == schoolDate)
				.filter(\.$event == event)
				.first() != nil
			if alreadyClaimed {
				return false
			}
			throw error
		}
	}
}

private enum SchoolNotificationEvent: String, CaseIterable {
	case morning
	case period1
	case period2
	case recess
	case period3
	case period4
	case lunch
	case period5
	case period6
	case finished

	var id: String {
		rawValue
	}

	private var time: (hour: Int, minute: Int) {
		switch self {
			case .morning: (8, 0)
			case .period1: (8, 50)
			case .period2: (9, 48)
			case .recess: (10, 46)
			case .period3: (11, 8)
			case .period4: (12, 6)
			case .lunch: (13, 4)
			case .period5: (13, 34)
			case .period6: (14, 32)
			case .finished: (15, 30)
		}
	}

	func couldBeDue(hour: Int, minute: Int) -> Bool {
		if self == .morning {
			return hour == time.hour && minute == time.minute
		}
		let eventMinutes = time.hour * 60 + time.minute
		let currentMinutes = hour * 60 + minute
		return (0 ... 5).contains(eventMinutes - currentMinutes)
	}

	func isDue(hour: Int, minute: Int, leadMinutes: Int) -> Bool {
		let appliedLead = self == .morning ? 0 : leadMinutes
		return hour * 60 + minute == time.hour * 60 + time.minute - appliedLead
	}

	func content(dayIndex: Int, subjects: [TimetableSubjectDTO], leadMinutes: Int) -> (title: String, body: String) {
		let timing = leadMinutes == 0 ? "now" : "in \(leadMinutes) \(leadMinutes == 1 ? "minute" : "minutes")"
		switch self {
			case .morning:
				return ("School day", "First period at 8:50: \(subjectName(period: 1, dayIndex: dayIndex, subjects: subjects)).")
			case .period1: return periodContent(1, timing: timing, dayIndex: dayIndex, subjects: subjects)
			case .period2: return periodContent(2, timing: timing, dayIndex: dayIndex, subjects: subjects)
			case .period3: return periodContent(3, timing: timing, dayIndex: dayIndex, subjects: subjects)
			case .period4: return periodContent(4, timing: timing, dayIndex: dayIndex, subjects: subjects)
			case .period5: return periodContent(5, timing: timing, dayIndex: dayIndex, subjects: subjects)
			case .period6: return periodContent(6, timing: timing, dayIndex: dayIndex, subjects: subjects)
			case .recess:
				return ("Recess starts \(timing)", "Next: \(subjectName(period: 3, dayIndex: dayIndex, subjects: subjects)).")
			case .lunch:
				return ("Lunch starts \(timing)", "Next: \(subjectName(period: 5, dayIndex: dayIndex, subjects: subjects)).")
			case .finished:
				return ("School finishes \(timing)", "The school day is finished.")
		}
	}

	private func periodContent(_ period: Int, timing: String, dayIndex: Int, subjects: [TimetableSubjectDTO]) -> (title: String, body: String) {
		("Period \(period) starts \(timing)", subjectName(period: period, dayIndex: dayIndex, subjects: subjects))
	}

	private func subjectName(period: Int, dayIndex: Int, subjects: [TimetableSubjectDTO]) -> String {
		guard let session = [1: 0, 2: 1, 3: 3, 4: 4, 5: 6, 6: 7][period] else { return "Free period" }
		return subjects.first(where: { subject in
			subject.slots.contains(where: { $0.day == dayIndex && $0.session == session })
		})?.id ?? "Free period"
	}
}

actor SchoolNotificationSchedulerLifecycle: LifecycleHandler {
	private var task: Task<Void, Never>?

	func didBootAsync(_ application: Application) async throws {
		let scheduler = SchoolNotificationScheduler()
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
