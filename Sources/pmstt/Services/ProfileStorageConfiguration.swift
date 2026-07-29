import Vapor

struct ProfileStorageConfiguration {
	let accountID: String
	let accessKeyID: String
	let secretAccessKey: String
	let bucketName: String
	let storageLimitBytes: Int64
	let monthlyOperationLimit: Int
	let monthlyWriteCutoff: Int

	static func load() throws -> ProfileStorageConfiguration {
		guard let accountID = Environment.get("R2_ACCOUNT_ID"),
			  let accessKeyID = Environment.get("R2_ACCESS_KEY_ID"),
			  let secretAccessKey = Environment.get("R2_SECRET_ACCESS_KEY"),
			  let bucketName = Environment.get("R2_BUCKET_NAME")
		else {
			throw Abort(.serviceUnavailable, reason: "Profile photo storage is not configured.")
		}
		return ProfileStorageConfiguration(
			accountID: accountID,
			accessKeyID: accessKeyID,
			secretAccessKey: secretAccessKey,
			bucketName: bucketName,
			storageLimitBytes: Environment.get("R2_STORAGE_LIMIT_BYTES").flatMap(Int64.init) ?? 9_000_000_000,
			monthlyOperationLimit: Environment.get("R2_MONTHLY_OPERATION_LIMIT").flatMap(Int.init) ?? 900_000,
			monthlyWriteCutoff: Environment.get("R2_MONTHLY_WRITE_CUTOFF").flatMap(Int.init) ?? 850_000
		)
	}

	var endpoint: String {
		"https://\(accountID).r2.cloudflarestorage.com"
	}
}
