// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The three Share API regions. Each has its own host and the application id
/// the Dexcom mobile app presents, which the service checks before it will
/// hand out an account id or a session.
enum GlucoseRegion: String, CaseIterable, Identifiable {
    case us, ous, jp

    var id: String { rawValue }

    var baseURL: URL {
        switch self {
        case .us: return URL(string: "https://share2.dexcom.com/ShareWebServices/Services/")!
        case .ous: return URL(string: "https://shareous1.dexcom.com/ShareWebServices/Services/")!
        case .jp: return URL(string: "https://share.dexcom.jp/ShareWebServices/Services/")!
        }
    }

    /// The US and outside-US endpoints share the id the current mobile app
    /// uses; Japan presents its own.
    var applicationID: String {
        switch self {
        case .us, .ous: return "d89443d2-327c-4a6f-89e5-496bbb0317db"
        case .jp: return "d8665ade-9673-4e27-9ff6-92db4ce13d13"
        }
    }

    static func stored(_ raw: String?) -> GlucoseRegion {
        raw.flatMap(GlucoseRegion.init(rawValue:)) ?? .us
    }
}

/// The direction the Share API reports. Its raw values are the strings the
/// endpoint returns now; older receivers returned an index, which
/// `from(apiValue:)` also accepts.
enum GlucoseTrend: String, CaseIterable, Codable {
    case doubleUp = "DoubleUp"
    case singleUp = "SingleUp"
    case fortyFiveUp = "FortyFiveUp"
    case flat = "Flat"
    case fortyFiveDown = "FortyFiveDown"
    case singleDown = "SingleDown"
    case doubleDown = "DoubleDown"
    case none = "None"
    case notComputable = "NotComputable"
    case rateOutOfRange = "RateOutOfRange"

    /// The arrow drawn beside the reading, when there is one.
    var symbol: String? {
        switch self {
        case .doubleUp: return "chevron.up.2"
        case .singleUp: return "arrow.up"
        case .fortyFiveUp: return "arrow.up.right"
        case .flat: return "arrow.right"
        case .fortyFiveDown: return "arrow.down.right"
        case .singleDown: return "arrow.down"
        case .doubleDown: return "chevron.down.2"
        case .none: return nil
        case .notComputable, .rateOutOfRange: return "questionmark"
        }
    }

    /// A plain glyph for text-only contexts and VoiceOver.
    var arrow: String {
        switch self {
        case .doubleUp: return "↑↑"
        case .singleUp: return "↑"
        case .fortyFiveUp: return "↗"
        case .flat: return "→"
        case .fortyFiveDown: return "↘"
        case .singleDown: return "↓"
        case .doubleDown: return "↓↓"
        case .none: return ""
        case .notComputable, .rateOutOfRange: return "?"
        }
    }

    var spoken: String {
        switch self {
        case .doubleUp: return "rising quickly"
        case .singleUp: return "rising"
        case .fortyFiveUp: return "rising slightly"
        case .flat: return "steady"
        case .fortyFiveDown: return "falling slightly"
        case .singleDown: return "falling"
        case .doubleDown: return "falling quickly"
        case .none: return "not reported"
        case .notComputable: return "direction unavailable"
        case .rateOutOfRange: return "direction out of range"
        }
    }

    static func from(apiValue: Any?) -> GlucoseTrend? {
        if let text = apiValue as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = GlucoseTrend(rawValue: trimmed) { return exact }
            // Be forgiving of a server or an old receiver that changed case.
            return GlucoseTrend.allCases.first { $0.rawValue.lowercased() == trimmed.lowercased() }
        }
        if let number = GlucoseSupport.integer(apiValue) {
            switch number {
            case 0: return GlucoseTrend.none
            case 1: return .doubleUp
            case 2: return .singleUp
            case 3: return .fortyFiveUp
            case 4: return .flat
            case 5: return .fortyFiveDown
            case 6: return .singleDown
            case 7: return .doubleDown
            case 8: return .notComputable
            case 9: return .rateOutOfRange
            default: return nil
            }
        }
        return nil
    }
}

