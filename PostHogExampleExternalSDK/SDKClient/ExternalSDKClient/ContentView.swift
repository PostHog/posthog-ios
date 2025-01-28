//
//  ContentView.swift
//  TestBuildIssuesClient
//
//  Created by Yiannis Josephides on 24/01/2025.
//

import ExternalSDK
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("Track Event") {
                MyExternalSDK.shared.track(event: "test")
            }
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
