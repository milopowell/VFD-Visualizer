//
//  DSPEngineWrapper.h
//  VFD Visualizer
//
//  Created by Milo Powell on 1/15/26.
//

#ifndef DSPEngineWrapper_h
#define DSPEngineWrapper_h

#import <Foundation/Foundation.h>

// Frequency range the bars cover, shared by the DSP engine and the axis labels
#define VFD_MIN_FREQUENCY 40.0f
#define VFD_MAX_FREQUENCY 20000.0f

@interface DSPEngineWrapper : NSObject

@property (nonatomic, readonly) float *frequencyBuffer;
@property (nonatomic, readonly) int numberOfBars;
@property (nonatomic, readonly) float *peakBuffer;

-(instancetype)initWithSize:(int)size;
-(void)processAudioSamples:(const float *)samples count:(int)count;
-(void)setGain:(float)gain;
-(void)setSmoothing:(float)smoothing;
-(void)setGravity:(float)gravity;
-(void)setNumBars:(int)numBars;
-(void)setHoldTime:(int)peakHoldTime;
//-(void)setBaseline:(float)baseline;

@end

#endif /* DSPEngineWrapper_h */
