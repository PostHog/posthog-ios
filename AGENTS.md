# Project: PostHog iOS SDK

## Project Description
PostHog iOS SDK is a Swift Package Manager and CocoaPods compatible analytics library for iOS, macOS, tvOS, watchOS, and visionOS applications. It provides event tracking, feature flags, session recording, and analytics capabilities for Apple platforms.

## Tech Stack
- **Language**: Swift 5.3+
- **Platforms**: iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1.0+
- **Package Management**: Swift Package Manager (primary), CocoaPods (legacy)
- **Build Tools**: Xcode, xcpretty for formatted output
- **Dependencies**: libwebp (embedded), Quick/Nimble (testing only)

## Code Conventions
- Swift 5.3 language version
- SwiftLint for code linting with auto-fix enabled
- SwiftFormat for consistent code formatting
- Use `make format` to auto-fix formatting and linting issues
- Use `make lint` to check formatting and linting without fixing
- Periphery for detecting unused code (`make api`)

## Project Structure
```
PostHog/                     # Main SDK source code
├── App Life Cycle/          # App lifecycle integration
├── Screen Views/            # Screen tracking functionality
├── Resources/               # Privacy manifest and resources
├── Capture/                 # Event capture implementation
├── Utils/                   # Utility classes and extensions
├── PostHog.swift            # Main SDK interface
├── Autocapture/             # Autocapture implementation
├── Replay/                  # Session replay implementation
├── Surveys/                 # Surveys implementation
├── SwiftUI/                 # SwiftUI modifiers and extensions for Session replay

PostHogTests/               # Unit and integration tests
PostHogExample*/            # Various example applications
vendor/libwebp/             # Embedded libwebp for image processing
```

## Build Commands

**IMPORTANT: Always use `make` commands instead of direct `xcodebuild` or `swift` commands.**

### Primary Commands
- `make build` - Build SDK and all examples for all platforms
- `make buildSdk` - Build only the PostHog SDK for all platforms (iOS, macOS, tvOS, watchOS, visionOS)
- `make buildExamples` - Build all example applications

### Testing Commands
- `make test` - Run Swift Package Manager tests (preferred)
- `make testOniOSSimulator` - Run tests on iOS Simulator
- `make testOnMacSimulator` - Run tests on macOS

### Code Quality Commands
- `make format` - Auto-fix SwiftLint and SwiftFormat issues
- `make lint` - Check code formatting and linting
- `make swiftLint` - Run SwiftLint with auto-fix
- `make swiftFormat` - Run SwiftFormat
- `make api` - Scan for unused code with Periphery

### Setup Commands
- `make bootstrap` - Install all required development tools (CocoaPods, xcpretty, SwiftLint, SwiftFormat, Periphery)

### Testing Framework
- **For new tests**: Use Apple's Swift Testing framework (preferred for all new test development)
  - Use `@Test` macro for test functions
  - Use `#expect` and similar macros for assertions
  - Follow Swift Testing best practices
- **Existing tests**: Currently use Quick/Nimble framework for behavior-driven testing

### Network Mocking
- Use `MockPostHogServer` class for mocking network requests
  - Located in `PostHogTests/TestUtils/MockPostHogServer.swift`
  - Built on top of OHHTTPStubs for HTTP stubbing

### Running Tests
- Use `make test` for running the main test suite (Swift Package Manager based)
- Test files are located in `PostHogTests/` directory

## Important Notes
- libwebp is embedded as a vendor dependency for image processing capabilities
- Always test changes across all supported platforms using `make build`

## Instructions for Claude

### Build and Test Workflow
1. **Always use `make` commands** instead of direct Xcode or Swift commands
2. Run `make format` before committing to ensure code style compliance
3. Run `make test` to execute the test suite
4. Use `make build` to verify changes work across all platforms
5. Run `make lint` to check for any remaining code style issues

### Code Style Preferences
- Follow existing Swift conventions in the codebase
- Use SwiftLint and SwiftFormat rules as defined in the project
- Maintain compatibility across all supported Apple platforms

### Development Approach
- Test changes thoroughly across iOS, macOS, tvOS, watchOS, and visionOS
- Mock network requests in tests using OHHTTPStubs

### Error Handling
- Use existing error handling patterns found in the codebase
- Ensure graceful degradation on unsupported platforms/versions
- Log errors appropriately without exposing sensitive user data

## Common Pitfalls
- Don't use `@available` checks without also adding the platform to Package.swift's platforms array
- The SDK must remain thread-safe - all public APIs should be callable from any thread
- Avoid adding new dependencies - the SDK aims to stay lightweight
- Session recording has different availability per platform - check `#if os()` guards
- The SDK must work offline - don't assume network availability

## Architecture Notes
- The SDK uses a queue-based architecture for event batching
- The main `PostHog` class is a singleton accessed via `PostHog.shared`

## API Design Principles
- Public API changes require careful consideration for backwards compatibility
- Prefer optional parameters with sensible defaults over method overloads
- All public methods should have documentation comments
- Deprecated methods should use `@available(*, deprecated, message:)` with migration guidance
