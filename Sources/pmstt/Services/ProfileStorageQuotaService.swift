import Fluent
import Vapor

enum ProfileStorageOperationKind {
	case read
	case mutation
}

private actor ProfileStorageQuotaCoordinator {
	static let shared = ProfileStorageQuotaCoordinator()

	func perform<T: Sendable>(
		_ operation: @Sendable () async throws -> T
	) async rethrows -> T {
		try await operation()
	}
}

struct ProfileStorageQuotaSnapshot: Content {
	let storedBytes: Int64
	let reservedBytes: Int64
	let storageLimitBytes: Int64
	let monthlyOperations: Int
	let monthlyOperationLimit: Int
	let monthlyWriteCutoff: Int
	let writesDisabled: Bool
	let reconciledStoredBytes: Int64?
	let reconciliationWarning: Bool
	let reconciledAt: Date?
}

struct ProfileStorageQuotaService {
	private let configuration: ProfileStorageConfiguration

	init(configuration: ProfileStorageConfiguration) {
		self.configuration = configuration
	}

	func reserveUpload(
		bytes: Int,
		on database: any Database,
		logger: Logger
	) async throws {
		try await ProfileStorageQuotaCoordinator.shared.perform {
			try await database.transaction { transaction in
				let quota = try await quota(on: transaction)
				guard !quota.writesDisabled else {
					throw writeBudgetError()
				}
				let projected = quota.storedBytes + quota.reservedBytes + Int64(bytes)
				guard projected <= configuration.storageLimitBytes else {
					throw AppError(
						.insufficientStorage,
						code: .profileStorageCapacityReached,
						reason: "Profile photo storage is currently full."
					)
				}
				quota.reservedBytes += Int64(bytes)
				try await quota.save(on: transaction)
				logThresholds(
					Int(projected),
					limit: Int(configuration.storageLimitBytes),
					label: "byte",
					logger: logger
				)
			}
		}
	}

	func finalizeUpload(bytes: Int, on database: any Database) async throws {
		try await ProfileStorageQuotaCoordinator.shared.perform {
			try await database.transaction { transaction in
				let quota = try await quota(on: transaction)
				quota.reservedBytes = max(0, quota.reservedBytes - Int64(bytes))
				quota.storedBytes += Int64(bytes)
				try await quota.save(on: transaction)
			}
		}
	}

	func releaseReservation(bytes: Int, on database: any Database) async throws {
		try await ProfileStorageQuotaCoordinator.shared.perform {
			let quota = try await quota(on: database)
			quota.reservedBytes = max(0, quota.reservedBytes - Int64(bytes))
			try await quota.save(on: database)
		}
	}

	func releaseStoredBytes(_ bytes: Int, on database: any Database) async throws {
		try await ProfileStorageQuotaCoordinator.shared.perform {
			let quota = try await quota(on: database)
			quota.storedBytes = max(0, quota.storedBytes - Int64(bytes))
			try await quota.save(on: database)
		}
	}

	func reserveOperation(
		_ kind: ProfileStorageOperationKind,
		on database: any Database,
		logger: Logger
	) async throws {
		let yearMonth = Self.currentYearMonth
		try await ProfileStorageQuotaCoordinator.shared.perform {
			try await database.transaction { transaction in
				let counter = try await ProfileStorageOperationMonth.query(on: transaction)
					.filter(\.$yearMonth == yearMonth)
					.first()
					?? ProfileStorageOperationMonth(yearMonth: yearMonth)

				if kind == .mutation, counter.reservedOperations >= configuration.monthlyWriteCutoff {
					throw writeBudgetError()
				}
				guard counter.reservedOperations < configuration.monthlyOperationLimit else {
					throw operationBudgetError()
				}

				counter.reservedOperations += 1
				try await counter.save(on: transaction)
				logThresholds(
					counter.reservedOperations,
					limit: configuration.monthlyOperationLimit,
					label: "operation",
					logger: logger
				)
			}
		}
	}

	func snapshot(on database: any Database) async throws -> ProfileStorageQuotaSnapshot {
		let quota = try await quota(on: database)
		let operations = try await ProfileStorageOperationMonth.query(on: database)
			.filter(\.$yearMonth == Self.currentYearMonth)
			.first()?
			.reservedOperations ?? 0
		return ProfileStorageQuotaSnapshot(
			storedBytes: quota.storedBytes,
			reservedBytes: quota.reservedBytes,
			storageLimitBytes: configuration.storageLimitBytes,
			monthlyOperations: operations,
			monthlyOperationLimit: configuration.monthlyOperationLimit,
			monthlyWriteCutoff: configuration.monthlyWriteCutoff,
			writesDisabled: quota.writesDisabled,
			reconciledStoredBytes: quota.reconciledStoredBytes,
			reconciliationWarning: quota.reconciliationWarning,
			reconciledAt: quota.reconciledAt
		)
	}

	private func quota(on database: any Database) async throws -> ProfileStorageQuota {
		if let quota = try await ProfileStorageQuota.find(ProfileStorageQuota.singletonID, on: database) {
			return quota
		}
		let quota = ProfileStorageQuota(
			storedBytes: 0,
			reservedBytes: 0,
			writesDisabled: false,
			reconciliationWarning: false
		)
		try await quota.create(on: database)
		return quota
	}

	private func writeBudgetError() -> AppError {
		AppError(
			.tooManyRequests,
			code: .profileStorageWriteBudgetReached,
			reason: "Profile photo changes are unavailable until next month.",
			headers: retryHeaders()
		)
	}

	private func operationBudgetError() -> AppError {
		AppError(
			.tooManyRequests,
			code: .profileStorageOperationBudgetReached,
			reason: "Profile photo storage operations are unavailable until next month.",
			headers: retryHeaders()
		)
	}

	private func retryHeaders() -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.replaceOrAdd(name: .retryAfter, value: String(Self.secondsUntilNextUTCMonth))
		return headers
	}

	private func logThresholds(
		_ usage: Int,
		limit: Int,
		label: String,
		logger: Logger
	) {
		let percentage = Double(usage) / Double(limit)
		if percentage >= 0.95 {
			logger.warning("Profile storage \(label) quota is at least 95% consumed")
		} else if percentage >= 0.90 {
			logger.warning("Profile storage \(label) quota is at least 90% consumed")
		} else if percentage >= 0.80 {
			logger.warning("Profile storage \(label) quota is at least 80% consumed")
		}
	}

	private static var currentYearMonth: String {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = .gmt
		let components = calendar.dateComponents([.year, .month], from: .now)
		let month = components.month ?? 0
		let paddedMonth = month < 10 ? "0\(month)" : "\(month)"
		return "\(components.year ?? 0)-\(paddedMonth)"
	}

	private static var secondsUntilNextUTCMonth: Int {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = .gmt
		let now = Date.now
		let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
		let next = calendar.date(byAdding: .month, value: 1, to: start) ?? now
		return max(1, Int(next.timeIntervalSince(now)))
	}
}
