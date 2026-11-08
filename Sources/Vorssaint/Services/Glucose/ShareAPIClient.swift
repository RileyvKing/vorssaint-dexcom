// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Talks to the legacy Dexcom Share service. The password stays in memory for
/// the lifetime of the client so an expired session can be renewed once; it
/// is never written by this type.
final class ShareAPIClient {
    let region: GlucoseRegion

    private let session: URLSession
    private var credentials: (username: String, password: String)?
    private var sessionID: String?

    init(region: GlucoseRegion, session: URLSession? = nil) {
        self.region = region
        self.session = session ?? Self.makeSession()
    }

    deinit {
        session.invalidateAndCancel()
    }

    var isSignedIn: Bool { sessionID != nil }

    /// Authenticate the account and open a publishing session. Both answers
    /// arrive as a single quoted JSON string.
    func signIn(username: String, password: String) async throws {
        let accountData = try await perform(
            ShareAPISupport.authenticateRequest(region: region, username: username, password: password))
        guard let accountID = ShareAPISupport.identifier(from: accountData) else {
            throw ShareAPIError.malformedResponse
        }
        let sessionData = try await perform(
            ShareAPISupport.loginRequest(region: region, accountID: accountID, password: password))
        guard let sessionID = ShareAPISupport.identifier(from: sessionData) else {
            throw ShareAPIError.malformedResponse
        }
        self.sessionID = sessionID
        credentials = (username, password)
    }

    /// The newest readings, best first. A session the service forgot is
    /// renewed once, as the Share client libraries do.
    func fetchReadings(minutes: Int = GlucoseSupport.historyMinutes,
                       maxCount: Int = 2) async throws -> [GlucoseReading] {
        guard let sessionID else { throw ShareAPIError.sessionExpired }
        do {
            return try await readings(sessionID: sessionID, minutes: minutes, maxCount: maxCount)
        } catch ShareAPIError.sessionExpired {
            try await renewSession()
            guard let renewed = self.sessionID else { throw ShareAPIError.sessionExpired }
            return try await readings(sessionID: renewed, minutes: minutes, maxCount: maxCount)
        }
    }

    /// A one-shot check for the settings, on a client of its own so a test
    /// never disturbs the running service's session.
    static func test(username: String, password: String, region: GlucoseRegion) async throws -> [GlucoseReading] {
        let client = ShareAPIClient(region: region)
        try await client.signIn(username: username, password: password)
        return try await client.fetchReadings(maxCount: 2)
    }

    private func renewSession() async throws {
        guard let credentials else { throw ShareAPIError.sessionExpired }
        sessionID = nil
        try await signIn(username: credentials.username, password: credentials.password)
    }

    private func readings(sessionID: String, minutes: Int, maxCount: Int) async throws -> [GlucoseReading] {
        let data = try await perform(
            ShareAPISupport.readingsRequest(region: region, sessionID: sessionID,
                                            minutes: minutes, maxCount: maxCount))
        // The Share service answers an expired session with an empty body
        // instead of an error code; the caller renews the session once.
        guard !data.isEmpty else { throw ShareAPIError.sessionExpired }
        return try ShareAPISupport.readingsOrError(from: data)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ShareAPIError.network
        }
        guard let http = response as? HTTPURLResponse else { throw ShareAPIError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ShareAPISupport.error(from: data, status: http.statusCode)
        }
        return data
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}
