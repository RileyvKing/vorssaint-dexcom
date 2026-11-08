// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The glucose extension's text. It ships in English for now; the shape is
/// the same one the other sections use, so translations can be added without
/// touching the views.
struct NotchGlucoseStrings {
    let title: String
    let hubDescription: String
    let summary: String
    let description: String

    let showInIsland: String
    let priority: String
    let priorityHint: String
    let targetRange: String
    let targetRangeHint: String
    let lowThreshold: String
    let highThreshold: String

    let account: String
    let accountHint: String
    let username: String
    let password: String
    let region: String
    let regionUS: String
    let regionOUS: String
    let regionJP: String

    let saveAndTest: String
    let testing: String
    let clear: String
    let credentialsSaved: String
    let credentialsMissing: String
    let saveFailed: String
    let testSuccessFormat: String
    let testNoReadings: String
    let invalidCredentials: String
    let tooManyAttempts: String
    let networkError: String
    let malformedReading: String
    let serverErrorFormat: String

    let lastUpdatedFormat: String
    let neverUpdated: String
    let noReading: String
    let stale: String
    let refresh: String
    let refreshing: String
    let configure: String

    let unit: String
    let notMedical: String

    func error(_ error: ShareAPIError) -> String {
        switch error {
        case .invalidCredentials: return invalidCredentials
        case .tooManyAttempts: return tooManyAttempts
        case .sessionExpired: return networkError
        case .network: return networkError
        case .malformedResponse: return malformedReading
        case .noReadings: return testNoReadings
        case .server(let message): return String(format: serverErrorFormat, message)
        }
    }

    func signedIn(_ reading: GlucoseReading, age: String) -> String {
        let shown = reading.status == nil ? reading.displayText + " " + unit : reading.displayText
        return String(format: testSuccessFormat, shown, age)
    }

    func updated(_ age: String) -> String {
        String(format: lastUpdatedFormat, age)
    }
}

extension FeatureStrings {
    /// One book of text for every language until the extension is translated.
    static func notchGlucose(_ language: AppLanguage) -> NotchGlucoseStrings {
        _ = language
        return NotchGlucoseStrings(
            title: "Glucose",
            hubDescription: "Show your Dexcom Share glucose reading, its direction and its history in the Dynamic Island.",
            summary: "Your Dexcom Share reading, with its trend arrow, kept current in the Dynamic Island.",
            description: "Sign in with the Dexcom account that publishes your sensor readings. The island checks Share for a new reading every minute and keeps the last one for ten minutes.",
            showInIsland: "Show glucose in the island",
            priority: "Glucose takes the island while fresh",
            priorityHint: "When a reading is less than ten minutes old it replaces music, agents and other activities. When it goes stale, they come back.",
            targetRange: "Target Range",
            targetRangeHint: "Readings below the low value are red, above the high value yellow, and in between green. The same colors mark the graph.",
            lowThreshold: "Low threshold",
            highThreshold: "High threshold",
            account: "Dexcom Share",
            accountHint: "Use the account that runs the Dexcom mobile app, not a follower’s account. Choose the region where the account was created.",
            username: "Username",
            password: "Password",
            region: "Region",
            regionUS: "United States",
            regionOUS: "Outside the United States",
            regionJP: "Japan",
            saveAndTest: "Save & Test",
            testing: "Testing…",
            clear: "Clear Credentials",
            credentialsSaved: "Credentials saved",
            credentialsMissing: "Add your Dexcom Share username and password.",
            saveFailed: "Dexcom accepted the sign-in, but the credentials could not be saved to the Keychain.",
            testSuccessFormat: "Signed in. Latest reading %1$@, %2$@.",
            testNoReadings: "Signed in, but no reading was found in the last day.",
            invalidCredentials: "That username or password was not accepted.",
            tooManyAttempts: "Dexcom asked us to wait before trying again. Check the password, then try later.",
            networkError: "Could not reach Dexcom. Check the connection and the region.",
            malformedReading: "Dexcom answered with something the app could not read.",
            serverErrorFormat: "Dexcom reported an error: %@",
            lastUpdatedFormat: "Updated %@",
            neverUpdated: "Not updated yet",
            noReading: "No recent reading",
            stale: "This reading is old. It is no longer shown in the island.",
            refresh: "Refresh",
            refreshing: "Refreshing…",
            configure: "Set Up Dexcom Share",
            unit: "mg/dL",
            notMedical: "This is a convenience display, not a medical device. Do not use it for treatment decisions."
        )
    }
}