/// One glucose value in the shape the Share API reports it: a number in the
/// measuring range, or the LOW/HIGH status outside it.
struct GlucoseReading: Equatable, Codable {
    enum Status: String, Codable, Equatable {
        case low, high
    }

    /// mg/dL, from 40 through 399. Nil for LOW and HIGH.
    var value: Int?
    var status: Status?
    var trend: GlucoseTrend?
    /// mg/dL per minute, when the source knows it. The Share API does not,
    /// so this is usually nil.
    var trendRate: Double?
    var recordedAt: Date

    var displayText: String {
        switch status {
        case .low: return "LOW"
        case .high: return "HIGH"
        case nil: return value.map(String.init) ?? "--"
        }
    }

    var isLow: Bool { status == .low }
    var isHigh: Bool { status == .high }

    /// What the reading has in the measuring range, for a graph.
    var chartValue: Double? {
        if let value { return Double(value) }
        switch status {
        case .low: return 40
        case .high: return 400
        case nil: return nil
        }
    }

    /// The Share API's own record is newest first. A missing or unusable
    /// record is skipped rather than inventing a reading.
    init?(shareRecord record: [String: Any]) {
        let reported = record["Value"] ?? record["value"]
        let reportedStatus = (record["Status"] ?? record["status"]) as? String
        let numeric = GlucoseSupport.integer(reported)
        var reading = GlucoseReading(value: nil, status: nil, trend: nil, trendRate: nil,
                                     recordedAt: Date(timeIntervalSince1970: 0))

        if let numeric {
            // 39 and 401 are the API's computed markers for outside the
            // measuring range, shown as LOW and HIGH rather than numbers.
            if numeric <= 39 {
                reading.status = .low
            } else if numeric >= 401 {
                reading.status = .high
            } else {
                reading.value = numeric
            }
        } else if let text = reported as? String,
                  ["low", "high"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            reading.status = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "low" ? .low : .high
        } else if let reportedStatus {
            switch reportedStatus.lowercased() {
            case "low": reading.status = .low
            case "high": reading.status = .high
            default: break
            }
        }

        guard reading.value != nil || reading.status != nil,
              let recordedAt = GlucoseSupport.recordDate(record) else { return nil }

        reading.recordedAt = recordedAt
        reading.trend = GlucoseTrend.from(apiValue: record["Trend"] ?? record["trend"])
        reading.trendRate = GlucoseSupport.double(record["TrendRate"] ?? record["trendRate"])
        self = reading
    }

    init(value: Int?, status: Status? = nil, trend: GlucoseTrend? = nil,
         trendRate: Double? = nil, recordedAt: Date) {
        self.value = value
        self.status = status
        self.trend = trend
        self.trendRate = trendRate
        self.recordedAt = recordedAt
    }
}

/// Where a reading falls against the person's target range. The band's ends
/// are values, so the strip and the graph share one decision.
enum GlucoseLevel: Equatable {
    case low, inRange, high
}

/// The configurable target range. Values are mg/dL and are clamped so the
/// low end always sits below the high end inside the sensor's range.
struct GlucoseTargets: Equatable {
    static let defaultLow = 80
    static let defaultHigh = 200
    static let range = 40...400

    let low: Int
    let high: Int

    init(low: Int = GlucoseTargets.defaultLow, high: Int = GlucoseTargets.defaultHigh) {
        let clampedLow = min(max(low, Self.range.lowerBound), Self.range.upperBound - 1)
        self.low = clampedLow
        self.high = min(max(high, clampedLow + 1), Self.range.upperBound)
    }

    func level(for reading: GlucoseReading) -> GlucoseLevel {
        switch reading.status {
        case .low: return .low
        case .high: return .high
        case nil: break
        }
        guard let value = reading.value else { return .inRange }
        return level(for: Double(value))
    }

    func level(for value: Double) -> GlucoseLevel {
        if value < Double(low) { return .low }
        if value > Double(high) { return .high }
        return .inRange
    }
}

