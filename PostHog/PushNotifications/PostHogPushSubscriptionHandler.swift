import Foundation

/// Sends push notification device tokens to PostHog and retries on failure.
///
/// A single latest-wins record `{deviceToken, appId}` is persisted before the first attempt so a
/// failed or offline send can be retried later (on `flush()` via `retryIfNeeded()`, or on the next
/// launch). The `distinct_id` is read fresh at send time, never persisted. On success the record is
/// kept and stamped with `deliveredForDistinctId`; when the distinct id later changes the token is
/// re-sent so it follows the identified user (see the shared plan, decision 5).
final class PostHogPushSubscriptionHandler {
    private enum Key {
        static let deviceToken = "deviceToken"
        static let appId = "appId"
        static let deliveredForDistinctId = "deliveredForDistinctId"
    }

    private struct PendingRecord {
        let deviceToken: String
        let appId: String
        let deliveredForDistinctId: String?
    }

    private struct CachedIdentityToken {
        let token: String
        let distinctId: String
        let appId: String
    }

    private static let firstRetryDelay: TimeInterval = 5
    private static let maxRetryDelay: TimeInterval = 30

    /// Watchdog window for `pushIdentityProvider`: if the host never calls completion within this, fall
    /// back to a token-less send so a misbehaving provider can't wedge sending for the whole process.
    /// A slow legitimate mint on a bad network is cut off and retried token-less (the 401 refresh
    /// re-mints). Test seam: shrunk in tests so the fallback fires quickly. Keep in parity with Android.
    var identityTokenMintTimeout: TimeInterval = 10

    private let api: PostHogApi
    private let storage: PostHogStorage
    private let config: PostHogConfig
    private let distinctIdProvider: () -> String
    private let isConnectedProvider: () -> Bool
    /// Gates every network attempt (send, flush retry, identity-change resend): `false` while the
    /// SDK is disabled or opted out. The record is kept so an opt-in can resume later.
    private let isAllowedProvider: () -> Bool

    /// Guards `retryCount`, `pausedUntil`, `isSending`, `pendingResend`, `halted`,
    /// `cachedIdentityToken`, and `didAuthRetry`.
    private let stateLock = NSLock()
    private var retryCount = 0
    private var pausedUntil: Date?
    private var isSending = false
    /// A send/resend was requested while one was already in flight: re-attempt with the latest record
    /// once it completes so an identity change (or newer token) mid-send isn't dropped until flush().
    private var pendingResend = false
    /// Set after a non-retryable failure or once retries are exhausted: no more attempts this session,
    /// but the record is kept for one retry on the next launch.
    private var halted = false
    /// Last token minted by `config.pushIdentityProvider` for a `(distinctId, appId)` pair, reused by
    /// retries and reset() to avoid extra provider roundtrips; cleared on a 401 re-mint and opt-out. In memory
    /// only — unlike the persisted record, a short-lived credential must not outlive the process.
    private var cachedIdentityToken: CachedIdentityToken?
    /// One fresh-token retry per send-cycle after a 401; reset with the retry state.
    private var didAuthRetry = false

    /// Serializes storage-record read-modify-writes (persist, deliver-stamp, unregister-clear, reset
    /// re-register) so a concurrent `send()`, `reset()`, or send completion can't interleave and lose a
    /// token. `PostHogStorage` does no locking of its own.
    private let recordLock = NSLock()

    private var contextChangedToken: RegistrationToken?

    init(
        _ api: PostHogApi,
        _ storage: PostHogStorage,
        _ config: PostHogConfig,
        distinctIdProvider: @escaping () -> String,
        isConnectedProvider: @escaping () -> Bool,
        isAllowedProvider: @escaping () -> Bool,
        onEventContextChanged: PostHogMulticastCallback<[String: Any]>
    ) {
        self.api = api
        self.storage = storage
        self.config = config
        self.distinctIdProvider = distinctIdProvider
        self.isConnectedProvider = isConnectedProvider
        self.isAllowedProvider = isAllowedProvider

        contextChangedToken = onEventContextChanged.subscribe { [weak self] context in
            guard let distinctId = context["distinct_id"] as? String, !distinctId.isEmpty else { return }
            self?.resendIfDistinctIdChanged(currentDistinctId: distinctId)
        }
    }

