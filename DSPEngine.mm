//
//  DSPEngine.cpp
//  VFD Visualizer
//
//  Created by Milo Powell on 1/15/26.
//

#include "DSPEngine.hpp"
#include <cmath>

// Constructor
DSPEngine::DSPEngine(int size) {
    fftSize = 4096; // Power of 2, standard for audio
    log2n = log2(fftSize);

    // Ring buffer setup for incoming samples
    ringBufferSize = 8192;
    ringBuffer.assign(ringBufferSize, 0.0f);
    ringBufferWritePos = 0;
    samplesInBuffer = 0;
    
    // Throttling setup
    targetFPS = 60;
    minFrameInterval = 1000 / targetFPS;
    lastFFTTime = std::chrono::steady_clock::now();
    
    // Create the FFT setup object
    fftSetup = vDSP_create_fftsetup(log2n, kFFTRadix2);
    
    frequencyData.assign(64, 0.0f); // Previous size
    peakData.assign(64, 0.0f);      // Previous size
    peakTimers.assign(64, 0);       // Previous size
    window.assign(fftSize, 0.0f);
    realPart.assign(fftSize / 2, 0.0f);
    imagPart.assign(fftSize / 2, 0.0f);
    magnitudes.assign(fftSize / 2, 0.0f);
    
    splitComplex.realp = realPart.data();
    splitComplex.imagp = imagPart.data();
    
    // Hann window to reduce spectral leaking
    vDSP_hann_window(window.data(), fftSize, vDSP_HANN_NORM);
}

// Destructor
DSPEngine::~DSPEngine() {
    vDSP_destroy_fftsetup(fftSetup);
}

// Perform FFT
void DSPEngine::performFFT(const float* inputBuffer, int incomingCount) {
    if (!inputBuffer) return;
    
    // Add new samples to ring buffer
    for (int i = 0; i < incomingCount; i++) {
        ringBuffer[ringBufferWritePos] = inputBuffer[i];
        ringBufferWritePos = (ringBufferWritePos + 1) % ringBufferSize;
        if (samplesInBuffer < ringBufferSize) {
            samplesInBuffer++;
        }
    }
    
    // Throttle FFT processing to target FPS
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - lastFFTTime).count();
    
    if (elapsed < minFrameInterval) {
        return; // Skip processing specific frame
    }
    lastFFTTime = now;
    
    // Only process if there are enough samples
    if (samplesInBuffer < fftSize) {
        return;
    }
    
    // Extract samples from ring buffer
    std::vector<float> inputSamples(fftSize);
    int readPos = (ringBufferWritePos - fftSize + ringBufferSize) % ringBufferSize;
    
    for (int i = 0; i < fftSize; i++) {
        inputSamples[i] = ringBuffer[(readPos + i) % ringBufferSize];
    }
    
    
    // Apply Hann window to the first 4096 samples in the buffer
    std::vector<float> windowedInput(fftSize);
    vDSP_vmul(inputSamples.data(), 1, window.data(), 1, windowedInput.data(), 1, fftSize);
    
    // Standard vDSP FFT sequence
    vDSP_ctoz((const DSPComplex*)windowedInput.data(), 2, &splitComplex, 1, fftSize / 2);
    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFT_FORWARD);
    
    // Calculate magnitudes using vDSP
    vDSP_zvmags(&splitComplex, 1, magnitudes.data(), 1, fftSize / 2);
    
    
    // Logarithmic mapping
    float sampleRate = 48000.0f;
    float binWidth = sampleRate / (float)fftSize; // ~11.7Hz binWidth
    
    for (int i = 0; i < numBars; i++) {
        float startFreq = 20.0f * powf(20000.0f / 20.0f, (float)i / numBars);
        float endFreq = 20.0f * powf(20000.0f / 20.0f, (float)(i + 1) / numBars);
        
        int startBin = (int)(startFreq / binWidth);
        int endBin = (int)(endFreq / binWidth);
        if (endBin <= startBin) endBin = startBin + 1;
        if (endBin > fftSize / 2) endBin = fftSize / 2;
        
        float maxVal = 0.0f;
        vDSP_maxv(&magnitudes[startBin], 1, &maxVal, endBin - startBin);
        
        // Normalize using log scale
        float db = 10.0f * log10(maxVal + 1e-6f);
        float normalized = (db - 20.0f + gain) / 60.0f; // Change 20.0f to tweak average gain
        
        // Smoothing
        frequencyData[i] = (frequencyData[i] * smoothing) + (normalized * (1.0f - smoothing));
        
        // Peak tracking
        if (frequencyData[i] >= peakData[i]) {
            peakData[i] = frequencyData[i]; // Push peak up
            peakTimers[i] = peakHoldTime; // Reset hold time
        } else {
            if (peakTimers[i] > 0) peakTimers[i]--; // Hold for a short duration
            else peakData[i] -= gravity; // Fall
        }
        if (peakData[i] < 0) peakData[i] = 0;
    }
    
    // Consume samples from buffer with 1024 hop
    samplesInBuffer -= 1024;
    if (samplesInBuffer < 0) samplesInBuffer = 0;
}

