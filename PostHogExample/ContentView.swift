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
                    }
                    .postHogMask()

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

                    Text("Sensitive text!!").postHogMask()
                    Button(action: incCounter) {
                        Text(String(counter))
                    }
                    .postHogMask()

                    TextField("Enter your name", text: $name)
                        .postHogMask()
                    Text("Hello, \(name)!")
                    Button(action: triggerAuthentication) {
                        Text("Trigger fake authentication!")
                    }
                    Button(action: triggerIdentify) {
                        Text("Trigger identify!")
                    }.postHogViewSeen("Trigger identify")
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
