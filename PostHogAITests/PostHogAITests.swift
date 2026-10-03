//
//  PostHogAITests.swift
//  PostHogAITests
//

#if canImport(FoundationModels) && compiler(>=6.4) && !os(tvOS)
    import Foundation
    import FoundationModels
    import PostHog
    @testable import PostHogAI
    import Testing

    @Suite(.serialized) struct PostHogAITests {
        @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
        @Test("A tool-loop turn reports the tokens of every model call, not just the last")
        func toolLoopTokens() async throws {
            let session = LanguageModelSession(model: FakeModel(), tools: [Temperature()], instructions: "Use the tool.")
            let turn = AIGenerationTurn(session: session, model: "fake", provider: "test", privacyMode: false, extra: nil)
            let response = try await session.respond(to: "Temperature in Lisbon?")
            let props = turn.properties(session: session, error: nil)

            // Two model calls: 40 + 12 input, 6 + 3 output. Response.usage only has the second.
            #expect(response.usage.input.totalTokenCount == 12)
            #expect(props["$ai_input_tokens"] as? Int == 52)
            #expect(props["$ai_output_tokens"] as? Int == 9)
            #expect(props["$ai_cache_read_input_tokens"] as? Int == 4)
            #expect(props["$ai_reasoning_tokens"] as? Int == 1)
            #expect((props["$ai_tools"] as? [[String: Any]])?.first?["name"] as? String == "getTemperature")
            #expect(props["$ai_model"] as? String == "fake")
            #expect(props["$ai_provider"] as? String == "test")
            #expect(props["$ai_trace_id"] is String)
            #expect(props["$ai_latency"] is Double)
            #expect(props["$ai_is_error"] == nil)
        }

        @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
        @Test("Input is the conversation up to the prompt; output is everything the turn added after it")
        func messages() async throws {
            let session = LanguageModelSession(model: FakeModel(), tools: [Temperature()], instructions: "Use the tool.")
            let turn = AIGenerationTurn(session: session, model: "fake", provider: "test", privacyMode: false, extra: nil)
            _ = try await session.respond(to: "Temperature in Lisbon?")
            let props = turn.properties(session: session, error: nil)

            let input = try #require(props["$ai_input"] as? [[String: Any]])
            #expect(input.map { $0["role"] as? String } == ["system", "user"])
            #expect(input.last?["content"] as? String == "Temperature in Lisbon?")

            let output = try #require(props["$ai_output_choices"] as? [[String: Any]])
            #expect(output.map { $0["role"] as? String } == ["assistant", "tool", "assistant"])
            let call = try #require((output.first?["tool_calls"] as? [[String: Any]])?.first?["function"] as? [String: Any])
            #expect(call["name"] as? String == "getTemperature")
            #expect(output.last?["content"] as? String == "It is fine.")
        }

        @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
        @Test("A later turn counts only its own tokens and includes the earlier turns as input")
        func secondTurn() async throws {
            let session = LanguageModelSession(model: FakeModel())
            _ = try await session.respond(to: "First")
            let turn = AIGenerationTurn(session: session, model: "fake", provider: "test", privacyMode: false, extra: nil)
            _ = try await session.respond(to: "Second")
            let props = turn.properties(session: session, error: nil)

            #expect(props["$ai_input_tokens"] as? Int == 12)
            #expect(props["$ai_output_tokens"] as? Int == 3)
            let input = try #require(props["$ai_input"] as? [[String: Any]])
            #expect(input.map { $0["role"] as? String } == ["user", "assistant", "user"])
        }

        @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
        @Test("Privacy mode leaves prompts and responses out but keeps the numbers")
        func privacyMode() async throws {
            let session = LanguageModelSession(model: FakeModel())
            let turn = AIGenerationTurn(session: session, model: "fake", provider: "test", privacyMode: true, extra: nil)
            _ = try await session.respond(to: "Secret")
            let props = turn.properties(session: session, error: nil)

            #expect(props["$ai_input"] == nil)
            #expect(props["$ai_output_choices"] == nil)
            #expect(props["$ai_input_tokens"] as? Int == 12)
        }

        @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
        @Test("Generation options become model parameters")
        func modelParameters() async throws {
            let session = LanguageModelSession(model: FakeModel())
            let turn = AIGenerationTurn(session: session, model: "fake", provider: "test", privacyMode: true, extra: nil)
            _ = try await session.respond(to: "Hi", options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 50))
            let props = turn.properties(session: session, error: nil)

            let params = try #require(props["$ai_model_parameters"] as? [String: Any])
            #expect(params["temperature"] as? Double == 0.3)
            #expect(params["max_tokens"] as? Int == 50)
        }

        @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
        @Test("capture sends one $ai_generation without content by default, passes the result through, and lets properties override")
        func captureSendsEvent() async throws {
            let (sdk, events) = makeSDK()
            defer { sdk.close() }
            let session = LanguageModelSession(model: FakeModel())

            let response = try await PostHogAI.capture(session, model: "fake", provider: "test",
                                                       properties: ["feature": "chat", "$ai_trace_id": "conversation-1"], postHog: sdk)
            {
                try await session.respond(to: "Hi")
            }

            #expect(response.content == "It is fine.")
            let event = try await waitForEvent(events)
            #expect(event.event == "$ai_generation")
            #expect(event.properties["feature"] as? String == "chat")
            #expect(event.properties["$ai_trace_id"] as? String == "conversation-1")
            #expect(event.properties["$ai_output_tokens"] as? Int == 3)
            #expect(event.properties["$ai_input"] == nil)
            #expect(event.properties["$ai_output_choices"] == nil)
        }

        @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
        @Test("capture records a failed turn and rethrows the error")
        func captureRecordsError() async throws {
            let (sdk, events) = makeSDK()
            defer { sdk.close() }
            let session = LanguageModelSession(model: FakeModel(), tools: [BrokenTemperature()])

            await #expect(throws: LanguageModelSession.ToolCallError.self) {
                try await PostHogAI.capture(session, model: "fake", provider: "test", postHog: sdk) {
                    try await session.respond(to: "Temperature in Lisbon?")
                }
            }
            let event = try await waitForEvent(events)
            #expect(event.properties["$ai_is_error"] as? Bool == true)
            #expect((event.properties["$ai_error"] as? String)?.contains("ToolCallError") == true)
            // The model call that asked for the tool still used tokens.
            #expect(event.properties["$ai_input_tokens"] as? Int == 40)
        }

        @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
        @Test("capture can be called from the main actor")
        @MainActor func captureFromMainActor() async throws {
            let (sdk, _) = makeSDK()
            defer { sdk.close() }
            let session = LanguageModelSession(model: FakeModel())
            let response = try await PostHogAI.capture(session, model: "fake", provider: "test", postHog: sdk) {
                try await session.respond(to: "Hi")
            }
            #expect(response.content == "It is fine.")
        }

        // MARK: - Helpers

        private final class Captured: @unchecked Sendable {
            private let lock = NSLock()
            private var events: [PostHogEvent] = []
            func add(_ event: PostHogEvent) {
                lock.withLock { events.append(event) }
            }
            var first: PostHogEvent? { lock.withLock { events.first } }
        }

        /// An SDK whose beforeSend records `$ai_generation` events and drops everything, so nothing
        /// leaves the device.
        private func makeSDK() -> (PostHogSDK, Captured) {
            let captured = Captured()
            let config = PostHogConfig(projectToken: "test-token", host: "http://localhost:9001")
            config.setBeforeSend { event in
                if event.event == "$ai_generation" { captured.add(event) }
                return nil
            }
            return (PostHogSDK.with(config), captured)
        }

        private func waitForEvent(_ captured: Captured) async throws -> PostHogEvent {
            for _ in 0 ..< 100 {
                if let event = captured.first { return event }
                try await Task.sleep(for: .milliseconds(20))
            }
            Issue.record("no $ai_generation event within 2s")
            throw CancellationError()
        }
    }

    // MARK: - Fakes

    /// A deterministic model. With tools enabled and no tool output yet it calls `getTemperature`;
    /// otherwise it answers "It is fine.". Each call reports distinct usage so the tests can tell
    /// a turn's total from the last call's.
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    struct FakeModel: LanguageModel {
        typealias Executor = FakeExecutor
        var capabilities: LanguageModelCapabilities { .init([.toolCalling]) }
        var executorConfiguration: FakeExecutor.Configuration { .init() }
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    struct FakeExecutor: LanguageModelExecutor {
        typealias Model = FakeModel
        struct Configuration: Hashable, Sendable {}
        init(configuration _: Configuration) {}

        nonisolated(nonsending) func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model _: FakeModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            let hasToolOutput = request.transcript.contains { if case .toolOutput = $0 { true } else { false } }
            if !request.enabledToolDefinitions.isEmpty, !hasToolOutput {
                await channel.send(.toolCalls(action: .toolCall(id: "call-1", name: "getTemperature",
                                                                action: .appendArguments(#"{"city":"Lisbon"}"#, tokenCount: 6))))
                await channel.send(.toolCalls(action: .updateUsage(input: .init(totalTokenCount: 40, cachedTokenCount: 0),
                                                                   output: .init(totalTokenCount: 6, reasoningTokenCount: 0))))
                return
            }
            await channel.send(.response(action: .appendText("It is fine.", tokenCount: 3)))
            await channel.send(.response(action: .updateUsage(input: .init(totalTokenCount: 12, cachedTokenCount: 4),
                                                              output: .init(totalTokenCount: 3, reasoningTokenCount: 1))))
        }
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    struct Temperature: Tool {
        let name = "getTemperature"
        let description = "Returns the temperature in Celsius for a city."
        @Generable struct Arguments { @Guide(description: "City name") var city: String }
        func call(arguments _: Arguments) async throws -> String {
            "21"
        }
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    struct BrokenTemperature: Tool {
        struct Down: Error {}
        let name = "getTemperature"
        let description = "Returns the temperature in Celsius for a city."
        @Generable struct Arguments { @Guide(description: "City name") var city: String }
        func call(arguments _: Arguments) async throws -> String {
            throw Down()
        }
    }
#endif
