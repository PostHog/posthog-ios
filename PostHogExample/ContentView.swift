//
//  ContentView.swift
//  PostHogExample
//
//  Created by Ben White on 10.01.23.
//

import AuthenticationServices
import PostHog
import SwiftUI

class SignInViewModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }

    func triggerAuthentication() {
        guard let authURL = URL(string: "https://example.com/auth") else { return }
        let scheme = "exampleauth"

        // Initialize the session.
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { callbackURL, error in
            if callbackURL != nil {
                print("URL", callbackURL!.absoluteString)
            }
            if error != nil {
                print("Error", error!.localizedDescription)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true

        session.start()
    }
}

class FeatureFlagsModel: ObservableObject {
    @Published var boolValue: Bool?
    @Published var stringValue: String?
    @Published var payloadValue: [String: String]?
    @Published var isReloading: Bool = false

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(reloaded), name: PostHogSDK.didReceiveFeatureFlags, object: nil)
    }

    @objc func reloaded() {
        boolValue = PostHogSDK.shared.isFeatureEnabled("4535-funnel-bar-viz")
        stringValue = PostHogSDK.shared.getFeatureFlag("multivariant") as? String
        payloadValue = PostHogSDK.shared.getFeatureFlagPayload("multivariant") as? [String: String]
    }

    func reload() {
        isReloading = true

        PostHogSDK.shared.reloadFeatureFlags {
            self.isReloading = false
        }
    }
}

struct ContentView: View {
    @State var counter: Int = 0
    @State private var name: String = "Max"
    @State private var showingSheet = false
    @State private var showingRedactedSheet = false
    @State private var refreshStatusID = UUID()
    @StateObject var api = Api()

    @StateObject var signInViewModel = SignInViewModel()
    @StateObject var featureFlagsModel = FeatureFlagsModel()

    func incCounter() {
        counter += 1
    }

    func triggerIdentify() {
        PostHogSDK.shared.identify(name, userProperties: [
            "name": name,
        ])
    }

    func testPersonPropertiesForFlags() {
        print("🧪 Testing person properties for flags...")

        // Note: PostHog iOS SDK automatically sets default person properties like:
        // $app_version, $app_build, $os_name, $os_version, $device_type, $locale
        // This ensures feature flags work immediately without waiting for identify() calls.

        // Set some additional test person properties
        PostHogSDK.shared.setPersonPropertiesForFlags([
            "test_property": "manual_test_value",
            "plan": "premium_test",
            "$app_version": "custom_override_version", // This will override the automatic value
        ])

        print("✅ Set person properties for flags")

        // Set some test group properties
        PostHogSDK.shared.setGroupPropertiesForFlags("organization", properties: [
            "plan": "enterprise",
            "seats": 50,
            "industry": "technology",
        ])

        print("✅ Set group properties for flags (organization)")

        // Trigger flag evaluation to send the request
        let flagValue = PostHogSDK.shared.isFeatureEnabled("test_flag")
        print("🏁 Flag value: \(flagValue)")

        // Check what's in getFeatureFlag too
        if let strFlag = PostHogSDK.shared.getFeatureFlag("multivariant") as? String {
            print("📄 Multivariant flag: \(strFlag)")
        }
    }

    func triggerAuthentication() {
        signInViewModel.triggerAuthentication()
    }

    func triggerFlagReload() {
        featureFlagsModel.reload()
    }

