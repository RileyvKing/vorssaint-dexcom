// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Dexcom Share contracts: request shapes, record parsing, trend
/// mapping, freshness and the error codes the island acts on. No network.
enum GlucoseTests {
    static func run(_ suite: TestSuite) {
        regionContracts(suite)
        requestContracts(suite)
        identifierContracts(suite)
        readingContracts(suite)
        dateContracts(suite)
        freshnessContracts(suite)
        historyContracts(suite)
        trendContracts(suite)
        targetContracts(suite)
        errorContracts(suite)
    }

    private static func regionContracts(_ suite: TestSuite) {
        suite.expect(GlucoseRegion.us.baseURL.absoluteString == "https://share2.dexcom.com/ShareWebServices/Services/",
                     "the US share host is the one the phone app uses")
        suite.expect(GlucoseRegion.ous.baseURL.absoluteString.contains("shareous1.dexcom.com"),
                     "outside the US uses its own host")
        suite.expect(GlucoseRegion.jp.baseURL.absoluteString.contains("share.dexcom.jp"),
                     "Japan uses its own host")
        suite.expect(GlucoseRegion.us.applicationID == GlucoseRegion.ous.applicationID
                        && GlucoseRegion.us.applicationID != GlucoseRegion.jp.applicationID
                        && GlucoseRegion.us.applicationID == "d89443d2-327c-4a6f-89e5-496bbb0317db",
                     "the US and outside-US hosts share the current app id, Japan has its own")
        suite.expect(GlucoseRegion.stored(nil) == .us && GlucoseRegion.stored("jp") == .jp
                        && GlucoseRegion.stored("elsewhere") == .us,
                     "an unknown or missing region falls back to the US")
    }

