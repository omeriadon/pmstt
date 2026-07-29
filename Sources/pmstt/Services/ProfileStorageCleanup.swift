import Fluent
import Vapor

struct ProfileStorageCleanup {
	func run(on application: Application) async {
		do {
			let configuration = try ProfileStorageConfiguration.load()
			let quota = ProfileStorageQuotaService(configuration: configuration)
			let objectStore = R2ProfileObjectStore(configuration: configuration)
			let cutoff = Date.now.addingTimeInterval(-60 * 60)
			let candidates = try await ProfileStorageObject.query(on: application.db)
				.group(.or) { group in
					group.filter(\.$state == .superseded)
					group.filter(\.$state == .orphaned)
				}
				.filter(\.$updatedAt < cutoff)
				.limit(100)
				.all()

			for object in candidates {
				do {
					try await quota.reserveOperation(.mutation, on: application.db, logger: application.logger)
					try await objectStore.delete(key: object.objectKey, client: application.client)
					try await quota.releaseStoredBytes(object.byteSize, on: application.db)
					try await object.delete(on: application.db)
				} catch {
					application.logger.warning(
						"Profile storage cleanup deferred an object",
						metadata: [
							"object_key": .string(object.objectKey),
							"error": .string(error.localizedDescription),
						]
					)
				}
			}
		} catch {
			application.logger.warning(
				"Profile storage cleanup skipped",
				metadata: ["error": .string(error.localizedDescription)]
			)
		}
	}
}

actor ProfileStorageCleanupLifecycle: LifecycleHandler {
	private var task: Task<Void, Never>?

	func didBootAsync(_ application: Application) async throws {
		let cleanup = ProfileStorageCleanup()
		let reconciliation = ProfileStorageReconciliation()
		task = Task {
			while !Task.isCancelled {
				await cleanup.run(on: application)
				await reconciliation.run(on: application)
				try? await Task.sleep(for: .hours(6))
			}
		}
	}

	func shutdownAsync(_ application: Application) async {
		_ = application
		task?.cancel()
		task = nil
	}
}
