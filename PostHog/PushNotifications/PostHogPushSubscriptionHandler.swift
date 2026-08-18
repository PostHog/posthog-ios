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
        static let distinctId = "distinctId"
    }

    private struct PendingRecord {
        let deviceToken: String
        let appId: String
        let deliveredForDistinctId: String?
    }

    /// A durable "delete this subscription" intent for the identity it names, persisted so an offline or
    /// failed unregister (logout/reset) is retried on `flush()`/next launch instead of silently leaving
    /// the device associated with the logged-out user. Separate key from `PendingRecord` so it coexists
    /// with a fresh registration the reset path writes under the new anonymous id.
    ///
    /// Single-slot, last-write-wins: only one identity's unregister can be pending at a time. Two
    /// overlapping logouts (rapid double-reset) drop the older intent — acceptable given one device token
    /// and how rare that is; a per-identity queue would be the fix if it ever matters.
    private struct PendingUnregister: Equatable {
        let distinctId: String
        let deviceToken: String
        let appId: String
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
    /// re-mints). Test seam: shrunk in tests so the fallback fires quickly.
    var identityTokenMintTimeout: TimeInterval = 10

    private let api: PostHogApi
    private let storage: PostHogStorage
    private let config: PostHogConfig
    private let distinctIdProvider: () -> String
    private let isConnectedProvider: () -> Bool
    /// Gates every network attempt (send, flush retry, identity-change resend): `false` while the
    /// SDK is disabled or opted out. The record is kept so an opt-in can resume later.
    private let isAllowedProvider: () -> Bool

    /// Gates cleanup (the unregister DELETE): `false` only while the SDK is disabled. Unlike
    /// `isAllowedProvider` this ignores opt-out, because a DELETE removes data rather than collecting
    /// it, so opt-out must not strand it (posthog-ios#746).
    private let isEnabledProvider: () -> Bool
    private let pushAppIdsProvider: () -> [String]?

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

    /// Runs `config.pushIdentityProvider` off the caller's thread (which is the host's main thread on
    /// the first registration, via `didRegisterForRemoteNotificationsWithDeviceToken:`). A provider
    /// that blocks can only stall this serial queue — and the mint watchdog still fires on a separate
    /// queue — never the host's UI.
    private let mintQueue = DispatchQueue(label: "com.posthog.push.identity-mint")

    /// Runs the disk-backed `resendIfDistinctIdChanged` re-check off the caller's thread. Only
    /// reached when the synchronous in-memory check in the `onEventContextChanged` subscriber sees
    /// a genuine mismatch (or an unhydrated cache).
    private let workQueue = DispatchQueue(label: "com.posthog.push.subscription-handler")

    /// At most one push HTTP request (POST or DELETE) in flight at a time, in dispatch order, so a
    /// straggler can't land at the server after a newer request and undo it (e.g. a logout DELETE
    /// erasing the subscription a re-login just delivered). Identity-token mints happen before
    /// enqueueing, so a slow provider never blocks this queue.
    private let httpQueue = DispatchQueue(label: "com.posthog.push.http")

    /// In-memory mirror of the persisted record's `deliveredForDistinctId`, guarded by `recordLock`.
    /// Lets the `onEventContextChanged` subscriber decide "nothing to resend" synchronously with no
    /// disk I/O on the caller's (often main) thread. `nil` = not yet hydrated from disk;
    /// `.some(x)` = hydrated, where `x` is nil when there is no delivered record.
    private var cachedDeliveredDistinctId: String??

    private var contextChangedToken: RegistrationToken?

    init(
        _ api: PostHogApi,
        _ storage: PostHogStorage,
        _ config: PostHogConfig,
        distinctIdProvider: @escaping () -> String,
        isConnectedProvider: @escaping () -> Bool,
        isAllowedProvider: @escaping () -> Bool,
        isEnabledProvider: @escaping () -> Bool,
        // The app_ids the project accepts registrations for, or nil when no server has said.
        // Nil means attempt: a server older than the key must not stop a device registering.
        pushAppIdsProvider: @escaping () -> [String]? = { nil },
        onEventContextChanged: PostHogMulticastCallback<[String: Any]>
    ) {
        self.api = api
        self.storage = storage
        self.config = config
        self.distinctIdProvider = distinctIdProvider
        self.isConnectedProvider = isConnectedProvider
        self.isAllowedProvider = isAllowedProvider
        self.isEnabledProvider = isEnabledProvider
        self.pushAppIdsProvider = pushAppIdsProvider

        contextChangedToken = onEventContextChanged.subscribe { [weak self] context in
            guard let self, let distinctId = context["distinct_id"] as? String, !distinctId.isEmpty else { return }
            // Synchronous in-memory check so the common no-change case costs no disk I/O on the
            // caller's thread, and so the decision uses the record state at notify time — an async
            // re-read would race reset()'s clear/re-register sequence. Only a genuine mismatch (or
            // an unhydrated cache right after launch) pays for the queue hop and full re-check.
            let cached = recordLock.withLock { self.cachedDeliveredDistinctId }
            if case let .some(delivered) = cached, delivered == nil || delivered == distinctId {
                return
            }
            workQueue.async { [weak self] in self?.resendIfDistinctIdChanged(currentDistinctId: distinctId) }
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
        enum ExistingMatch { case delivered, undeliveredSame, none }
        let match = recordLock.withLock { () -> ExistingMatch in
            if let record = loadRecordLocked(),
               record.deviceToken == deviceToken,
               record.appId == appId
            {
                if !currentDistinctId.isEmpty, record.deliveredForDistinctId == currentDistinctId {
                    return .delivered
                }
                if record.deliveredForDistinctId == nil {
                    writeRecord(deviceToken: deviceToken, appId: appId)
                    return .undeliveredSame
                }
            }
            writeRecord(deviceToken: deviceToken, appId: appId)
            return .none
        }
        if match == .delivered {
            hedgeLog("Push subscription skipped: token already delivered for the current distinct id.")
            return
        }

        // A new token/appId supersedes any previous failure — reset the whole retry state. An
        // identical re-register of an already-undelivered record does not: APNs re-delivering the
        // same token would otherwise spam register() and defeat the backoff (still attempted below
        // unless paused).
        if match != .undeliveredSame {
            resetRetryState()
        }

        attemptIfAllowed(deviceToken: deviceToken, appId: appId)
    }

    /// Retries a persisted, not-yet-delivered subscription if the backoff window has elapsed.
    /// Called from `PostHogSDK.flush()`.
    func retryIfNeeded() {
        // Drain any pending unregister first (offline logout, transport failure) — independent of the
        // send record, usually absent after a logout; the in-memory identity-token cache is empty here,
        // so the retry re-mints a fresh token and sidesteps the expired-token 401. If a same-identity
        // registration is queued (logged out then back in), drop the DELETE instead — an in-flight
        // DELETE completing after the POST would kill the subscription just delivered.
        let record = loadRecord()
        if let pending = loadPendingUnregister() {
            if let record, pending.distinctId == distinctIdProvider(), pending.appId == record.appId {
                clearPendingUnregister(matching: pending)
            } else {
                attemptUnregister(pending)
            }
        }

        guard let record else { return }

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

    /// Unregister: `DELETE /api/push_subscriptions` for `distinctId`. The intent is persisted first, so an
    /// offline or failed attempt is retried on `flush()`/next launch (see `PendingUnregister`) rather than
    /// dropped — otherwise a logout while offline, or with an expired identity token, would leave the
    /// device associated with the logged-out user on the backend. Cleared on a 2xx or a terminal 4xx.
    func unregister(distinctId: String, deviceToken: String, appId: String) {
        guard !distinctId.isEmpty, !deviceToken.isEmpty, !appId.isEmpty else {
            hedgeLog("Push unregister skipped: missing distinct id, token, or app id.")
            return
        }
        let pending = PendingUnregister(distinctId: distinctId, deviceToken: deviceToken, appId: appId)
        writePendingUnregister(pending)
        guard isEnabledProvider() else {
            hedgeLog("Push unregister deferred: SDK is disabled. Will retry on flush/next launch.")
            return
        }
        attemptUnregister(pending)
    }

    /// Attempts the persisted DELETE. Offline defers without clearing the intent (retried later). On a 401
    /// with a provider, re-mints a fresh identity token once and retries — the same-process logout path may
    /// hold an expired cached token (the provider mints a short TTL). `isRetry` caps that to one re-mint.
    private func attemptUnregister(_ pending: PendingUnregister, isRetry: Bool = false) {
        guard isEnabledProvider() else { return }
        guard isConnectedProvider() else {
            hedgeLog("Push unregister deferred: no network connection. Will retry on flush/next launch.")
            return
        }
        // Same one-verification-state as registration: the DELETE resolves a token for the distinct id it
        // carries (the old identity on the reset() path).
        resolveIdentityToken(distinctId: pending.distinctId, appId: pending.appId) { [weak self] identityToken in
            guard let self, isEnabledProvider() else { return }
            // A registration may have superseded this intent while the mint was in flight (re-login
            // during a slow mint) — re-apply the same supersede rule the retry drain uses, and bail if
            // the intent was already cleared/replaced by something else in the meantime.
            guard loadPendingUnregister() == pending else { return }
            if let record = loadRecord(), pending.distinctId == distinctIdProvider(), pending.appId == record.appId {
                clearPendingUnregister(matching: pending)
                return
            }
            performSerialized { done in
                self.api.deletePushSubscription(
                    distinctId: pending.distinctId, deviceToken: pending.deviceToken, appId: pending.appId,
                    identityToken: identityToken, completion: done
                )
            } completion: { [weak self] info in
                self?.handleUnregisterResult(info, pending: pending, isRetry: isRetry)
            }
        }
    }

    private func handleUnregisterResult(_ info: PostHogUploadInfo, pending: PendingUnregister, isRetry: Bool) {
        if let statusCode = info.statusCode, 200 ... 299 ~= statusCode {
            clearPendingUnregister(matching: pending)
            hedgeLog("Push subscription unregistered successfully.")
            return
        }

        // 401: identity verification failed. Re-mint once and retry, mirroring the send-path 401 refresh.
        if info.statusCode == 401, config.pushIdentityProvider != nil, !isRetry {
            stateLock.withLock { cachedIdentityToken = nil }
            hedgeLog("Push unregister rejected (401). Retrying once with a fresh identity token.")
            attemptUnregister(pending, isRetry: true)
            return
        }

        // Retryable (transport error, 429, 5xx): keep the intent for flush/next launch.
        if isRetryable(info) {
            hedgeLog("Push unregister failed (status \(statusString(info))); will retry on flush/next launch.")
            return
        }

        // Terminal (post-retry 401, 404 already gone, other 4xx): drop the intent, best-effort ceiling.
        clearPendingUnregister(matching: pending)
        hedgeLog("Push unregister failed (status \(statusString(info))); dropping (best-effort).")
    }

    /// Snapshot of the stored token/appId, read *before* `reset()` clears the rest of storage so the
    /// old identity's subscription can be DELETEd and then re-registered under the new anonymous id.
    /// Clears the record under `recordLock` here (rather than leaving it to `PostHogStorage.reset()`)
    /// so a concurrent `send()` can't write a fresh record in the gap between this snapshot and the
    /// unlocked storage clear only to have it erased.
    func recordForReset() -> (deviceToken: String, appId: String)? {
        recordLock.withLock {
            guard let record = loadRecordLocked() else { return nil }
            storage.remove(key: .pushSubscription)
            cachedDeliveredDistinctId = .some(nil)
            return (record.deviceToken, record.appId)
        }
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
            cachedDeliveredDistinctId = .some(nil)
            return record
        }
        guard let record else {
            hedgeLog("Push unregister skipped: no registered token.")
            return
        }
        unregister(distinctId: distinctIdProvider(), deviceToken: record.deviceToken, appId: record.appId)
    }

    /// Opt-out drops the cached identity credential so a later opt-in re-mints it, and clears the
    /// per-cycle 401 retry flag so a consumed retry doesn't stay stuck and suppress the next one.
    func onOptOut() {
        stateLock.withLock {
            cachedIdentityToken = nil
            didAuthRetry = false
        }
    }

    // MARK: - Private

    #if TESTING
        /// Observes the thread `resendIfDistinctIdChanged` actually runs on, so tests can assert the
        /// `onEventContextChanged` subscriber's disk read never happens on the caller's thread.
        var onResendForTesting: ((Bool) -> Void)?
    #endif

    private func resendIfDistinctIdChanged(currentDistinctId: String) {
        #if TESTING
            onResendForTesting?(Thread.isMainThread)
        #endif
        guard let record = loadRecord(),
              let delivered = record.deliveredForDistinctId,
              delivered != currentDistinctId
        else {
            return
        }

        resetRetryState()

        attemptIfAllowed(deviceToken: record.deviceToken, appId: record.appId)
    }

    /// Called when remote config resolves. `newlyRegisterable` are the app_ids that were not
    /// registerable the last time we looked and are now.
    ///
    /// A device that registered while its project had no push integration was answered 200 and had its
    /// token discarded, but still recorded the send as delivered and stopped asking. Clearing that
    /// marker for an app_id that just became registerable is the only thing that reaches it.
    func onPushAppIdsChanged(_ newlyRegisterable: Set<String>) {
        workQueue.async { [weak self] in
            guard let self else { return }

            let record = recordLock.withLock { self.loadRecordLocked() }
            guard let record, newlyRegisterable.contains(record.appId) else {
                // Either nothing changed for this device, or the app_id was already registerable and
                // the existing delivered marker is honest. Re-sending here would put the request back
                // on every launch, which is what the marker exists to prevent.
                return
            }

            if record.deliveredForDistinctId != nil {
                recordLock.withLock {
                    self.writeRecord(deviceToken: record.deviceToken, appId: record.appId)
                }
            }

            resetRetryState()
            hedgeLog("Push app_id \(record.appId) became registerable; re-registering.")
            attemptIfAllowed(deviceToken: record.deviceToken, appId: record.appId)
        }
    }

    private func resetRetryState() {
        stateLock.withLock {
            retryCount = 0
            pausedUntil = nil
            halted = false
            didAuthRetry = false
        }
    }

    /// Nil means no server has published the list, so we cannot rule the app_id out and must try.
    private func isRegisterable(_ appId: String) -> Bool {
        guard let appIds = pushAppIdsProvider() else { return true }
        return appIds.contains(appId)
    }

    private func attemptIfAllowed(deviceToken: String, appId: String) {
        if !isAllowedProvider() {
            hedgeLog("Push subscription not sent: SDK is disabled or opted out.")
            return
        }

        if !isRegisterable(appId) {
            // The project publishes no push integration for this app_id, so the server would accept
            // the request and throw the token away. The record stays on disk, so onPushAppIdsChanged
            // has a token to register once the project does configure push.
            hedgeLog("Push subscription skipped: app_id \(appId) is not configured for this project.")
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
                // Also drop any registration that folded into `pendingResend` during the mint. We're
                // opted out, so it must not fire, and leaving it set would make the next send's
                // `handleResult` service a stale resend. A later opt-in re-registers normally.
                stateLock.withLock {
                    self.isSending = false
                    self.pendingResend = false
                }
                return
            }
            // The identity may have changed while the mint was in flight (identify/reset racing a
            // slow provider): sending under the stale distinctId would register the token to the
            // wrong person. Skip this send, but service any registration that folded into
            // `pendingResend` during the mint (e.g. reset's re-register) — dropping it would leave
            // the new identity unregistered until `retryIfNeeded` heals it on the next flush/launch.
            guard self.distinctIdProvider() == distinctId else {
                hedgeLog("Push subscription skipped: distinct id changed while minting the identity token.")
                let hadPendingResend = stateLock.withLock { () -> Bool in
                    self.isSending = false
                    let pending = self.pendingResend
                    self.pendingResend = false
                    return pending
                }
                if hadPendingResend {
                    servicePendingResend()
                }
                return
            }
            // Eligibility can also flip during the mint: remote config may resolve and drop this
            // app_id. Re-check so a config that arrived mid-mint isn't ignored, which would POST a
            // token the server discards and then record it as delivered, suppressing retries.
            guard isRegisterable(appId) else {
                hedgeLog("Push subscription skipped: app_id \(appId) is not configured for this project.")
                let hadPendingResend = stateLock.withLock { () -> Bool in
                    self.isSending = false
                    let pending = self.pendingResend
                    self.pendingResend = false
                    return pending
                }
                if hadPendingResend {
                    servicePendingResend()
                }
                return
            }
            performSerialized { done in
                self.api.pushSubscription(
                    distinctId: distinctId, deviceToken: deviceToken, appId: appId, identityToken: identityToken,
                    completion: done
                )
            } completion: { [weak self] info in
                self?.handleResult(info, deviceToken: deviceToken, appId: appId, distinctId: distinctId)
            }
        }
    }

    /// Runs `request` on `httpQueue`, blocking the queue until its completion fires so the next push
    /// request can't dispatch before this one finishes. The wait is a safety net over the request's
    /// own 10s timeout: a dropped completion must not wedge every future push request behind it.
    /// Result handlers re-enter via `httpQueue.async` (401 retries), which is safe — this block's
    /// wait has already ended by then.
    private func performSerialized(
        _ request: @escaping (@escaping (PostHogUploadInfo) -> Void) -> Void,
        completion: @escaping (PostHogUploadInfo) -> Void
    ) {
        httpQueue.async {
            let done = DispatchSemaphore(value: 0)
            let resultLock = NSLock()
            var result = PostHogUploadInfo(statusCode: nil, error: nil)
            request { info in
                resultLock.withLock { result = info }
                done.signal()
            }
            // On timeout the transport-error default is reported (retryable); a late real
            // completion only signals a semaphore nobody waits on anymore.
            _ = done.wait(timeout: .now() + 30)
            completion(resultLock.withLock { result })
        }
    }

    /// Resolves the identity token for `distinctId`/`appId`, preferring an exact cache hit. The
    /// completion may run synchronously or from whatever thread the provider completes on; extra
    /// provider completions are ignored (an uncalled one falls back to a token-less send after the
    /// watchdog timeout — see the config doc).
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
        // token-less send. A late real completion doesn't deliver (via `completed`) but still
        // caches its token so the next attempt skips the mint.
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
        // Hop off the caller's (often main) thread: a blocking provider stalls only `mintQueue`, and
        // the watchdog above still fires from `DispatchQueue.global()` to unwedge the send.
        mintQueue.async {
            provider(distinctId, appId) { [weak self] token in
                guard let self else { return }
                let isFirst = self.stateLock.withLock { () -> Bool in
                    // Cache regardless of who wins the race: a provider persistently slower than
                    // the watchdog would otherwise never populate the cache and re-mint on every
                    // future attempt. Guarded by the same lock onOptOut() uses to clear the cache,
                    // so a concurrent opt-out can't leave a stale token cached (isAllowedProvider()
                    // is already false here if opt-out won).
                    if let token, self.isAllowedProvider() {
                        self.cachedIdentityToken = CachedIdentityToken(token: token, distinctId: distinctId, appId: appId)
                    }
                    if completed {
                        return false
                    }
                    completed = true
                    return true
                }
                guard isFirst else { return }
                hedgeLog(token != nil
                    ? "Attaching freshly minted identity token to push request."
                    : "No identity token attached to push request (provider completed nil).")
                completion(token)
            }
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

        if hadPendingResend {
            servicePendingResend()
        }
    }

    /// Services a registration or identity change that folded into `pendingResend` while a send
    /// cycle was in flight, with fresh retry state so the latest token isn't stranded behind that
    /// cycle's backoff or halt. If a newer send already reclaimed `isSending` (e.g. the 401
    /// fresh-token retry `handleFailure` starts), folds back into it instead: resetting retry
    /// state here would clear that cycle's `didAuthRetry` cap out from under it.
    private func servicePendingResend() {
        let deferredToInFlight = stateLock.withLock { () -> Bool in
            if isSending {
                pendingResend = true
                return true
            }
            return false
        }
        if !deferredToInFlight, let record = loadRecord() {
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

        guard isRetryable(info) else {
            stateLock.withLock { halted = true }
            if info.statusCode == 401, config.pushIdentityProvider == nil {
                hedgeLog(
                    "Push subscription rejected (401): identity verification may be required — set config.pushIdentityProvider. Keeping record for next launch."
                )
            } else {
                hedgeLog("Push subscription rejected (status \(statusString(info))). Keeping record for next launch.")
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

            // A fresh registration delivered to this identity supersedes any queued logout-DELETE for
            // it (log out of A, then back into A): otherwise the next retryIfNeeded() drain would
            // unregister the subscription we just re-registered.
            clearPendingUnregisterLocked(
                matching: PendingUnregister(distinctId: distinctId, deviceToken: deviceToken, appId: appId)
            )
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
        cachedDeliveredDistinctId = .some(deliveredForDistinctId)
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
            cachedDeliveredDistinctId = .some(nil)
            return nil
        }
        let record = PendingRecord(deviceToken: deviceToken, appId: appId, deliveredForDistinctId: data[Key.deliveredForDistinctId])
        cachedDeliveredDistinctId = .some(record.deliveredForDistinctId)
        return record
    }

    private func writePendingUnregister(_ pending: PendingUnregister) {
        recordLock.withLock {
            storage.setDictionary(forKey: .pushPendingUnregister, contents: [
                Key.distinctId: pending.distinctId,
                Key.deviceToken: pending.deviceToken,
                Key.appId: pending.appId,
            ])
        }
    }

    private func loadPendingUnregister() -> PendingUnregister? {
        recordLock.withLock { loadPendingUnregisterLocked() }
    }

    private func loadPendingUnregisterLocked() -> PendingUnregister? {
        guard let data = storage.getDictionary(forKey: .pushPendingUnregister) as? [String: String],
              let distinctId = data[Key.distinctId],
              let deviceToken = data[Key.deviceToken],
              let appId = data[Key.appId]
        else {
            return nil
        }
        return PendingUnregister(distinctId: distinctId, deviceToken: deviceToken, appId: appId)
    }

    /// Clears the intent only if it's still the one that just resolved — a newer unregister (a second
    /// logout while this DELETE was in flight) may have overwritten the slot, and its intent must not be
    /// dropped by this stale completion.
    private func clearPendingUnregister(matching pending: PendingUnregister) {
        recordLock.withLock { clearPendingUnregisterLocked(matching: pending) }
    }

    private func clearPendingUnregisterLocked(matching pending: PendingUnregister) {
        guard loadPendingUnregisterLocked() == pending else { return }
        storage.remove(key: .pushPendingUnregister)
    }

    /// Transport error (no status), 429, or 5xx is retryable; everything else (4xx) is terminal.
    private func isRetryable(_ info: PostHogUploadInfo) -> Bool {
        info.statusCode.map { $0 == 429 || (500 ... 599 ~= $0) } ?? true
    }

    private func statusString(_ info: PostHogUploadInfo) -> String {
        info.statusCode.map(String.init) ?? "none"
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

        var hasPendingUnregisterForTesting: Bool {
            loadPendingUnregister() != nil
        }
    }
#endif
