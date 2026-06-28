import Foundation

enum SigningError: Error, CustomStringConvertible {
	case resourceNotFound(String)
	case opensslNotFound
	case opensslFailed(status: Int32, stderr: String)

	var description: String {
		switch self {
			case .resourceNotFound(let path):
				return "Required signing resource not found: \(path)"

			case .opensslNotFound:
				return "Could not find an openssl executable."

			case .opensslFailed(let status, let stderr):
				return "OpenSSL failed with status \(status): \(stderr)"
		}
	}
}

private func Print(_ message: String) {
	print(message)
}

private func PrintError(_ message: String) {
	print("ERROR: \(message)")
}

private func findOpenSSL() throws -> URL {
	let candidates = [
		"/opt/homebrew/bin/openssl", // Apple Silicon Homebrew
		"/usr/bin/openssl" // macOS system / Ubuntu system
	]

	for path in candidates {
		if FileManager.default.isExecutableFile(atPath: path) {
			return URL(fileURLWithPath: path)
		}
	}

	throw SigningError.opensslNotFound
}

private func requireFile(_ url: URL) throws {
	guard FileManager.default.fileExists(atPath: url.path) else {
		throw SigningError.resourceNotFound(url.path)
	}
}

func signManifestWithBundledKey(
	manifestURL: URL,
	outputSignatureURL: URL,
	resourceDirectory: URL
) throws {
	let passKeyURL = resourceDirectory.appendingPathComponent("pass.pem")
	let walletCertURL = resourceDirectory.appendingPathComponent("wallet_pass.pem")

	try requireFile(manifestURL)
	try requireFile(passKeyURL)
	try requireFile(walletCertURL)

	let opensslURL = try findOpenSSL()

	Print("Using OpenSSL at: \(opensslURL.path)")

	let process = Process()
	process.executableURL = opensslURL

	process.arguments = [
		"smime",
		"-binary",
		"-sign",
		"-signer", walletCertURL.path,
		"-inkey", passKeyURL.path,
		"-in", manifestURL.path,
		"-out", outputSignatureURL.path,
		"-outform", "DER"
	]

	let stderrPipe = Pipe()
	let stdoutPipe = Pipe()

	process.standardError = stderrPipe
	process.standardOutput = stdoutPipe

	try process.run()
	process.waitUntilExit()

	let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
	let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

	let stderr = String(data: stderrData, encoding: .utf8) ?? ""
	let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

	if process.terminationStatus != 0 {
		PrintError("OpenSSL stdout: \(stdout)")
		PrintError("OpenSSL stderr: \(stderr)")
		throw SigningError.opensslFailed(
			status: process.terminationStatus,
			stderr: stderr.isEmpty ? stdout : stderr
		)
	}

	try requireFile(outputSignatureURL)

	Print("Pass manifest signed successfully")
}
