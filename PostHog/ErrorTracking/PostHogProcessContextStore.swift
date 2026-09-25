//
//  PostHogProcessContextStore.swift
//  PostHog
//

import Foundation

/// Keeps the latest crash context (identity, event properties, exception steps) on disk, one
/// file per process ID.
///
/// A PLCrashReporter report carries its context inside the report. A MetricKit diagnostic
/// doesn't: it arrives on a later launch and only says which process it was for. This store
/// lets that report be tied back to the person and session it happened in.
final class PostHogProcessContextStore {
    static let directoryName = "posthog.processContexts"
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    /// Every launch leaves a context, and most are never claimed.
    static let maxFiles = 20

    private let directory: URL
    private let currentPid: Int32
    private let queue = DispatchQueue(label: "com.posthog.ProcessContextStore", qos: .utility)
    private let pendingLock = NSLock()
    private var pendingBlob: Data?
    private var isClosed = false

    init(directory: URL, currentPid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.directory = directory
        self.currentPid = currentPid
        let ownFile = fileURL(for: currentPid)
        queue.async { [directory] in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // A file under this process ID was left by an earlier process that had the same ID;
            // a report for this process must never be matched to it.
            try? FileManager.default.removeItem(at: ownFile)
            Self.prune(directory, olderThan: Date().addingTimeInterval(-Self.maxAge))
        }
    }

    /// Replaces this process's saved context. Written off the caller's thread; a burst of
    /// writes collapses into one.
    func write(_ blob: Data) {
        let shouldSchedule = pendingLock.withLock { () -> Bool in
            guard !isClosed else { return false }
            let wasPending = pendingBlob != nil
            pendingBlob = blob
            return !wasPending
        }
        guard shouldSchedule else { return }

        let url = fileURL(for: currentPid)
        queue.async { [weak self, directory] in
            guard let latest = self?.takePendingBlob() else { return }
            // Another process sharing an app group container may have deleted the directory.
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? latest.write(to: url, options: .atomic)
        }
    }

    /// Deletes every saved context and ignores later writes, e.g. when crash autocapture stops.
    ///
    /// Synchronous, so a store created right after (on re-enable) can't have its file deleted.
    func removeAll() {
        pendingLock.withLock {
            isClosed = true
            pendingBlob = nil
        }
        queue.sync {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Returns and removes the context saved by `pid`.
    ///
    /// Process IDs get reused, so a context written after `latest` belongs to a later process
    /// and is ignored.
    func takeContext(pid: Int32, notAfter latest: Date) -> [String: Any]? {
        queue.sync {
            let url = fileURL(for: pid)
            guard let lastWritten = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  lastWritten <= latest,
                  let data = try? Data(contentsOf: url),
                  let context = fromJSONData(data)
            else {
                return nil
            }
            try? FileManager.default.removeItem(at: url)
            return context
        }
    }

    private func takePendingBlob() -> Data? {
        pendingLock.withLock {
            let blob = pendingBlob
            pendingBlob = nil
            return blob
        }
    }

    private func fileURL(for pid: Int32) -> URL {
        directory.appendingPathComponent("\(pid).json")
    }

    private static func prune(_ directory: URL, olderThan cutoff: Date) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let newestFirst = files.map { file in
            (file, (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        for (index, (file, modified)) in newestFirst.enumerated() where index >= maxFiles || modified < cutoff {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
