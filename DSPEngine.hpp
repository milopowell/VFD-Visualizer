//
//  DSPEngine.hpp
//  VFD Visualizer
//
//  Created by Milo Powell on 1/15/26.
//

#ifndef DSPEngine_hpp
#define DSPEngine_hpp

#include <stdio.h>
#include <vector>
#include <Accelerate/Accelerate.h>

class DSPEngine {
private:
    int fftSize;
    int log2n;
    FFTSetup fftSetup;
    DSPSplitComplex splitComplex;
    
    std::vector<float> frequencyData; // Results for the shader
    std::vector<float> peakData;      // Falling caps
    std::vector<float> peakTimers;    // Duration before caps fall
    std::vector<float> window;        // Hann window to smooth edges
    std::vector<float> realPart;      // Internal FFT buffer
    std::vector<float> imagPart;      // Internal FFT buffer
    std::vector<float> accumulationBuffer;

public:
    DSPEngine(int size);
    ~DSPEngine();
    void performFFT(const float* inputBuffer, int incomingCount);
    
    float* getFrequencyDataPointer() { return frequencyData.data(); }
    float* getPeakDataPointer() { return peakData.data(); }
    
    
    // Default values; can be manipulated by user
    float gain = 20.0f;
    float smoothing = 0.70f;
    float gravity = 0.005f;
    int peakHoldTime = 30;
    int numBars = 32;

};

#endif


