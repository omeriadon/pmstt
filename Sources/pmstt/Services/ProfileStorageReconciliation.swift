import Fluent
import Vapor

private struct R2AnalyticsRequest: Content {
	let query: String
	let variables: Variables

	struct Variables: Content {
		let accountTag: String
		let startDate: String
		let endDate: String
		let bucketName: String
	}
}

private struct R2AnalyticsResponse: Content {
	let data: DataContainer?
	let errors: [GraphQLError]?

	struct DataContainer: Content {
		let viewer: Viewer
	}

	struct Viewer: Content {
		let accounts: [Account]
	}

	struct Account: Content {
		let r2StorageAdaptiveGroups: [StorageGroup]
	}

	struct StorageGroup: Content {
		let max: StorageMaximum
	}

	struct StorageMaximum: Content {
		let objectCount: Int64?
		let uploadCount: Int64?
		let payloadSize: Int64?
		let metadataSize: Int64?
	}

	struct GraphQLError: Content {
		let message: String
	}
}

struct ProfileStorageReconciliation {
	private static let query = """
	query ProfileStorageAudit(
		$accountTag: string!
		$startDate: Time
		$endDate: Time
		$bucketName: string
	) {
		viewer {
			accounts(filter: { accountTag: $accountTag }) {
				r2StorageAdaptiveGroups(
					limit: 1
					filter: {
						datetime_geq: $startDate
						datetime_leq: $endDate
						bucketName: $bucketName
					}
					orderBy: [datetime_DESC]
				) {
					max {
						objectCount
						uploadCount
						payloadSize
						metadataSize
					}
				}
			}
		}
	}
	"""

	func run(on application: Application) async {
		do {
			let configuration = try ProfileStorageConfiguration.load()
			guard let token = configuration.analyticsAPIToken,
				  !token.isEmpty
			else {
				application.logger.debug(
					"Profile storage analytics reconciliation is not configured"
				)
				return
			}

			let endDate = Date.now
			let startDate = endDate.addingTimeInterval(-24 * 60 * 60)
			let formatter = ISO8601DateFormatter()
			let request = R2AnalyticsRequest(
				query: Self.query,
				variables: .init(
					accountTag: configuration.accountID,
					startDate: formatter.string(from: startDate),
					endDate: formatter.string(from: endDate),
					bucketName: configuration.bucketName
				)
			)

			let response = try await application.client.post(
				URI(string: "https://api.cloudflare.com/client/v4/graphql"),
				headers: [
					"Authorization": "Bearer \(token)",
					"Content-Type": "application/json",
				]
			) { outgoing in
				try outgoing.content.encode(request)
			}
			guard response.status == .ok else {
				throw Abort(
					.badGateway,
					reason: "Cloudflare analytics returned \(response.status.code)."
				)
			}

			let analytics = try response.content.decode(R2AnalyticsResponse.self)
			if let error = analytics.errors?.first {
				throw Abort(.badGateway, reason: error.message)
			}
			guard let remote = analytics.data?
				.viewer.accounts.first?
				.r2StorageAdaptiveGroups.first?
				.max,
				let remoteBytes = remote.payloadSize
			else {
				application.logger.debug(
					"Profile storage analytics has no delayed sample yet"
				)
				return
			}

			let quota = try await ProfileStorageQuota.find(
				ProfileStorageQuota.singletonID,
				on: application.db
			) ?? ProfileStorageQuota()
			let trackedBytes = quota.storedBytes + quota.reservedBytes
			let warning = remoteBytes > trackedBytes

			quota.reconciledStoredBytes = remoteBytes
			quota.reconciledAt = .now
			quota.reconciliationWarning = warning
			quota.writesDisabled = warning
			try await quota.save(on: application.db)

			if warning {
				application.logger.error(
					"Profile storage reconciliation disabled writes",
					metadata: [
						"tracked_bytes": .string(String(trackedBytes)),
						"remote_bytes": .string(String(remoteBytes)),
						"remote_objects": .string(String(remote.objectCount ?? 0)),
						"remote_uploads": .string(String(remote.uploadCount ?? 0)),
					]
				)
			} else {
				application.logger.info(
					"Profile storage reconciliation matched local accounting",
					metadata: [
						"tracked_bytes": .string(String(trackedBytes)),
						"remote_bytes": .string(String(remoteBytes)),
					]
				)
			}
		} catch {
			application.logger.warning(
				"Profile storage analytics reconciliation skipped",
				metadata: ["error": .string(error.localizedDescription)]
			)
		}
	}
}