/// Errors the Share API and the client can surface. Kept free of UI text so
/// the settings can phrase them in the app's language.
enum ShareAPIError: Error, Equatable {
    case invalidCredentials
    case tooManyAttempts
    case sessionExpired
    case network
    case malformedResponse
    case noReadings
    case server(String)
}

enum GlucoseSupport {
    /// A reading is current for two sensor cycles, which is also the window
    /// the API itself uses for a current reading.
    static let freshnessWindow: TimeInterval = 10 * 60
    /// How much data the page asks for: one day, the API's maximum window.
    static let historyMinutes = 1440
    static let maximumReadings = 288
    static let maximumHistory = 288

    static let stripWingRange: ClosedRange<CGFloat> = 44...78

    /// The newest reading, if there is one. Share returns newest first; the
    /// sort here keeps a server that changes that from reordering the graph.
    static func latest(from readings: [GlucoseReading]) -> GlucoseReading? {
        readings.max { $0.recordedAt < $1.recordedAt }
    }

    static func sortedNewestFirst(_ readings: [GlucoseReading]) -> [GlucoseReading] {
        readings.sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Merge a poll's results into the history, keeping one entry per sensor
    /// time and the newest day only.
    static func merged(history: [GlucoseReading], adding readings: [GlucoseReading],
                       now: Date = Date()) -> [GlucoseReading] {
        guard !readings.isEmpty else { return history }
        var byTime: [Int: GlucoseReading] = [:]
        for reading in history {
            byTime[Int(reading.recordedAt.timeIntervalSince1970.rounded())] = reading
        }
        for reading in readings {
            byTime[Int(reading.recordedAt.timeIntervalSince1970.rounded())] = reading
        }
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        return byTime.values
            .filter { $0.recordedAt >= cutoff }
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(maximumHistory)
            .map { $0 }
    }

    /// A reading whose sensor time is within the freshness window. A sensor
    /// clock a little ahead is treated as current rather than stale.
    static func isFresh(_ reading: GlucoseReading, now: Date = Date()) -> Bool {
        let age = age(of: reading, now: now)
        return age <= freshnessWindow
    }

    /// A reading's age, clamped at zero for a sensor clock that runs ahead.
    static func age(of reading: GlucoseReading, now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(reading.recordedAt))
    }

    /// When a fresh reading stops taking the closed island.
    static func freshUntil(_ reading: GlucoseReading) -> Date {
        reading.recordedAt.addingTimeInterval(freshnessWindow)
    }

    /// The trend to fall back on when a source reports none: the change
    /// between the two newest readings, in the Dexcom bands.
    static func computedTrend(from readings: [GlucoseReading]) -> GlucoseTrend? {
        let sorted = sortedNewestFirst(readings)
        guard sorted.count >= 2,
              let newer = sorted[0].chartValue,
              let older = sorted[1].chartValue else { return nil }
        let minutes = sorted[0].recordedAt.timeIntervalSince(sorted[1].recordedAt) / 60
        guard minutes > 0 else { return nil }
        let rate = (newer - older) / minutes
        switch rate {
        case 3...: return .doubleUp
        case 2..<3: return .singleUp
        case 1..<2: return .fortyFiveUp
        case (-1)..<1: return .flat
        case (-2)..<(-1): return .fortyFiveDown
        case (-3)..<(-2): return .singleDown
        default: return .doubleDown
        }
    }

    /// The date a Share record carries. `DT` is the display time with its
    /// offset, `WT` the same instant as epoch milliseconds, and `ST` an ISO
    /// fallback; all three end at the same absolute time.
    static func recordDate(_ record: [String: Any]) -> Date? {
        for key in ["DT", "WT", "ST"] {
            guard let text = record[key] as? String else { continue }
            if let date = dexcomDate(text) { return date }
        }
        return nil
    }

