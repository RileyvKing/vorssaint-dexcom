// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Keeps one Dexcom Share reading current and decides when it is fresh
/// enough to take the closed island. The endpoint only adds a reading every
/// five minutes, so a minute between checks catches each one soon after it
/// lands; the reading stays usable for two sensor cycles.
final class GlucoseService: ObservableObject {
    static let shared = GlucoseService()

    @Published private(set) var reading: GlucoseReading?
    @Published private(set) var isFresh = false
    @Published private(set) var history: [GlucoseReading] = []
    @Published private(set) var lastError: ShareAPIError?
    @Published private(set) var lastFetchedAt: Date?
    @Published private(set) var isRefreshing = false
    /// Whether the Keychain holds a username and password.
    @Published private(set) var isConfigured = false

    /// The page is on screen: ask for the day's readings so its graph fills,
    /// instead of only the newest pair.
    var pageVisible = false {
        didSet {
            guard pageVisible != oldValue, pageVisible else { return }
            refresh(force: true)
        }
    }

    /// Whether the closed island may show the reading now. The loop stops
    /// when the section is off, so freshness alone is enough here.
    var showsActivity: Bool {
        reading != nil && isFresh
    }

    private var client: ShareAPIClient?
    private var credentials: (username: String, password: String)?
    private var credentialSignature: String?
    private var loop: Task<Void, Never>?
    private var expiryWork: DispatchWorkItem?
    private var retryDelay: TimeInterval = 0
    private var authFailed = false
    private var fetchInFlight = false
    private var generation = 0
    private var wakeObserver: NSObjectProtocol?

