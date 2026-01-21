//
//  Renderer.swift
//  VFD Visualizer
//
//  Created by Milo Powell on 1/17/26.
//

import Foundation
import MetalKit

// Look if there is a better way
struct VisualizerUniforms {
    var activeColorLow: SIMD3<Float>
    var activeColorHigh: SIMD3<Float>
    var inactiveColor: SIMD3<Float>
    var numBars: Int32
    var showPeaks: Float
    var barSpacing: Float
    var padding: Float = 0
}

class Renderer: NSObject, MTKViewDelegate {
    var captureManager: CaptureManager
    var device: MTLDevice?
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState?
    var isDarkMode: Bool = true
    
    // Frame rate limiting
    private var lastRenderTime: CFTimeInterval = 0
    private let targetFPS: Double = 60
    private let minFrameInterval: CFTimeInterval
    
    init(captureManager: CaptureManager) {
        self.captureManager = captureManager
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        self.minFrameInterval = 1.0 / targetFPS
        super.init()
        setupPipeline()
    }
    
    private func setupPipeline() {
        guard let device = device else { return }
        
        // Check if library exists
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not find Metal Library.")
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vfd_vertex")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "vfd_fragment")
        
        // Ensure this matches the MTKView default
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            // Force an error log here
            Swift.print("PIPELINE ERROR: \(error)")
        }
    }

    func draw(in view: MTKView) {
        // Frame rate limiting
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - lastRenderTime
        
        if elapsed < minFrameInterval {
            return // Skip frame to maintain target fps
        }
        
        lastRenderTime = currentTime
        
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let pipeline = pipelineState,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipeline)

        // Pass the audio data (0)
        let maxBars = 64 // Current max bars
        if let audioDataPtr = captureManager.audioEngine?.frequencyBuffer {
            encoder.setFragmentBytes(audioDataPtr, length: MemoryLayout<Float>.size * maxBars, index: 0)
        }
        
        // Pass the uniforms (1)
        let barSpacing = 1.0 / Float(captureManager.numBars)
        
        let uniforms: VisualizerUniforms
        if isDarkMode {
            uniforms = VisualizerUniforms(
                activeColorLow: SIMD3<Float>(0.0, 1.0, 1.0), // Cyan
                activeColorHigh: SIMD3<Float>(1.0, 0.0, 0.0), // Red
                inactiveColor: SIMD3<Float>(0.0, 0.0, 0.1), // Dark blue
                numBars: Int32(captureManager.numBars),
                showPeaks: captureManager.showPeaks ? 1.0 : 0.0,
                barSpacing: barSpacing
            )
        } else {
            uniforms = VisualizerUniforms(
                activeColorLow: SIMD3<Float>(0.0, 0.4, 0.8), // Deep blue
                activeColorHigh: SIMD3<Float>(0.5, 0.0, 0.5), // Purple
                inactiveColor: SIMD3<Float>(0.9, 0.9, 0.9), // Light Grey
                numBars: Int32(captureManager.numBars),
                showPeaks: captureManager.showPeaks ? 1.0 : 0.0,
                barSpacing: barSpacing
            )
        }
        
        var localUniforms = uniforms
        encoder.setFragmentBytes(&localUniforms, length: MemoryLayout<VisualizerUniforms>.size, index: 1)
        
        // Peak data (2)
        if let peakDataPtr = captureManager.audioEngine?.peakBuffer {
            encoder.setFragmentBytes(peakDataPtr, length: MemoryLayout<Float>.size * maxBars, index: 2)
        }
        
        // Pass the boxes
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
