//
//  DSPEngineWrapper.m
//  VFD Visualizer
//
//  Created by Milo Powell on 1/15/26.
//

#import <Foundation/Foundation.h>
#import "DSPEngineWrapper.h"
#import "DSPEngine.hpp"

@implementation DSPEngineWrapper {
    DSPEngine *_cppEngine;
    //int _barCount;
}

- (instancetype)initWithSize:(int)size {
    self = [super init];
    if (self) {
        _cppEngine = new DSPEngine(64);
        //_barCount = size;
    }
    return self;
}

- (void)dealloc {
    delete _cppEngine;
}

- (void)processAudioSamples:(const float *)samples count:(int)count {
    _cppEngine->performFFT(samples, count);
}

// Flexible variables
- (void)setGain:(float)gain {
    _cppEngine->gain = gain;
}

- (void)setSmoothing:(float)smoothing {
    _cppEngine->smoothing = smoothing;
}

- (void)setGravity:(float)gravity {
    _cppEngine->gravity = gravity;
}

- (void)setHoldTime:(int)peakHoldTime {
    _cppEngine->peakHoldTime = peakHoldTime;
}

- (void)setNumBars:(int)numBars {
    _cppEngine->numBars = numBars;
}

- (float *)frequencyBuffer {
    return _cppEngine->getFrequencyDataPointer();
}

- (float *)peakBuffer {
    return _cppEngine->getPeakDataPointer();
}

@end
