//
//  VFD_VisualizerApp.swift
//  VFD Visualizer
//
//  Created by Milo Powell on 1/15/26.
//

import SwiftUI

@main
struct VFD_VisualizerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Hide the title bar so the window looks like a piece of hardware.
        // The close, minimize, and zoom buttons stay in the top-left corner.
        .windowStyle(.hiddenTitleBar)
        // Without a title bar, let the window be dragged from its background
        .windowBackgroundDragBehavior(.enabled)
    }
}