    /// Registers a device token. Persists it (latest-wins) and attempts to send immediately.
    /// Re-registering the token already delivered for the current distinct id is a no-op, so APNs
    /// re-delivering the same token on every launch doesn't re-POST it.
    func send(deviceToken: String, appId providedAppId: String? = nil) {
        if deviceToken.isEmpty {
            hedgeLog("Push subscription not sent: device token is empty.")
            return
        }

        let appId = providedAppId ?? Bundle.main.bundleIdentifier ?? ""
        if appId.isEmpty {
            hedgeLog("Push subscription not sent: no app id (bundle identifier is nil).")
            return
        }

        let currentDistinctId = distinctIdProvider()
        let alreadyDelivered = recordLock.withLock { () -> Bool in
            if let record = loadRecordLocked(),
               record.deviceToken == deviceToken,
               record.appId == appId,
               !currentDistinctId.isEmpty,
               record.deliveredForDistinctId == currentDistinctId
            {
                return true
            }
            writeRecord(deviceToken: deviceToken, appId: appId)
            return false
        }
        if alreadyDelivered {
            hedgeLog("Push subscription skipped: token already delivered for the current distinct id.")
            return
        }

        // A new token supersedes any previous failure — reset the whole retry state.
        resetRetryState()

        attemptIfAllowed(deviceToken: deviceToken, appId: appId)
    }

    /// Retries a persisted, not-yet-delivered subscription if the backoff window has elapsed.
    /// Called from `PostHogSDK.flush()`.
    func retryIfNeeded() {
        guard let record = loadRecord() else { return }

        let distinctId = distinctIdProvider()
        guard !distinctId.isEmpty else { return }

        // Already delivered to the current user — nothing to do.
        if record.deliveredForDistinctId == distinctId {
            return
        }

        // Delivered to a different user (identity changed while the app was closed) — treat as fresh.
        if let delivered = record.deliveredForDistinctId, delivered != distinctId {
            resetRetryState()
        }

        attemptIfAllowed(deviceToken: record.deviceToken, appId: record.appId)
    }

    /// Best-effort unregister: a single `DELETE /api/push_subscriptions` for `distinctId`. Unlike
    /// `send`, there is no retry, backoff, or persistence — a failure is logged and dropped (the
    /// backend also unsets a dead token on the next send, and the durable path is the re-register).
    func unregister(distinctId: String, deviceToken: String, appId: String) {
        guard isAllowedProvider() else {
            hedgeLog("Push unregister skipped: SDK is disabled or opted out.")
            return
        }
        guard !distinctId.isEmpty, !deviceToken.isEmpty, !appId.isEmpty else {
            hedgeLog("Push unregister skipped: missing distinct id, token, or app id.")
            return
        }
        // Same one-verification-state as registration: the DELETE resolves a token for the distinct id
        // it carries (the old identity on the reset() path). Still best-effort — no 401 refresh here.
        resolveIdentityToken(distinctId: distinctId, appId: appId) { [weak self] identityToken in
            guard let self, isAllowedProvider() else { return }
            api.deletePushSubscription(
                distinctId: distinctId, deviceToken: deviceToken, appId: appId, identityToken: identityToken
            ) { info in
                if let statusCode = info.statusCode, 200 ... 299 ~= statusCode {
                    hedgeLog("Push subscription unregistered successfully.")
                } else {
                    hedgeLog("Push unregister failed (status \(info.statusCode.map(String.init) ?? "none")); ignoring (best-effort).")
                }
            }
        }
    }

