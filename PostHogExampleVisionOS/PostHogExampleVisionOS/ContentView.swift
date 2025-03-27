//
//  ContentView.swift
//  PostHogExampleVisionOS
//
//  Created by Ioannis Josephides on 19/03/2025.
//

import PostHog
import RealityKit
import RealityKitContent
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Model3D(named: "Scene", bundle: realityKitContentBundle)
                .padding(.bottom, 50)

            Button("Send Event") {
                PostHogSDK.shared.capture("Event from VisionOS")
            }
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