    var body: some View {
        NavigationView {
            List {
                #if os(iOS)
                    Section("Manual Session Recording Control") {
                        Text("\(sessionRecordingStatus) SID: \(PostHogSDK.shared.getSessionId() ?? "NA")")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.leading)
                            .id(refreshStatusID)

                        Button("Stop") {
                            PostHogSDK.shared.stopSessionRecording()
                            DispatchQueue.main.async {
                                refreshStatusID = UUID()
                            }
                        }
                        Button("Resume") {
                            PostHogSDK.shared.startSessionRecording()
                            DispatchQueue.main.async {
                                refreshStatusID = UUID()
                            }
                        }
                        Button("Start New Session") {
                            PostHogSDK.shared.startSessionRecording(resumeCurrent: false)
                            DispatchQueue.main.async {
                                refreshStatusID = UUID()
                            }
                        }
                    }
                #endif
                Section("General") {
                    NavigationLink {
                        ContentView()
                    } label: {
                        Text("Infinite navigation")
                    }
                    #if os(iOS)
                    .postHogMask()
                    #endif

                    HStack {
                        Spacer()
                        VStack {
                            Text("Remote Image")
                            AsyncImage(
                                url: URL(string: "https://res.cloudinary.com/dmukukwp6/image/upload/v1710055416/posthog.com/contents/images/media/social-media-headers/hogs/professor_hog.png"),
                                content: { image in
                                    image
                                        .renderingMode(.original)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                },
                                placeholder: {
                                    Color.gray
                                }
                            )
                            .frame(width: 60, height: 60)
                        }
                        Spacer()
                        VStack {
                            Text("Static Image")
                            Image(.maxStatic)
                                .resizable()
                                .frame(width: 60, height: 60)
                        }
                        Spacer()
                    }

                    Button("Show Sheet") {
                        showingSheet.toggle()
                    }
                    .sheet(isPresented: $showingSheet) {
                        ContentView()
                            .postHogScreenView("ContentViewSheet")
                    }
                    Button("Show redacted view") {
                        showingRedactedSheet.toggle()
                    }
                    .sheet(isPresented: $showingRedactedSheet) {
                        RepresentedExampleUIView()
                    }

                    #if os(iOS)
                        Text("Sensitive text!!").postHogMask()
                        Button(action: incCounter) {
                            Text(String(counter))
                        }
                        .postHogMask()
                    #endif

                    TextField("Enter your name", text: $name)
                    #if os(iOS)
                        .postHogMask()
                    #endif

                    Text("Hello, \(name)!")
                    Button(action: triggerAuthentication) {
                        Text("Trigger fake authentication!")
                    }
                    Button(action: triggerIdentify) {
                        Text("Trigger identify!")
                    }.postHogViewSeen("Trigger identify")

                    Button(action: testPersonPropertiesForFlags) {
                        Text("🧪 Test Person & Group Properties")
                    }
                }

                Section("Feature flags") {
                    HStack {
                        Text("Boolean:")
                        Spacer()
                        Text("\(featureFlagsModel.boolValue?.description ?? "unknown")")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("String:")
                        Spacer()
                        Text("\(featureFlagsModel.stringValue ?? "unknown")")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Payload:")
                        Spacer()
                        Text("\(featureFlagsModel.payloadValue?.description ?? "unknown")")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Button(action: triggerFlagReload) {
                            Text("Reload flags")
                        }
                        Spacer()
                        if featureFlagsModel.isReloading {
                            ProgressView()
                        }
                    }
                }

                Section("Error tracking") {
                    Button("Capture Swift Error") {
                        do {
                            throw SampleError.generic
                        } catch {
                            PostHogSDK.shared.captureException(error, properties: [
                                "is_test": true,
                                "error_type": "swift_error",
                            ])
                        }
                    }

                    Button("Capture NSException (Constructed)") {
                        let exception = NSException(
                            name: NSExceptionName("PostHogTestException"),
                            reason: "Manual test exception for error tracking validation",
                            userInfo: [
                                "test_scenario": "manual_button_press",
                                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                            ]
                        )

                        PostHogSDK.shared.captureException(exception, properties: [
                            "is_test": true,
                            "user_initiated": true,
                            "exception_type": "safe_nsexception",
                        ])
                    }

                    Button("Trigger Real NSRangeException") {
                        ExceptionHandler.try({
                            ExceptionHandler.triggerSampleRangeException()
                        }, catch: { exception in
                            PostHogSDK.shared.captureException(exception, properties: [
                                "is_test": true,
                                "exception_type": "real_nsrange_exception",
                                "caught_by": "objective_c_wrapper",
                            ])
                        })
                    }

                    Button("Trigger Real NSInvalidArgumentException") {
                        ExceptionHandler.try({
                            ExceptionHandler.triggerSampleInvalidArgumentException()
                        }, catch: { exception in
                            PostHogSDK.shared.captureException(exception, properties: [
                                "is_test": true,
                                "exception_type": "real_invalid_argument_exception",
                                "caught_by": "objective_c_wrapper",
                            ])
                        })
                    }

                    Button("Trigger Custom NSException") {
                        ExceptionHandler.try({
                            ExceptionHandler.triggerSampleGenericException()
                        }, catch: { exception in
                            PostHogSDK.shared.captureException(exception, properties: [
                                "is_test": true,
                                "exception_type": "real_custom_exception",
                                "caught_by": "objective_c_wrapper",
                            ])
                        })
                    }

                    Button("Trigger Chained NSException") {
                        ExceptionHandler.try({
                            ExceptionHandler.triggerChainedException()
                        }, catch: { exception in
                            PostHogSDK.shared.captureException(exception, properties: [
                                "is_test": true,
                                "exception_type": "chained_exception",
                                "caught_by": "objective_c_wrapper",
                                "scenario": "network_database_business_chain"
                            ])
                        })
                    }

                    Button("Trigger with Message") {
                        PostHogSDK.shared.captureException("Unexpected state detected", properties: [
                            "is_test": true,
                            "app_state": "some_state"
                        ])
                    }
                }

                Section("PostHog beers") {
                    if !api.beers.isEmpty {
                        ForEach(api.beers) { beer in
                            HStack(alignment: .center) {
                                Text(beer.name)
                                Spacer()
                                Text("First brewed")
                                Text(beer.first_brewed).foregroundColor(Color.gray)
                            }
                        }
                    } else {
                        HStack {
                            Text("Loading beers...")
                            Spacer()
                            ProgressView()
                        }
                    }
                }
            }
            .navigationTitle("PostHog")
        }.onAppear {
            api.listBeers(completion: { beers in
                api.beers = beers
            })
        }
    }

    #if os(iOS)
        private var sessionRecordingStatus: String {
            PostHogSDK.shared.isSessionReplayActive() ? "🟢" : "🔴"
        }
    #endif
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

private enum SampleError: Error {
    case generic

    var localizedDescription: String {
        switch self {
        case .generic:
            return "This is a generic error"

        @unknown default:
            return "An unknown error occurred."
        }
    }
}
