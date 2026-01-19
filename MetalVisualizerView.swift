//
//  MetalVisualizerView.swift
//  VFD Visualizer
//
//  Created by Milo Powell on 1/17/26.
//

import Foundation
import SwiftUI
import MetalKit

struct MetalVisualizerView: NSViewRepresentable {
    @ObservedObject var captureManager: CaptureManager
    var isDarkMode: Bool

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.isDarkMode = isDarkMode
    }

    func makeCoordinator() -> Renderer {
        Renderer(captureManager: captureManager)
    }
}
