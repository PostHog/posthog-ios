//
//  PostHogAI.swift
//  PostHogAI
//

// Needs the iOS 27 SDK (Swift 6.4): LanguageModel and session usage are new there.
#if canImport(FoundationModels) && compiler(>=6.4) && !os(tvOS)
    import Foundation
    import FoundationModels
    import PostHog

    /// Captures Apple Foundation Models calls as PostHog AI observability events.
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    @available(tvOS, unavailable)
    public enum PostHogAI {
        /// Runs one turn of `session` and captures it as an `$ai_generation` event.
        ///
        /// Make exactly one call on `session` inside `body`, such as `respond(to:)`. For streaming,
        /// create the stream inside `body` too, and iterate it there:
        ///
        /// ```swift
        /// let reply = try await PostHogAI.capture(session, model: "claude-sonnet-5", provider: "anthropic") {
        ///     try await session.respond(to: prompt)
        /// }
        /// ```
        ///
        /// The event carries the token counts the model reported for the whole turn, including any
        /// tool calls, plus latency, tools, model parameters and, when the turn fails, the error.
        /// `body`'s result and errors pass through unchanged.
        ///
        /// - Parameters:
        ///   - session: The session `body` calls.
        ///   - model: The model name to report, for example `"claude-sonnet-5"`. PostHog uses it to
        ///     look up pricing.
        ///   - provider: The provider to report, for example `"apple"` or `"anthropic"`.
        ///   - privacyMode: When `true` (the default), prompts and responses are left out of the
        ///     event. Set to `false` to send them as `$ai_input` and `$ai_output_choices`.
        ///   - properties: Extra properties to add to the event. They override the built-in ones, so
        ///     pass the same `$ai_trace_id` on every turn to group a conversation into one trace.
        ///   - postHog: The SDK instance that captures the event.
        ///   - body: The session call to run.
        /// - Returns: Whatever `body` returns.
        public nonisolated(nonsending) static func capture<T>(
            _ session: LanguageModelSession,
            model: String,
            provider: String,
            privacyMode: Bool = true,
            properties: [String: Any]? = nil,
            postHog: PostHogSDK = .shared,
            _ body: () async throws -> T
        ) async rethrows -> T {
            let turn = AIGenerationTurn(session: session, model: model, provider: provider,
                                        privacyMode: privacyMode, extra: properties)
            do {
                let result = try await body()
                postHog.capture("$ai_generation", properties: turn.properties(session: session, error: nil))
                return result
            } catch {
                postHog.capture("$ai_generation", properties: turn.properties(session: session, error: error))
                throw error
            }
        }
    }

    /// Snapshot of a session taken before a turn, used to work out what the turn added.
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    @available(tvOS, unavailable)
    struct AIGenerationTurn {
        let model: String
        let provider: String
        let privacyMode: Bool
        let extra: [String: Any]?
        let traceId = UUID().uuidString
        let entriesBefore: Int
        let usageBefore: LanguageModelSession.Usage
        let start = ContinuousClock.now

        init(session: LanguageModelSession, model: String, provider: String, privacyMode: Bool, extra: [String: Any]?) {
            self.model = model
            self.provider = provider
            self.privacyMode = privacyMode
            self.extra = extra
            entriesBefore = session.transcript.count
            usageBefore = session.usage
        }

        func properties(session: LanguageModelSession, error: Error?) -> [String: Any] {
            let latency = ContinuousClock.now - start
            let entries = Array(session.transcript)
            let added = entries.dropFirst(entriesBefore)
            // The prompt that started this turn; everything after it is the model's output.
            let promptIndex = added.firstIndex { if case .prompt = $0 { true } else { false } }

            var props: [String: Any] = [
                "$ai_trace_id": traceId,
                "$ai_model": model,
                "$ai_provider": provider,
                "$ai_latency": Double(latency.components.seconds) + Double(latency.components.attoseconds) / 1e18,
            ]

            // Session usage is cumulative, so the turn's usage is the difference. It covers every
            // model call in the turn, including tool-loop calls that `Response.usage` leaves out.
            let usage = session.usage
            props["$ai_input_tokens"] = usage.input.totalTokenCount - usageBefore.input.totalTokenCount
            props["$ai_output_tokens"] = usage.output.totalTokenCount - usageBefore.output.totalTokenCount
            let cached = usage.input.cachedTokenCount - usageBefore.input.cachedTokenCount
            if cached > 0 { props["$ai_cache_read_input_tokens"] = cached }
            let reasoning = usage.output.reasoningTokenCount - usageBefore.output.reasoningTokenCount
            if reasoning > 0 { props["$ai_reasoning_tokens"] = reasoning }

            if let tools = Self.toolDefinitions(in: entries), !tools.isEmpty {
                props["$ai_tools"] = tools.map { ["name": $0.name, "description": $0.description] }
            }
            if let promptIndex, case let .prompt(prompt) = entries[promptIndex] {
                let params = Self.modelParameters(prompt)
                if !params.isEmpty { props["$ai_model_parameters"] = params }
            }

            if !privacyMode, let promptIndex {
                props["$ai_input"] = entries[...promptIndex].compactMap(Self.message)
                props["$ai_output_choices"] = entries[(promptIndex + 1)...].compactMap(Self.message)
            }

            if let error {
                props["$ai_is_error"] = true
                props["$ai_error"] = String(describing: error)
            }

            return props.merging(extra ?? [:]) { _, theirs in theirs }
        }

        private static func toolDefinitions(in entries: [Transcript.Entry]) -> [Transcript.ToolDefinition]? {
            for case let .instructions(instructions) in entries {
                return instructions.toolDefinitions
            }
            return nil
        }

        private static func modelParameters(_ prompt: Transcript.Prompt) -> [String: Any] {
            var params: [String: Any] = [:]
            if let temperature = prompt.options.temperature { params["temperature"] = temperature }
            if let maxTokens = prompt.options.maximumResponseTokens { params["max_tokens"] = maxTokens }
            if let level = prompt.contextOptions.reasoningLevel { params["reasoning_level"] = String(describing: level) }
            return params
        }

        /// Converts a transcript entry to the OpenAI-style message PostHog displays.
        private static func message(_ entry: Transcript.Entry) -> [String: Any]? {
            switch entry {
            case let .instructions(instructions):
                return ["role": "system", "content": text(instructions.segments)]
            case let .prompt(prompt):
                return ["role": "user", "content": text(prompt.segments)]
            case let .response(response):
                return ["role": "assistant", "content": text(response.segments)]
            case let .toolCalls(calls):
                return ["role": "assistant", "tool_calls": calls.map { call in
                    ["id": call.id, "type": "function",
                     "function": ["name": call.toolName, "arguments": call.arguments.jsonString]]
                }]
            case let .toolOutput(output):
                return ["role": "tool", "name": output.toolName, "content": text(output.segments)]
            case .reasoning:
                return nil
            @unknown default:
                return nil
            }
        }

        private static func text(_ segments: [Transcript.Segment]) -> String {
            segments.map { segment in
                switch segment {
                case let .text(text): text.content
                case let .structure(structure): structure.content.jsonString
                case .attachment: "[attachment]"
                @unknown default: ""
                }
            }.joined(separator: "\n")
        }
    }
#endif