    private init() {
        loadCache()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshFreshness()
            self?.refresh(force: true)
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && AppFeature.notchGlucose.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchGlucoseEnabled)
            && NotchSupport.modules(in: defaults).contains(.glucose)
    }

    /// Read the preferences and the Keychain, then make sure one loop is
    /// running. Called whenever the island's preferences change.
    func syncWithPreferences() {
        guard Self.isEnabled() else {
            stop()
            return
        }
        guard let username = GlucoseKeychain.string(.username),
              let password = GlucoseKeychain.string(.password),
              !username.isEmpty, !password.isEmpty else {
            isConfigured = false
            stop()
            return
        }
        isConfigured = true
        let region = GlucoseRegion.stored(UserDefaults.standard.string(forKey: DefaultsKey.notchGlucoseRegion))
        let signature = "\(username)\u{0}\(password.hashValue)\u{0}\(region.rawValue)"
        if signature != credentialSignature {
            loop?.cancel(); loop = nil
            client = ShareAPIClient(region: region)
            credentials = (username, password)
            credentialSignature = signature
            authFailed = false
            retryDelay = 0
        }
        startLoop()
        refresh()
    }

    /// A person asked again from the page: forget an earlier sign-in failure
    /// once and let the next check try. Credentials are unchanged.
    func retryNow() {
        authFailed = false
        retryDelay = 0
        syncWithPreferences()
        refresh(force: true)
    }

    /// A saved or cleared credential is a fresh start: forget the failure so
    /// the next check can sign in again.
    func credentialsChanged() {
        authFailed = false
        retryDelay = 0
        credentialSignature = nil
        syncWithPreferences()
    }

    /// A test from Settings: the entered credentials, not the saved ones.
    /// A successful test saves the same values and restarts the service.
    func testConnection(username: String, password: String,
                        region: GlucoseRegion) async -> Result<[GlucoseReading], ShareAPIError> {
        do {
            let readings = try await ShareAPIClient.test(username: username, password: password, region: region)
            return .success(readings)
        } catch let error as ShareAPIError {
            return .failure(error)
        } catch {
            return .failure(.network)
        }
    }

    func refresh(force: Bool = false) {
        guard !authFailed, client != nil else { return }
        // Preference changes can sync the island many times in a row; one
        // check every twenty seconds is plenty for a five-minute sensor.
        if !force, let lastFetchedAt, Date().timeIntervalSince(lastFetchedAt) < 20 { return }
        let token = generation
        Task { [weak self] in
            await self?.fetchOnce(generation: token)
        }
    }

    func stop() {
        generation &+= 1
        loop?.cancel(); loop = nil
        expiryWork?.cancel(); expiryWork = nil
        client = nil
        credentials = nil
        credentialSignature = nil
        isConfigured = false
        authFailed = false
        retryDelay = 0
        isRefreshing = false
        fetchInFlight = false
        lastError = nil
        if isFresh { isFresh = false }
    }

    // MARK: Fetching

    private func startLoop() {
        guard loop == nil else { return }
        generation &+= 1
        let token = generation
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetchOnce(generation: token)
                guard await MainActor.run(body: { !self.shouldStopLoop(generation: token) }) else { return }
                let delay = await MainActor.run { self.delayBeforeNextPoll() }
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
        }
    }

    private func shouldStopLoop(generation: Int) -> Bool {
        authFailed || self.generation != generation
    }

    private func delayBeforeNextPoll() -> TimeInterval {
        if retryDelay > 0 { return retryDelay }
        return 60
    }

    private func fetchOnce(generation: Int) async {
        let acquired = await MainActor.run { () -> Bool in
            guard generation == self.generation, !self.fetchInFlight else { return false }
            self.fetchInFlight = true
            self.isRefreshing = true
            return true
        }
        guard acquired else { return }
        guard let client, let credentials else {
            await MainActor.run {
                self.fetchInFlight = false
                self.isRefreshing = false
            }
            return
        }
        let result: Result<[GlucoseReading], ShareAPIError>
        do {
            if !client.isSignedIn {
                try await client.signIn(username: credentials.username, password: credentials.password)
            }
            let readings = try await client.fetchReadings(maxCount: pageVisible ? GlucoseSupport.maximumReadings : 2)
            result = .success(readings)
        } catch let error as ShareAPIError {
            result = .failure(error)
        } catch {
            result = .failure(.network)
        }
        await MainActor.run {
            // A stop or a new set of preferences makes this answer stale; the
            // newer fetch owns the flag now.
            guard generation == self.generation else { return }
            self.fetchInFlight = false
            self.isRefreshing = false
            switch result {
            case .success(let readings): self.apply(readings, generation: generation)
            case .failure(let error): self.apply(error, generation: generation)
            }
        }
    }

    private func apply(_ readings: [GlucoseReading], generation: Int) {
        guard generation == self.generation else { return }
        let latest = GlucoseSupport.latest(from: readings)
        if let latest {
            var shown = latest
            // When a source omits the direction, the last two readings still
            // say which way the value moved.
            if shown.trend == nil {
                let pool = GlucoseSupport.merged(history: history, adding: readings)
                shown.trend = GlucoseSupport.computedTrend(from: pool)
            }
            reading = shown
            history = GlucoseSupport.merged(history: history, adding: readings)
            saveCache()
        }
        lastError = readings.isEmpty ? .noReadings : nil
        lastFetchedAt = Date()
        retryDelay = 0
        authFailed = false
        refreshFreshness()
    }

    private func apply(_ error: ShareAPIError, generation: Int) {
        guard generation == self.generation else { return }
        lastError = error
        lastFetchedAt = Date()
        switch error {
        case .invalidCredentials, .tooManyAttempts:
            // Repeated sign-ins can lock the account; wait for the person to
            // change something rather than retrying every minute.
            authFailed = true
            loop?.cancel(); loop = nil
            retryDelay = 0
        case .network:
            retryDelay = min(300, retryDelay == 0 ? 30 : retryDelay * 2)
        case .sessionExpired, .malformedResponse, .noReadings, .server:
            retryDelay = min(300, retryDelay == 0 ? 60 : retryDelay * 2)
        }
        refreshFreshness()
    }

    // MARK: Freshness

    private func refreshFreshness() {
        // A stopped service has no reader to confirm a reading; never let a
        // wake or an old timer bring one back on its own.
        guard client != nil else {
            if isFresh { isFresh = false }
            return
        }
        let fresh = reading.map { GlucoseSupport.isFresh($0) } ?? false
        if fresh != isFresh { isFresh = fresh }
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiryWork?.cancel()
        expiryWork = nil
        guard isFresh, let reading else { return }
        let delay = max(1, GlucoseSupport.freshUntil(reading).timeIntervalSinceNow)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.reading == reading else { return }
            self.refreshFreshness()
        }
        expiryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Cache

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.notchGlucoseCachedReading),
              let cached = try? JSONDecoder().decode(GlucoseReading.self, from: data) else { return }
        reading = cached
        // A cached value must not show before the island and its section are
        // known to be on; the first sync decides that and the first fetch
        // confirms it.
        isFresh = GlucoseSupport.isFresh(cached) && Self.isEnabled()
        scheduleExpiry()
    }

    private func saveCache() {
        guard let reading, let data = try? JSONEncoder().encode(reading) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.notchGlucoseCachedReading)
    }
}
