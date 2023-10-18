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
            print(callbackURL, error)
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
        NotificationCenter.default.addObserver(self, selector: #selector(reloaded), name: PostHog.didReceiveFeatureFlags, object: nil)
    }

    @objc func reloaded() {
        boolValue = PostHog.shared.isFeatureEnabled("4535-funnel-bar-viz")
        stringValue = PostHog.shared.getFeatureFlag("multivariant") as? String
        payloadValue = PostHog.shared.getFeatureFlagPayload("multivariant") as? [String: String]
    }

    func reload() {
        isReloading = true

        PostHog.shared.reloadFeatureFlags { _, _ in
            self.isReloading = false
        }
    }
}

struct ContentView: View {
    @State var counter: Int = 0
    @State private var name: String = "Tim"
    @State private var showingSheet = false
    @State private var showingRedactedSheet = false
    @StateObject var api = Api()

    @StateObject var signInViewModel = SignInViewModel()
    @StateObject var featureFlagsModel = FeatureFlagsModel()

    func incCounter() {
        counter += 1
    }

    func triggerIdentify() {
        PostHog.shared.identify(name, userProperties: [
            "name": name,
        ])
    }

    func triggerAuthentication() {
        signInViewModel.triggerAuthentication()
    }

    func triggerFlagReload() {
        featureFlagsModel.reload()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    NavigationLink {
                        ContentView()
                    } label: {
                        Text("Infinite navigation")
                    }.accessibilityIdentifier("ph-no-capture")

                    Button("Show Sheet") {
                        showingSheet.toggle()
                    }
                    .sheet(isPresented: $showingSheet) {
                        ContentView()
                    }
                    Button("Show redacted view") {
                        showingRedactedSheet.toggle()
                    }
                    .sheet(isPresented: $showingRedactedSheet) {
                        RepresentedExampleUIView()
                    }

                    Text("Sensitive text!!").accessibilityIdentifier("ph-no-capture")
                    Button(action: incCounter) {
                        Text(String(counter))
                    }.accessibilityIdentifier("ph-no-capture-id").accessibilityLabel("ph-no-capture")

                    TextField("Enter your name", text: $name)
                    Text("Hello, \(name)!")
                    Button(action: triggerAuthentication) {
                        Text("Trigger fake authentication!")
                    }
                    Button(action: triggerIdentify) {
                        Text("Trigger identify!")
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
