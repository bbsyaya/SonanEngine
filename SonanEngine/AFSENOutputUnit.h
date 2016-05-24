//
// AFSENOutputUnit.h
//
// Copyright (c) 2012 ap4y (lod@pisem.net)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFSENAudioUnit.h"
#import "AFSENConverter.h"
#import "AFSENTypes.h"

@class AFSENOutputUnit;


@protocol AFSENOutputUnitDelegate <NSObject>

@optional

- (void)outputUnit:(AFSENOutputUnit *)unit didChangeReadyToPlay:(BOOL)readyToPlay;

@end



/**
 `AFSENOutputUnit` is a subclass of AFSENAudioUnit for playing converted `PCM` data through the output device. This class gets data from the converter buffer.
 */
@interface AFSENOutputUnit : AFSENAudioUnit

@property (nonatomic, weak, nullable) id<AFSENOutputUnitDelegate> outputUnitDelegate;

/**
 A flag that determines if instance is currently active.
 */
@property (assign, nonatomic, readonly) BOOL isProcessing;

/**
 Engine output format
 */
@property (assign, nonatomic) AFSENOutputFormat outputFormat;

/**
 Returns initialized `AFSENOutputUnit` object and specifies converter source.

 @param converter An converter object used as a data source.

 @return An initialized `AFSENOutputUnit` object.
 **/
- (nonnull instancetype)initWithConverter:(nonnull AFSENConverter *)converter NS_DESIGNATED_INITIALIZER;

@property (readonly, strong, nonatomic, nonnull) AFSENConverter *converter;

/**
 Returns supported `PCM` audio format.

 @return An `ASBD` struct with supported audio format.
 */
@property (readonly) AudioStreamBasicDescription format;

/**
 Pauses playback throught the output device. Idempotent method.
 */
- (void)pause;

/**
 Resumes playback throught the output device. Idempotent method.
 */
- (void)resume;

/**
 Stops playback throught the output device and deallocates unnecessary resources. Idempotent method.
 */
- (void)stop;

/**
 Converts `frames` number to `seconds` according to the supported format.

 @param framesCount `Frames` number to convert to `seconds`.

 @return A number of `seconds` for specified number of `frames`.
 */
- (double)framesToSeconds:(double)framesCount;

/**
 Returns amount of played time in `seconds`.
 */
@property (readonly) double amountPlayed;

/**
 Seeks to the time within playing track.

 @param time Time interval offset in `seconds`.
 */
- (void)seek:(double)time;

/**
 Sets output unit volume. Default value `1`.

 @param volume Volume value in `percent`.
 */
- (void)setVolume:(float)volume;

- (void)setSampleRate:(double)sampleRate;

@property (getter=isReadyToPlay, readonly) BOOL readyToPlay;

@end
