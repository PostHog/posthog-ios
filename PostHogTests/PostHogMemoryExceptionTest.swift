import Foundation
@testable import PostHog
import Testing

@Suite("Memory exception (OOM) reporting")
struct PostHogMemoryExceptionTest {
    private let appUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let libUUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func makeConfig() -> PostHogErrorTrackingConfig {
        let config = PostHogErrorTrackingConfig()
        config.inAppIncludes = ["MyApp"]
        config.inAppByDefault = false
        return config
    }

    private func exception(_ properties: [String: Any]) -> [String: Any] {
        (properties["$exception_list"] as? [[String: Any]])?.first ?? [:]
    }

    private func frames(_ properties: [String: Any]) -> [[String: Any]] {
        (exception(properties)["stacktrace"] as? [String: Any])?["frames"] as? [[String: Any]] ?? []
    }

    @Test("reports a fatal OutOfMemory exception")
    func reportsFatalOutOfMemory() {
        let properties = PostHogMemoryExceptionProcessor.processFrames([], config: makeConfig())

        #expect(properties["$exception_level"] as? String == "fatal")
        #expect(exception(properties)["type"] as? String == "OutOfMemory")
        let mechanism = exception(properties)["mechanism"] as? [String: Any]
        #expect(mechanism?["type"] as? String == "memory_exception")
        #expect(mechanism?["handled"] as? Bool == false)
        #expect(exception(properties)["stacktrace"] == nil)
        #expect(properties["$debug_images"] == nil)
    }

    @Test("derives each frame's image address from its offset, outermost frame first")
    func derivesImageAddresses() {
        let properties = PostHogMemoryExceptionProcessor.processFrames([
            PostHogDiagnosticFrame(binaryUUID: libUUID, binaryName: "libsystem_malloc.dylib", address: 0x1_8000_1234, offsetIntoBinaryTextSegment: 0x1234),
            PostHogDiagnosticFrame(binaryUUID: appUUID, binaryName: "MyApp", address: 0x1_0000_0500, offsetIntoBinaryTextSegment: 0x500),
        ], config: makeConfig())

        let frames = frames(properties)
        #expect(frames.count == 2)
        #expect(frames[0]["module"] as? String == "MyApp")
        #expect(frames[0]["instruction_addr"] as? String == "0x0000000100000500")
        #expect(frames[0]["image_addr"] as? String == "0x0000000100000000")
        #expect(frames[0]["in_app"] as? Bool == true)
        #expect(frames[1]["module"] as? String == "libsystem_malloc.dylib")
        #expect(frames[1]["image_addr"] as? String == "0x0000000180000000")
        #expect(frames[1]["in_app"] as? Bool == false)
    }

    @Test("emits one debug image per binary, keyed by UUID and load address")
    func emitsDebugImages() {
        let properties = PostHogMemoryExceptionProcessor.processFrames([
            PostHogDiagnosticFrame(binaryUUID: appUUID, binaryName: "MyApp", address: 0x1_0000_0500, offsetIntoBinaryTextSegment: 0x500),
            PostHogDiagnosticFrame(binaryUUID: appUUID, binaryName: "MyApp", address: 0x1_0000_0900, offsetIntoBinaryTextSegment: 0x900),
        ], config: makeConfig())

        let images = properties["$debug_images"] as? [[String: Any]] ?? []
        #expect(images.count == 1)
        #expect(images.first?["debug_id"] as? String == appUUID.uuidString)
        #expect(images.first?["image_addr"] as? String == "0x0000000100000000")
        #expect(images.first?["code_file"] as? String == "MyApp")
    }

    @Test("keeps a frame without an offset but gives it no image")
    func frameWithoutOffset() {
        let properties = PostHogMemoryExceptionProcessor.processFrames([
            PostHogDiagnosticFrame(binaryUUID: nil, binaryName: nil, address: 0x1234, offsetIntoBinaryTextSegment: nil),
        ], config: makeConfig())

        #expect(frames(properties).count == 1)
        #expect(frames(properties).first?["image_addr"] == nil)
        #expect(properties["$debug_images"] == nil)
    }

