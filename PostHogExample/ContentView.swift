//
//  ContentView.swift
//  PostHogExample
//
//  Created by Ben White on 10.01.23.
//

import AuthenticationServices
import PostHog
import SwiftUI

struct LongScrollView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(0 ..< 3000, id: \.self) { index in
                    VStack {
                        AsyncImage(url: .init(string: "https://picsum.photos/id/\(index)/200/200.jpg")) { result in
                            if let image = result.image{
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.gray
                            }
                        }
                        .aspectRatio(1, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Item \(index)")
                                .font(.headline)
                            Text("This is item number \(index) in a long scrolling list")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .frame(minHeight: 120)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Long Scroll Test")
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
                    Section("Session Replay Test") {
                        NavigationLink {
                            LongScrollView()
                        } label: {
                            Text("Long Scroll Test")
                        }
                    }
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
