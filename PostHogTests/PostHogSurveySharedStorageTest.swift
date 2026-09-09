import Foundation
@testable import PostHog
import Testing

extension PostHogSurveyEventsTest {
    @Test("a failed epoch rotation revokes progress for every storage instance")
    func immutableEpochRevokesSharedProgress() throws {
        let first = getSut()
        defer { first.close() }
        let second = getSut(resetStorage: false)
        defer { second.close() }
        second.config.setBeforeSend { _ in nil }
        let storage = try #require(first.storage)
        let epochFile = storage.url(forKey: .surveyResetEpoch)
        let survey = try partialResponseSurvey(enabled: true)
        let integration = try getSurveyIntegration(first)
        integration.setShownSurvey(survey)
        var events: [PostHogEvent] = []
        first.config.setBeforeSend { events.append($0)
            return nil
        }
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: epochFile.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: epochFile.path)
            second.reset()
        }
        second.reset()
        #expect(integration.getNextQuestion(index: 0, response: .openEnded("Old process")) == nil)
        #expect(events.isEmpty)
        #expect(SurveyProgressStore(storage: storage).load(survey) == nil)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: epochFile.path)
        first.reset()
        let recovered = try getSurveyIntegration(second)
        recovered.setShownSurvey(survey)
        _ = recovered.getNextQuestion(index: 0, response: .openEnded("Recovered"))
        #expect(SurveyProgressStore(storage: storage).load(survey)?.responses["$survey_response_first"]?.text == "Recovered")
    }

    @Test("a new shared-storage attempt captures events before resetting SDK warms its identity")
    func surveyEventsDuringResetIdentityGap() throws {
        let first = getSut()
        defer { first.close() }
        let storage = try #require(first.storage)
        var generateDuringReset: (() -> Void)?
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
        config._surveys = true
        config.disableRemoteConfigForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.disableQueueTimerForTesting = true
        config.getAnonymousId = { uuid in
            generateDuringReset?()
            // Preserve the identity created by the other process during this callback.
            return storage.getString(forKey: .anonymousId).flatMap(UUID.init(uuidString:)) ?? uuid
        }
        let second = PostHogSDK.with(config)
        defer { second.close() }
        let survey = try partialResponseSurvey(enabled: true)
        let integration = try getSurveyIntegration(first)
        var events: [PostHogEvent] = []
        first.config.setBeforeSend { events.append($0)
            return nil
        }
        var enteredGap = false
        generateDuringReset = {
            enteredGap = true
            #expect(storage.getString(forKey: .anonymousId) == nil)
            #expect(storage.getString(forKey: .distinctId) == nil)
            integration.setShownSurvey(survey)
            integration.testHandleSurveyShown(survey: survey.toDisplaySurvey())
            _ = integration.getNextQuestion(index: 0, response: .openEnded("First"))
            _ = integration.getNextQuestion(index: 1, response: .openEnded("Final"))
        }
        defer { generateDuringReset = nil }
        second.reset()
        try #require(enteredGap)
        #expect(events.map(\.event) == ["survey shown", "survey sent", "survey sent"])
        #expect(events.allSatisfy { $0.distinctId == second.getDistinctId() })
        #expect(events.last?.properties["$survey_response_first"] as? String == "First")
    }

    @Test("fresh SDK shown events use the newly persisted anonymous identity")
    func freshSurveyEventIdentity() throws {
        let config = PostHogConfig(projectToken: testProjectToken, host: "http://localhost:9090")
        config._surveys = true
        config.disableRemoteConfigForTesting = true
        config.captureApplicationLifecycleEvents = false
        config.disableQueueTimerForTesting = true
        let storage = PostHogStorage(config)
        storage.reset()
        try #require(storage.getString(forKey: .anonymousId) == nil)
        try #require(storage.getString(forKey: .distinctId) == nil)
        let postHog = PostHogSDK.with(config)
        defer { postHog.close() }
        var captured: PostHogEvent?
        config.setBeforeSend { captured = $0
            return nil
        }
        let survey = try partialResponseSurvey(enabled: true)
        let integration = try getSurveyIntegration(postHog)
        integration.setShownSurvey(survey)
        integration.testHandleSurveyShown(survey: survey.toDisplaySurvey())
        let event = try #require(captured)
        #expect(event.event == "survey shown")
        #expect(event.distinctId == storage.getString(forKey: .anonymousId))
    }

    @Test("reset atomically replaces a read-only epoch file")
    func resetReplacesReadOnlyEpoch() throws {
        let postHog = getSut()
        defer { postHog.close() }
        let storage = try #require(postHog.storage)
        let oldEpoch = storage.withSurveyState { $0 }
        let epochFile = storage.url(forKey: .surveyResetEpoch)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: epochFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: epochFile.path) }
        postHog.reset()
        #expect(storage.getString(forKey: .surveyResetEpoch) != oldEpoch)
        #expect(storage.isSurveyGenerationCurrent(oldEpoch) == false)
    }

    @Test("progress without a reset epoch is discarded")
    func ownerlessProgressIsDiscarded() throws {
        let postHog = getSut()
        defer { postHog.close() }
        postHog.config.setBeforeSend { _ in nil }
        let storage = try #require(postHog.storage)
        let survey = try partialResponseSurvey(enabled: true)
        let integration = try getSurveyIntegration(postHog)
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Ownerless"))
        var records = try #require(storage.getDictionary(forKey: .surveyProgress))
        let key = try #require(records.keys.first)
        var record = try #require(records[key] as? [String: Any])
        record.removeValue(forKey: "resetEpoch")
        record["version"] = 1
        records[key] = record
        storage.setDictionary(forKey: .surveyProgress, contents: records)
        #expect(SurveyProgressStore(storage: storage).load(survey) == nil)
        #expect(storage.getDictionary(forKey: .surveyProgress)?.isEmpty == true)
    }

    @Test("survey progress fails closed when the shared lock cannot be opened")
    func unavailableSurveyCoordination() throws {
        let postHog = getSut()
        defer { postHog.close() }
        postHog.config.setBeforeSend { _ in nil }
        let storage = try #require(postHog.storage)
        let survey = try partialResponseSurvey(enabled: true)
        let integration = try getSurveyIntegration(postHog)
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Saved"))
        let store = SurveyProgressStore(storage: storage)
        let progress = try #require(store.load(survey))
        let lockFile = storage.appFolderUrl.appendingPathComponent("posthog.surveyState.lock")
        try FileManager.default.removeItem(at: lockFile)
        try FileManager.default.createDirectory(at: lockFile, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: lockFile) }
        #expect(store.load(survey) == nil)
        store.save(progress, for: survey)
        #expect(integration.getNextQuestion(index: 1, response: .openEnded("Rejected")) == nil)
    }

    @Test("independent storage instances initialize one durable survey epoch")
    func sharedSurveyEpochInitialization() async throws {
        let postHog = getSut()
        defer { postHog.close() }
        let storage = try #require(postHog.storage)
        storage.remove(key: .surveyResetEpoch)
        let instances = (0 ..< 8).map { _ in PostHogStorage(postHog.config) }
        let epochs = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for instance in instances {
                group.addTask { instance.withSurveyState { $0 } }
            }
            var epochs: [String] = []
            for await epoch in group {
                epochs.append(epoch)
            }
            return epochs
        }
        #expect(Set(epochs).count == 1)
        #expect(epochs.first == storage.getString(forKey: .surveyResetEpoch))
    }

    @Test("shared storage rejects an old process's progress after reset", arguments: [false, true])
    func sharedStorageResetRejectsStaleProgress(keepAnonymousId: Bool) throws {
        let first = getSut()
        defer { first.close() }
        first.config.setBeforeSend { _ in nil }
        if !keepAnonymousId { first.identify("old-process-user") }
        let second = getSut(resetStorage: false)
        defer { second.reset()
            second.close()
        }
        second.config.reuseAnonymousId = keepAnonymousId
        second.config.setBeforeSend { _ in nil }
        let firstStorage = try #require(first.storage)
        let secondStorage = try #require(second.storage)
        try #require(firstStorage !== secondStorage)
        try #require(firstStorage.appFolderUrl == secondStorage.appFolderUrl)
        let oldIdentity = first.getDistinctId()
        try #require(second.getDistinctId() == oldIdentity)
        let survey = try partialResponseSurvey(enabled: true)
        let oldIntegration = try getSurveyIntegration(first)
        oldIntegration.setShownSurvey(survey)
        _ = oldIntegration.getNextQuestion(index: 0, response: .openEnded("Old process"))
        let firstStore = SurveyProgressStore(storage: firstStorage)
        let oldProgress = try #require(firstStore.load(survey))
        second.reset()
        #expect((second.getDistinctId() == oldIdentity) == keepAnonymousId)
        firstStore.save(oldProgress, for: survey)
        #expect(SurveyProgressStore(storage: secondStorage).load(survey) == nil)
        let freshIntegration = try getSurveyIntegration(second)
        freshIntegration.setShownSurvey(survey)
        _ = freshIntegration.getNextQuestion(index: 0, response: .openEnded("New process"))
        let freshSubmission = freshIntegration.testActiveSubmissionId
        firstStore.save(oldProgress, for: survey)
        #expect(firstStore.load(survey)?.submissionId == freshSubmission)
        #expect(oldIntegration.getNextQuestion(index: 1, response: .openEnded("Stale callback")) == nil)
        let resumed = try getSurveyIntegration(first)
        resumed.setShownSurvey(survey)
        #expect(resumed.testActiveSubmissionId == freshSubmission)
        var captured: PostHogEvent?
        first.config.setBeforeSend { captured = $0
            return nil
        }
        _ = resumed.getNextQuestion(index: 1, response: .openEnded("Fresh response"))
        let event = try #require(captured)
        #expect(event.distinctId == second.getDistinctId())
        #expect(event.properties["$survey_response_first"] as? String == "New process")
    }

    @Test("reset in another storage instance waits for an in-flight progress write")
    func sharedStorageResetWaitsForWrite() throws {
        let first = getSut()
        defer { first.close() }
        first.config.setBeforeSend { _ in nil }
        let second = getSut(resetStorage: false)
        defer { second.reset()
            second.close()
        }
        let storage = try #require(first.storage)
        let secondStorage = try #require(second.storage)
        let survey = try partialResponseSurvey(enabled: true)
        let integration = try getSurveyIntegration(first)
        integration.setShownSurvey(survey)
        _ = integration.getNextQuestion(index: 0, response: .openEnded("Old process"))
        let store = SurveyProgressStore(storage: storage)
        let progress = try #require(store.load(survey))
        let resetStarted = DispatchSemaphore(value: 0)
        let resetFinished = DispatchSemaphore(value: 0)
        storage.testOnSurveyProgressRead = {
            storage.testOnSurveyProgressRead = nil
            DispatchQueue.global().async {
                resetStarted.signal()
                second.reset()
                resetFinished.signal()
            }
            #expect(resetStarted.wait(timeout: .now() + 5) == .success)
            #expect(resetFinished.wait(timeout: .now() + 0.05) == .timedOut)
        }
        store.save(progress, for: survey)
        try #require(resetFinished.wait(timeout: .now() + 5) == .success)
        #expect(SurveyProgressStore(storage: secondStorage).load(survey) == nil)
    }
}