    /// Snapshot of the stored token/appId, read *before* `reset()` clears storage so the old
    /// identity's subscription can be DELETEd and then re-registered under the new anonymous id.
    func recordForReset() -> (deviceToken: String, appId: String)? {
        guard let record = loadRecord() else { return nil }
        return (record.deviceToken, record.appId)
    }

    /// Re-registers a token snapshotted by `recordForReset()` after `reset()` cleared storage — used
    /// only from `reset()`. Skips if a newer token was persisted in the meantime (an APNs delivery
    /// racing reset), so the stale snapshot can't overwrite it.
    func reregisterAfterReset(deviceToken: String, appId: String) {
        let superseded = recordLock.withLock { () -> Bool in
            if loadRecordLocked() != nil {
                return true
            }
            writeRecord(deviceToken: deviceToken, appId: appId)
            return false
        }
        if superseded {
            hedgeLog("Push re-register after reset skipped: a newer token superseded the snapshot.")
            return
        }
        resetRetryState()
        attemptIfAllowed(deviceToken: deviceToken, appId: appId)
    }

    /// Public-API unregister: DELETE for the current distinct id, then forget the local record so a
    /// later launch won't re-send it. The load-then-clear is atomic so a concurrent `send()` can't slip
    /// a new token in between and have it silently dropped.
    func unregisterCurrentToken() {
        let record: PendingRecord? = recordLock.withLock {
            guard let record = loadRecordLocked() else { return nil }
            storage.remove(key: .pushSubscription)
            return record
        }
        guard let record else {
            hedgeLog("Push unregister skipped: no registered token.")
            return
        }
        unregister(distinctId: distinctIdProvider(), deviceToken: record.deviceToken, appId: record.appId)
    }

    /// Opt-out drops the cached identity credential so a later opt-in re-mints it.
    func onOptOut() {
        stateLock.withLock { cachedIdentityToken = nil }
    }

    // MARK: - Private

    private func resendIfDistinctIdChanged(currentDistinctId: String) {
        guard let record = loadRecord(),
              let delivered = record.deliveredForDistinctId,
              delivered != currentDistinctId
        else {
            return
        }

        resetRetryState()

        attemptIfAllowed(deviceToken: record.deviceToken, appId: record.appId)
    }

    private func resetRetryState() {
        stateLock.withLock {
            retryCount = 0
            pausedUntil = nil
            halted = false
            didAuthRetry = false
        }
    }

    private func attemptIfAllowed(deviceToken: String, appId: String) {
        if !isAllowedProvider() {
            hedgeLog("Push subscription not sent: SDK is disabled or opted out.")
            return
        }

        let distinctId = distinctIdProvider()
        if distinctId.isEmpty {
            hedgeLog("Push subscription deferred: no distinct id yet.")
            return
        }

        // Offline: defer without burning a retry attempt.
        if !isConnectedProvider() {
            hedgeLog("Push subscription deferred: no network connection.")
            return
        }

        let shouldSend = stateLock.withLock { () -> Bool in
            if halted {
                return false
            }
            if isSending {
                // Fold this request into the in-flight send; replayed on completion (see pendingResend).
                pendingResend = true
                return false
            }
            if let until = pausedUntil, until > Date() {
                return false
            }
            isSending = true
            return true
        }
        guard shouldSend else { return }

        // `isSending` stays claimed across the mint, so a registration arriving mid-mint folds into
        // `pendingResend` exactly like one arriving mid-request.
        resolveIdentityToken(distinctId: distinctId, appId: appId) { [weak self] identityToken in
            guard let self else { return }
            // Opt-out may land during a slow mint; re-check before sending.
            guard isAllowedProvider() else {
                stateLock.withLock { self.isSending = false }
                return
            }
            api.pushSubscription(
                distinctId: distinctId, deviceToken: deviceToken, appId: appId, identityToken: identityToken
            ) { [weak self] info in
                self?.handleResult(info, deviceToken: deviceToken, appId: appId, distinctId: distinctId)
            }
        }
    }