    private static func requestContracts(_ suite: TestSuite) {
        let authenticate = ShareAPISupport.authenticateRequest(region: .us, username: "person@example.com",
                                                               password: "secret")
        suite.expect(authenticate.httpMethod == "POST"
                        && authenticate.url?.path.hasSuffix("/General/AuthenticatePublisherAccount") == true,
                     "the first sign-in posts to the authenticate endpoint")
        let body = authenticate.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: String]
        }
        suite.expect(body?["accountName"] == "person@example.com"
                        && body?["password"] == "secret"
                        && body?["applicationId"] == GlucoseRegion.us.applicationID,
                     "the authenticate body carries the account, password and app id")

        let login = ShareAPISupport.loginRequest(region: .jp, accountID: "account", password: "secret")
        let loginBody = login.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: String]
        }
        suite.expect(login.url?.path.hasSuffix("/General/LoginPublisherAccountById") == true
                        && loginBody?["accountId"] == "account"
                        && loginBody?["applicationId"] == GlucoseRegion.jp.applicationID,
                     "the second step logs in with the account id and the regional app id")

        let readings = ShareAPISupport.readingsRequest(region: .us, sessionID: "session",
                                                       minutes: 9_999, maxCount: 9_999)
        let components = readings.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })
        suite.expect(readings.httpMethod == "POST"
                        && readings.url?.path.hasSuffix("/Publisher/ReadPublisherLatestGlucoseValues") == true,
                     "readings are a POST to the publisher endpoint")
        suite.expect(query["sessionId"] == "session" && query["minutes"] == "1440"
                        && query["maxCount"] == "288",
                     "the day is the most the endpoint takes, and the count is capped")
        suite.expect(readings.value(forHTTPHeaderField: "Accept") == "application/json"
                        && readings.value(forHTTPHeaderField: "Content-Type") == "application/json",
                     "the API is asked for and answered in JSON")
    }

    private static func identifierContracts(_ suite: TestSuite) {
        suite.expect(ShareAPISupport.identifier(from: Data("\"abc-123\"".utf8)) == "abc-123",
                     "a quoted identifier is unwrapped")
        suite.expect(ShareAPISupport.identifier(from: Data("abc-123".utf8)) == "abc-123",
                     "an unquoted identifier is accepted")
        suite.expect(ShareAPISupport.identifier(from: Data("\"00000000-0000-0000-0000-000000000000\"".utf8)) == nil,
                     "the all-zero UUID is an error, not a session")
        suite.expect(ShareAPISupport.identifier(from: Data(#"{"Code":"SessionNotValid"}"#.utf8)) == nil,
                     "an error object is never mistaken for a session")
        suite.expect(ShareAPISupport.identifier(from: Data()) == nil,
                     "an empty answer is not an identifier")
    }

    private static func readingContracts(_ suite: TestSuite) {
        let normal = GlucoseReading(shareRecord: [
            "Value": 142, "Trend": "FortyFiveUp", "DT": "Date(1751234567890-0700)",
        ])
        suite.expect(normal?.displayText == "142" && normal?.trend == .fortyFiveUp
                        && normal?.value == 142 && normal?.status == nil,
                     "a measuring-range value keeps its number and trend")

        let low = GlucoseReading(shareRecord: ["Value": 39, "Trend": "Flat", "DT": "Date(1)"])
        let high = GlucoseReading(shareRecord: ["Value": 401, "Trend": "SingleDown", "DT": "Date(1)"])
        suite.expect(low?.displayText == "LOW" && low?.status == .low && low?.value == nil,
                     "39 is LOW rather than a number")
        suite.expect(high?.displayText == "HIGH" && high?.status == .high && high?.value == nil,
                     "401 is HIGH rather than a number")

        let forty = GlucoseReading(shareRecord: ["Value": 40, "Trend": "Flat", "DT": "Date(1)"])
        let fourHundred = GlucoseReading(shareRecord: ["Value": 400, "Trend": "Flat", "DT": "Date(1)"])
        suite.expect(forty?.displayText == "40" && fourHundred?.displayText == "400",
                     "the measuring range's ends remain numbers")

        let statusOnly = GlucoseReading(shareRecord: ["Status": "high", "Trend": "Flat", "DT": "Date(1)"])
        suite.expect(statusOnly?.displayText == "HIGH",
                     "a record that only carries a status still reads")
        let wordValue = GlucoseReading(shareRecord: ["Value": "LOW", "Trend": "Flat", "DT": "Date(1)"])
        suite.expect(wordValue?.displayText == "LOW",
                     "a source that spells LOW in the value still reads")

        suite.expect(GlucoseReading(shareRecord: ["Trend": "Flat", "DT": "Date(1)"]) == nil,
                     "a record with neither a value nor a status is not a reading")
        suite.expect(GlucoseReading(shareRecord: ["Value": 120, "Trend": "Flat"]) == nil,
                     "a record without a time is not a reading")

        let legacy = GlucoseReading(shareRecord: ["Value": 120, "Trend": 4, "DT": "Date(1)"])
        suite.expect(legacy?.trend == .flat,
                     "an older receiver's numeric trend maps to the same direction")

        let lowValue = GlucoseReading(shareRecord: ["Value": 39, "Trend": "None", "DT": "Date(1)"])
        suite.expect(lowValue?.chartValue == 40,
                     "LOW has a graph value at the bottom of the range")
    }

    private static func dateContracts(_ suite: TestSuite) {
        let displayed = GlucoseSupport.dexcomDate("Date(1751234567890-0700)")
        suite.expectClose(displayed?.timeIntervalSince1970 ?? .nan, 1_751_234_567.89,
                          "the display date's epoch milliseconds are the instant")
        let withoutOffset = GlucoseSupport.dexcomDate("Date(1751234567890)")
        suite.expectClose(withoutOffset?.timeIntervalSince1970 ?? .nan, 1_751_234_567.89,
                          "a date without an offset is the same epoch")
        let iso = GlucoseSupport.dexcomDate("2026-01-02T03:04:05Z")
        suite.expect(iso != nil && GlucoseSupport.dexcomDate("2026-01-02T03:04:05") != nil,
                     "the ISO fallbacks parse both with and without a zone")
        suite.expect(GlucoseSupport.dexcomDate("not a date") == nil,
                     "unparseable time text is rejected")
    }

    private static func freshnessContracts(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = GlucoseReading(value: 120, trend: .flat,
                                   recordedAt: now.addingTimeInterval(-9 * 60 - 59))
        let stale = GlucoseReading(value: 120, trend: .flat,
                                   recordedAt: now.addingTimeInterval(-10 * 60 - 1))
        let ahead = GlucoseReading(value: 120, trend: .flat,
                                   recordedAt: now.addingTimeInterval(90))
        suite.expect(GlucoseSupport.isFresh(fresh, now: now),
                     "a reading inside ten minutes is fresh")
        suite.expect(!GlucoseSupport.isFresh(stale, now: now),
                     "a reading past ten minutes is no longer fresh")
        suite.expect(GlucoseSupport.isFresh(ahead, now: now)
                        && GlucoseSupport.age(of: ahead, now: now) == 0,
                     "a sensor clock a little ahead is current, not negative")
        suite.expectClose(GlucoseSupport.freshUntil(fresh).timeIntervalSince(fresh.recordedAt),
                          GlucoseSupport.freshnessWindow,
                          "freshness ends one window after the sensor time")
    }

    private static func historyContracts(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let older = GlucoseReading(value: 100, trend: .flat, recordedAt: now.addingTimeInterval(-600))
        let newer = GlucoseReading(value: 110, trend: .flat, recordedAt: now.addingTimeInterval(-300))
        let duplicate = GlucoseReading(value: 111, trend: .flat, recordedAt: newer.recordedAt)
        let ancient = GlucoseReading(value: 130, trend: .flat, recordedAt: now.addingTimeInterval(-25 * 60 * 60))
        let merged = GlucoseSupport.merged(history: [older, newer], adding: [duplicate, ancient], now: now)
        suite.expect(merged.count == 2 && merged.first?.value == 111 && merged.last?.value == 100,
                     "history keeps one entry per sensor time, newest first, and drops yesterday")
        suite.expect(GlucoseSupport.latest(from: [older, newer]) == newer,
                     "the newest reading is chosen regardless of response order")
        suite.expect(GlucoseSupport.sortedNewestFirst([older, newer]).first == newer,
                     "sorting puts the newest first")
    }

    private static func trendContracts(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func trend(_ old: Int, _ new: Int, minutes: TimeInterval = 10) -> GlucoseTrend? {
            GlucoseSupport.computedTrend(from: [
                GlucoseReading(value: new, recordedAt: now),
                GlucoseReading(value: old, recordedAt: now.addingTimeInterval(-minutes * 60)),
            ])
        }
        suite.expect(trend(100, 100) == .flat, "no change is flat")
        suite.expect(trend(100, 115) == .fortyFiveUp, "1.5 mg/dL/min is a slight rise")
        suite.expect(trend(100, 125) == .singleUp, "2.5 mg/dL/min is a rise")
        suite.expect(trend(100, 140) == .doubleUp, "4 mg/dL/min rises quickly")
        suite.expect(trend(140, 100) == .doubleDown, "4 mg/dL/min falls quickly")
        suite.expect(GlucoseTrend.from(apiValue: "flat") == .flat
                        && GlucoseTrend.from(apiValue: "FORTYFIVEDOWN") == .fortyFiveDown
                        && GlucoseTrend.from(apiValue: "NotComputable") == .notComputable,
                     "trend text is forgiving of case and keeps unknown states")
        suite.expect(GlucoseTrend.flat.symbol == "arrow.right" && GlucoseTrend.doubleUp.symbol == "chevron.up.2"
                        && GlucoseTrend.none.symbol == nil && GlucoseTrend.flat.arrow == "→",
                     "each direction has the arrow the strip draws")
    }

    private static func targetContracts(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let targets = GlucoseTargets(low: 80, high: 200)
        func level(_ value: Int?, status: GlucoseReading.Status? = nil) -> GlucoseLevel {
            targets.level(for: GlucoseReading(value: value, status: status, recordedAt: now))
        }
        suite.expect(level(79) == .low && level(80) == .inRange
                        && level(200) == .inRange && level(201) == .high,
                     "the target range is inclusive at both ends")
        suite.expect(level(nil, status: .low) == .low && level(nil, status: .high) == .high,
                     "LOW and HIGH keep their side of the range")
        suite.expect(targets.level(for: 79.9) == .low && targets.level(for: 200.1) == .high,
                     "chart values use the same thresholds")

        suite.expect(GlucoseTargets(low: 500, high: 10) == GlucoseTargets(low: 399, high: 400),
                     "stored values are clamped into the sensor's range and kept in order")
        suite.expect(GlucoseTargets(low: 200, high: 80) == GlucoseTargets(low: 200, high: 201),
                     "a high value below the low one becomes the next value above it")
        suite.expect(GlucoseTargets(low: 40, high: 400) == GlucoseTargets(low: 40, high: 400),
                     "the widest valid range survives unchanged")
    }

    private static func errorContracts(_ suite: TestSuite) {        func error(_ json: String, status: Int = 500) -> ShareAPIError? {
            ShareAPISupport.error(from: Data(json.utf8), status: status)
        }
        suite.expect(error(#"{"Code":"AccountPasswordInvalid","Message":"no"}"#) == .invalidCredentials,
                     "a bad password maps to its own error")
        suite.expect(error(#"{"Code":"SessionNotValid","Message":"no"}"#) == .sessionExpired
                        && error(#"{"Code":"SessionIdNotFound","Message":"no"}"#) == .sessionExpired,
                     "an expired session is renewed")
        suite.expect(error(#"{"Code":"SSO_AuthenticateMaxAttemptsExceeded","Message":"no"}"#) == .tooManyAttempts,
                     "too many attempts asks the person to wait")
        suite.expect(error(#"{"Code":"InvalidArgument","Message":"password is invalid"}"#) == .invalidCredentials,
                     "an invalid password argument is a credential error")
        suite.expect(error(#"{"Code":"SomethingElse","Message":"broken"}"#) == .server("broken"),
                     "an unknown server error keeps its message")
        suite.expect(error("not json", status: 401) == .sessionExpired
                        && error("not json", status: 200) == .malformedResponse,
                     "a 401 is a session problem and anything else unreadable is malformed")

        let json = """
        [
          {"Value":39,"Trend":"Flat","DT":"Date(1751234567890-0700)"},
          {"Value":401,"Trend":"SingleDown","DT":"Date(1751234567891-0700)"}
        ]
        """
        let readings = ShareAPISupport.readings(from: Data(json.utf8))
        suite.expect(readings.count == 2 && readings.first?.displayText == "HIGH"
                        && readings.last?.displayText == "LOW",
                     "a readings response parses and stays newest first")
        do {
            _ = try ShareAPISupport.readingsOrError(from: Data("not a list".utf8))
            suite.expect(false, "a malformed readings response is rejected")
        } catch let error as ShareAPIError {
            suite.expect(error == .malformedResponse, "a malformed readings response is rejected")
        } catch {
            suite.expect(false, "a malformed readings response is rejected")
        }
    }
}