    /// `Date(1751234567890-0700)`, `Date(1751234567890)` and an ISO 8601
    /// timestamp in either the local or the UTC form.
    static func dexcomDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Date(") {
            guard let open = trimmed.firstIndex(of: "("), let close = trimmed.lastIndex(of: ")"),
                  open < close else { return nil }
            let inner = trimmed[trimmed.index(after: open)..<close]
            let digits = inner.prefix { $0.isNumber }
            guard !digits.isEmpty, let milliseconds = Double(digits) else { return nil }
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: trimmed)
    }

    static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let number as Int: return number
        case let number as Double: return number.isFinite ? Int(number) : nil
        case let text as String: return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let number as Double: return number.isFinite ? number : nil
        case let text as String: return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
}

/// The legacy Share API's requests and responses. Building them here keeps
/// the client free of string assembly and lets the contracts be tested
/// without a network.
enum ShareAPISupport {
    static let authenticatePath = "General/AuthenticatePublisherAccount"
    static let loginPath = "General/LoginPublisherAccountById"
    static let readingsPath = "Publisher/ReadPublisherLatestGlucoseValues"

    static func authenticateRequest(region: GlucoseRegion, username: String,
                                    password: String) -> URLRequest {
        request(region: region, path: authenticatePath, body: [
            "accountName": username,
            "password": password,
            "applicationId": region.applicationID,
        ])
    }

    static func loginRequest(region: GlucoseRegion, accountID: String,
                             password: String) -> URLRequest {
        request(region: region, path: loginPath, body: [
            "accountId": accountID,
            "password": password,
            "applicationId": region.applicationID,
        ])
    }

    static func readingsRequest(region: GlucoseRegion, sessionID: String, minutes: Int,
                                maxCount: Int) -> URLRequest {
        var components = URLComponents(url: region.baseURL.appending(path: readingsPath),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionID),
            URLQueryItem(name: "minutes", value: String(min(minutes, GlucoseSupport.historyMinutes))),
            URLQueryItem(name: "maxCount", value: String(min(max(maxCount, 1), GlucoseSupport.maximumReadings))),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("Dexcom Share/3.0.2.11 CFNetwork/711.2.23 Darwin/14.0.0",
                         forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("{}".utf8)
        return request
    }

    private static func request(region: GlucoseRegion, path: String, body: [String: String]) -> URLRequest {
        var request = URLRequest(url: region.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("Dexcom Share/3.0.2.11 CFNetwork/711.2.23 Darwin/14.0.0",
                         forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// A login and a session both come back as one quoted JSON string.
    static func identifier(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) {
            // An error body is an object; it is never an identifier.
            guard let text = object as? String, validIdentifier(text) else { return nil }
            return text
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) {
            return validIdentifier(text) ? text : nil
        }
        return nil
    }

    private static func validIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text != "00000000-0000-0000-0000-000000000000"
    }

    static func readings(from data: Data) -> [GlucoseReading] {
        (try? readingsOrError(from: data)) ?? []
    }

    /// Distinguishes an empty list from a response the app cannot read.
    static func readingsOrError(from data: Data) throws -> [GlucoseReading] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ShareAPIError.malformedResponse
        }
        return GlucoseSupport.sortedNewestFirst(array.compactMap(GlucoseReading.init(shareRecord:)))
    }

    /// The API answers a failed login or an expired session with a `Code`
    /// and a `Message`; map the codes the client acts on and leave the rest.
    static func error(from data: Data, status: Int) -> ShareAPIError {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = object["Code"] as? String {
            switch code {
            case "SessionIdNotFound", "SessionNotValid":
                return .sessionExpired
            case "AccountPasswordInvalid":
                return .invalidCredentials
            case "SSO_AuthenticateMaxAttemptsExceeded":
                return .tooManyAttempts
            case "SSO_InternalError":
                if let message = object["Message"] as? String,
                   message.contains("Cannot Authenticate") { return .invalidCredentials }
                return .server(object["Message"] as? String ?? code)
            case "InvalidArgument":
                if let message = object["Message"] as? String,
                   message.contains("accountName") || message.contains("password") {
                    return .invalidCredentials
                }
                return .server(object["Message"] as? String ?? code)
            default:
                return .server(object["Message"] as? String ?? code)
            }
        }
        if status == 401 || status == 403 { return .sessionExpired }
        return .malformedResponse
    }
}
