//
//  DSPEngineWrapper.h
//  VFD Visualizer
//
//  Created by Milo Powell on 1/15/26.
//

#ifndef DSPEngineWrapper_h
#define DSPEngineWrapper_h

#import <Foundation/Foundation.h>

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
