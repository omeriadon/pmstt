import JWT
import Vapor

struct UserPayload: JWTPayload, Authenticatable {
    let sub: UUID
    let sid: UUID
    let platform: ClientPlatform.RawValue
    let installationID: String
    let authority: SessionAuthority.RawValue
    let capabilities: [Capability.RawValue]
    let typ: String
    let iss: IssuerClaim
    let iat: IssuedAtClaim
    let exp: ExpirationClaim

    var platformValue: ClientPlatform { ClientPlatform(rawValue: platform) ?? .legacy }

    init(sub: UUID, sid: UUID, platform: ClientPlatform, installationID: String, capabilities: [Capability] = [], typ: String = "access", issuedAt: Date = Date(), expiresAt: Date) {
        self.sub = sub
        self.sid = sid
        self.platform = platform.rawValue
        self.installationID = installationID
        self.authority = platform.authority.rawValue
        self.capabilities = capabilities.map(\.rawValue)
        self.typ = typ
        self.iss = .init(value: "pmstt")
        self.iat = .init(value: issuedAt)
        self.exp = .init(value: expiresAt)
    }

    func verify(using _: some JWTAlgorithm) async throws {
        guard typ == "access", iss.value == "pmstt" else { throw Abort(.unauthorized) }
        try exp.verifyNotExpired()
    }
}

struct RefreshPayload: JWTPayload {
    let sub: UUID
    let sid: UUID
    let platform: ClientPlatform.RawValue
    let installationID: String
    let authority: SessionAuthority.RawValue
    let jti: UUID
    let typ: String
    let iss: IssuerClaim
    let iat: IssuedAtClaim
    let exp: ExpirationClaim

    func verify(using _: some JWTAlgorithm) async throws {
        guard typ == "refresh", iss.value == "pmstt" else { throw Abort(.unauthorized) }
        try exp.verifyNotExpired()
    }
}

struct LegacyUserPayload: JWTPayload {
    let sub: UUID
    let email: String?
    let exp: ExpirationClaim

    func verify(using _: some JWTAlgorithm) async throws { try exp.verifyNotExpired() }
}

struct SessionAuthenticator: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        do {
            request.auth.login(try await request.jwt.verify(bearer.token, as: UserPayload.self))
        } catch {
            let legacy = try await request.jwt.verify(bearer.token, as: LegacyUserPayload.self)
            request.auth.login(UserPayload(
                sub: legacy.sub,
                sid: UUID.zero,
                platform: .legacy,
                installationID: "",
                capabilities: [.read, .logout],
                expiresAt: legacy.exp.value
            ))
        }
    }
}

private extension UUID {
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
