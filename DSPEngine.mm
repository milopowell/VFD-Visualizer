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
    accumulationBuffer.reserve(8192);
    
    // Create the 'setup' object
    fftSetup = vDSP_create_fftsetup(log2n, kFFTRadix2);
    
    frequencyData.assign(64, 0.0f); // Previous size
    peakData.assign(64, 0.0f);      // Previous size
    peakTimers.assign(64, 0);       // Previous size
    window.assign(fftSize, 0.0f);
    realPart.assign(fftSize / 2, 0.0f);
    imagPart.assign(fftSize / 2, 0.0f);
    
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

    // Add new samples to internal buffer
    for (int i = 0; i < incomingCount; i++) {
        accumulationBuffer.push_back(inputBuffer[i]);
    }

    // Only process if enough data for 4096 FFT
    if (accumulationBuffer.size() >= fftSize) {
        
        // Apply Hann window to the first 4096 samples in the buffer
        std::vector<float> windowedInput(fftSize);
        vDSP_vmul(accumulationBuffer.data(), 1, window.data(), 1, windowedInput.data(), 1, fftSize);

        // Standard vDSP FFT sequence
        vDSP_ctoz((const DSPComplex*)windowedInput.data(), 2, &splitComplex, 1, fftSize / 2);
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFT_FORWARD);

        // Logarithmic mapping
        float sampleRate = 48000.0f;
        float binWidth = sampleRate / (float)fftSize; // ~11.7Hz binWidth

        for (int i = 0; i < numBars; i++) {
            float startFreq = 20.0f * powf(20000.0f / 20.0f, (float)i / numBars);
            float endFreq = 20.0f * powf(20000.0f / 20.0f, (float)(i + 1) / numBars);

            int startBin = (int)(startFreq / binWidth);
            int endBin = (int)(endFreq / binWidth);
            if (endBin <= startBin) endBin = startBin + 1;

            float maxVal = 0.0f;
            for (int k = startBin; k < endBin && k < (fftSize / 2); k++) {
                float mag = (splitComplex.realp[k] * splitComplex.realp[k]) +
                            (splitComplex.imagp[k] * splitComplex.imagp[k]);
                if (mag > maxVal) maxVal = mag;
            }

            float normalized = (10.0f * log10(sqrtf(maxVal) + 1e-6f) + 20.0f + gain) / 60.0f; //10*log for power
            normalized = std::max(0.0f, std::min(1.0f, normalized)); // Baseline adjust

            // Smoothing
            frequencyData[i] = (frequencyData[i] * smoothing) + (normalized * (1.0f - smoothing));

            if (frequencyData[i] >= peakData[i]) {
                peakData[i] = frequencyData[i]; // Push peak up
                peakTimers[i] = peakHoldTime; // Reset hold time
            } else {
                if (peakTimers[i] > 0) peakTimers[i]--; // Hold for a short duration
                else peakData[i] -= gravity; // Fall
            }
            if (peakData[i] < 0) peakData[i] = 0;
        }

        // Remove old samples
        // Hop by 1024 for responsiveness
        accumulationBuffer.erase(accumulationBuffer.begin(), accumulationBuffer.begin() + 1024);
    }
}