    @Test("gives a frame an image address but emits no debug image when the binary has no UUID")
    func imageWithoutUUID() {
        let properties = PostHogMemoryExceptionProcessor.processFrames([
            PostHogDiagnosticFrame(binaryUUID: nil, binaryName: "MyApp", address: 0x1_0000_0500, offsetIntoBinaryTextSegment: 0x500),
        ], config: makeConfig())

        #expect(frames(properties).first?["image_addr"] as? String == "0x0000000100000000")
        #expect(properties["$debug_images"] == nil)
    }

    // MARK: - Process context store

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oom-\(UUID().uuidString)")
    }

    private func blob(_ distinctId: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["distinct_id": distinctId])
    }

    @Test("returns the context a process saved, once")
    func takesContextOnce() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // One instance for both sides: writes are queued, and reading drains the queue.
        let store = PostHogProcessContextStore(directory: directory, currentPid: 42)
        store.write(blob("killed-user"))

        let saved = store.takeContext(pid: 42, notAfter: Date().addingTimeInterval(60))
        #expect(saved?["distinct_id"] as? String == "killed-user")
        #expect(store.takeContext(pid: 42, notAfter: Date().addingTimeInterval(60)) == nil)
    }

    @Test("keeps only the latest context per process")
    func latestWriteWins() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = PostHogProcessContextStore(directory: directory, currentPid: 42)
        writer.write(blob("first"))
        writer.write(blob("second"))

        let saved = writer.takeContext(pid: 42, notAfter: Date().addingTimeInterval(60))
        #expect(saved?["distinct_id"] as? String == "second")
    }

    @Test("ignores a context written after the report's time range, from a reused process ID")
    func ignoresLaterContext() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PostHogProcessContextStore(directory: directory, currentPid: 42)
        store.write(blob("later-process"))

        #expect(store.takeContext(pid: 42, notAfter: Date().addingTimeInterval(-3600)) == nil)
    }

    @Test("keeps only the newest contexts when more than the cap are on disk")
    func capsContextFiles() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let total = PostHogProcessContextStore.maxFiles + 5
        for pid in 1 ... total {
            let url = directory.appendingPathComponent("\(pid).json")
            try blob("user-\(pid)").write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(pid - total) * 60)], ofItemAtPath: url.path)
        }

        let store = PostHogProcessContextStore(directory: directory, currentPid: 999)
        // Reading drains the queue, so pruning has finished.
        #expect(store.takeContext(pid: 1, notAfter: Date()) == nil)
        #expect(store.takeContext(pid: Int32(total), notAfter: Date())?["distinct_id"] as? String == "user-\(total)")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(remaining.count == PostHogProcessContextStore.maxFiles - 1)
    }

    @Test("removeAll deletes every saved context and ignores later writes")
    func removesAll() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try blob("earlier launch").write(to: directory.appendingPathComponent("7.json"))
        let store = PostHogProcessContextStore(directory: directory, currentPid: 42)
        store.write(blob("user"))
        store.removeAll()
        store.write(blob("late write"))

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(store.takeContext(pid: 42, notAfter: Date().addingTimeInterval(60)) == nil)
    }

    @Test("keeps saving after another process sharing the directory removed it")
    func survivesSharedDirectoryRemoval() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = PostHogProcessContextStore(directory: directory, currentPid: 1)
        let appExtension = PostHogProcessContextStore(directory: directory, currentPid: 2)
        _ = appExtension.takeContext(pid: 99, notAfter: Date()) // finish its setup first
        app.removeAll()
        appExtension.write(blob("extension user"))

        #expect(appExtension.takeContext(pid: 2, notAfter: Date().addingTimeInterval(60))?["distinct_id"] as? String == "extension user")
    }

    @Test("a new store takes over its process ID, so an earlier process's file under that ID is never matched")
    func dropsStaleFileForOwnPid() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try blob("earlier process, same pid").write(to: directory.appendingPathComponent("42.json"))

        let store = PostHogProcessContextStore(directory: directory, currentPid: 42)

        #expect(store.takeContext(pid: 42, notAfter: Date().addingTimeInterval(60)) == nil)
    }

    @Test("returns nil for a process that saved nothing")
    func missingContext() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PostHogProcessContextStore(directory: directory, currentPid: 43)
        #expect(store.takeContext(pid: 42, notAfter: Date()) == nil)
    }
}