    /// Resolves the identity token for `distinctId`/`appId`, preferring an exact cache hit. The
    /// completion may run synchronously or from whatever thread the provider completes on; extra
    /// provider completions are ignored (an uncalled one strands the request — see the config doc).
    private func resolveIdentityToken(distinctId: String, appId: String, completion: @escaping (String?) -> Void) {
        guard let provider = config.pushIdentityProvider else {
            hedgeLog("No identity token attached to push request (no pushIdentityProvider).")
            return completion(nil)
        }

        let cached = stateLock.withLock { () -> String? in
            guard let cache = cachedIdentityToken, cache.distinctId == distinctId, cache.appId == appId else {
                return nil
            }
            return cache.token
        }
        if let cached {
            hedgeLog("Attaching cached identity token to push request.")
            return completion(cached)
        }

        var completed = false
        // A provider that never calls its completion would hold isSending for the whole process and
        // wedge every later send. Bound the wait: if the mint doesn't land in time, fall back to a
        // token-less send. A late real completion is a no-op via `completed`.
        let timeout = identityTokenMintTimeout
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            let isFirst = self.stateLock.withLock { () -> Bool in
                if completed {
                    return false
                }
                completed = true
                return true
            }
            guard isFirst else { return }
            hedgeLog("pushIdentityProvider did not complete within \(timeout)s; sending without identity token.")
            completion(nil)
        }
        provider(distinctId, appId) { [weak self] token in
            guard let self else { return }
            // A mint can complete after opt-out cleared the cache; caching it would resurrect a
            // stale credential on a later opt-in. The 401 refresh covers the residual race window.
            let allowed = isAllowedProvider()
            let isFirst = self.stateLock.withLock { () -> Bool in
                if completed {
                    return false
                }
                completed = true
                if let token, allowed {
                    self.cachedIdentityToken = CachedIdentityToken(token: token, distinctId: distinctId, appId: appId)
                }
                return true
            }
            guard isFirst else { return }
            hedgeLog(token != nil
                ? "Attaching freshly minted identity token to push request."
                : "No identity token attached to push request (provider completed nil).")
            completion(token)
        }
    }

    private func handleResult(_ info: PostHogUploadInfo, deviceToken: String, appId: String, distinctId: String) {
        let hadPendingResend = stateLock.withLock { () -> Bool in
            isSending = false
            let pending = pendingResend
            pendingResend = false
            return pending
        }

        if let statusCode = info.statusCode, 200 ... 299 ~= statusCode {
            markDelivered(deviceToken: deviceToken, appId: appId, distinctId: distinctId)
            resetRetryState()
            hedgeLog("Push subscription sent successfully.")
        } else {
            handleFailure(info, deviceToken: deviceToken, appId: appId)
        }

        // A newer registration or identity change arrived while this send was in flight. Service it with
        // fresh retry state so the latest token isn't stranded behind this send's backoff or halt.
        if hadPendingResend, let record = loadRecord() {
            resetRetryState()
            attemptIfAllowed(deviceToken: record.deviceToken, appId: record.appId)
        }
    }

    /// Applies backoff/halt state for a non-2xx result. Split from `handleResult` so a coalesced resend
    /// is serviced afterward regardless of which failure branch this took.
    private func handleFailure(_ info: PostHogUploadInfo, deviceToken: String, appId: String) {
        // A 401 means identity verification failed. With a provider, allow one fresh-token retry per
        // send-cycle; a second 401 falls through to the terminal branch below.
        if info.statusCode == 401, config.pushIdentityProvider != nil {
            let shouldRetryWithFreshToken = stateLock.withLock { () -> Bool in
                if didAuthRetry {
                    return false
                }
                didAuthRetry = true
                cachedIdentityToken = nil
                return true
            }
            if shouldRetryWithFreshToken {
                hedgeLog("Push subscription rejected (401). Retrying once with a fresh identity token.")
                attemptIfAllowed(deviceToken: deviceToken, appId: appId)
                return
            }
        }

        // Retryable: transport error (no status), 429, or 5xx. Everything else (400/401) is terminal.
        let retryable: Bool
        if let statusCode = info.statusCode {
            retryable = statusCode == 429 || (500 ... 599 ~= statusCode)
        } else {
            retryable = true
        }

        guard retryable else {
            stateLock.withLock { halted = true }
            if info.statusCode == 401, config.pushIdentityProvider == nil {
                hedgeLog(
                    "Push subscription rejected (401): identity verification may be required — set config.pushIdentityProvider. Keeping record for next launch."
                )
            } else {
                hedgeLog("Push subscription rejected (status \(info.statusCode.map(String.init) ?? "none")). Keeping record for next launch.")
            }
            return
        }

        let attempt = stateLock.withLock { () -> Int in
            retryCount += 1
            return retryCount
        }

        if attempt > config.maxRetries {
            stateLock.withLock { halted = true }
            hedgeLog("Push subscription: max retries (\(config.maxRetries)) exceeded. Keeping record for next launch.")
            return
        }

        let delay = info.retryAfter ?? retryDelay(forAttempt: attempt)
        stateLock.withLock { pausedUntil = Date().addingTimeInterval(delay) }
        hedgeLog("Push subscription failed (attempt \(attempt)/\(config.maxRetries)). Retrying in \(delay)s.")
    }

    /// Keep the delivered record so the token can be re-sent when the distinct id changes, but only if
    /// a newer token hasn't superseded it while this request was in flight.
    private func markDelivered(deviceToken: String, appId: String, distinctId: String) {
        recordLock.withLock {
            guard let record = loadRecordLocked(),
                  record.deviceToken == deviceToken,
                  record.appId == appId
            else {
                return
            }

            writeRecord(deviceToken: deviceToken, appId: appId, deliveredForDistinctId: distinctId)
        }
    }

    /// Persists the record. Caller must hold `recordLock`. Pass `deliveredForDistinctId` to stamp it
    /// delivered so an identity change can trigger a resend (decision 5).
    private func writeRecord(deviceToken: String, appId: String, deliveredForDistinctId: String? = nil) {
        var contents = [
            Key.deviceToken: deviceToken,
            Key.appId: appId,
        ]
        if let deliveredForDistinctId {
            contents[Key.deliveredForDistinctId] = deliveredForDistinctId
        }
        storage.setDictionary(forKey: .pushSubscription, contents: contents)
    }

    /// Standalone record read; acquires `recordLock`. Default-safe entry point — call this unless you
    /// already hold `recordLock`, in which case use `loadRecordLocked()`.
    private func loadRecord() -> PendingRecord? {
        recordLock.withLock { loadRecordLocked() }
    }

    /// Reads the record without locking; the caller MUST already hold `recordLock`. Exists only so a
    /// read-modify-write can happen atomically inside one `recordLock` critical section.
    private func loadRecordLocked() -> PendingRecord? {
        guard let data = storage.getDictionary(forKey: .pushSubscription) as? [String: String],
              let deviceToken = data[Key.deviceToken],
              let appId = data[Key.appId]
        else {
            return nil
        }
        return PendingRecord(deviceToken: deviceToken, appId: appId, deliveredForDistinctId: data[Key.deliveredForDistinctId])
    }

    /// Exponential backoff: `min(5 * 2^(attempt-1), 30)` → 5, 10, 20, 30, 30, …
    func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        min(Self.firstRetryDelay * pow(2, Double(attempt - 1)), Self.maxRetryDelay)
    }
}

#if TESTING
    extension PostHogPushSubscriptionHandler {
        var retryCountForTesting: Int {
            stateLock.withLock { retryCount }
        }

        var isHaltedForTesting: Bool {
            stateLock.withLock { halted }
        }

        /// Clears the backoff window (but not the halted flag) so a retry can be driven without waiting.
        func clearBackoffForTesting() {
            stateLock.withLock { pausedUntil = nil }
        }
    }
#endif
