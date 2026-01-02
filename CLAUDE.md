# Project: PostHog iOS SDK

## Project Description
PostHog iOS SDK is a Swift Package Manager and CocoaPods compatible analytics library for iOS, macOS, tvOS, watchOS, and visionOS applications. It provides event tracking, feature flags, session recording, and analytics capabilities for Apple platforms.

## Tech Stack
- **Language**: Swift 5.3+
- **Platforms**: iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1.0+
- **Package Management**: Swift Package Manager (primary), CocoaPods (legacy)
- **Testing**: Quick + Nimble, OHHTTPStubs for network mocking
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
└── PostHog.swift           # Main SDK interface

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

## Testing Guidelines
- Use `make test` for running the main test suite (Swift Package Manager based)
- Tests use Quick/Nimble framework for behavior-driven testing
- Network requests are mocked using OHHTTPStubs
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