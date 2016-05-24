//
// AFSENInputUnit.h
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


@class AFSENInputUnit;


@protocol AFSENInputUnitDelegate <NSObject>

@optional

- (void)inputUnit:(AFSENInputUnit *)unit didChangePreloadProgress:(float)progress;

- (void)inputUnit:(AFSENInputUnit *)unit  didFailWithError:(NSError *)error;

@end


/**
 `AFSENInputUnit` is a subclass of AFSENAudioUnit for reading and decoding data from the source.
 */
@interface AFSENInputUnit : AFSENAudioUnit

@property (strong, nonatomic, readonly) dispatch_queue_t lock_queue;

@property (nonatomic,weak)id<AFSENInputUnitDelegate> inputUnitDelegate;

/**
 A flag that determines if instance is currently decoding data.
 */
@property (assign, nonatomic, readonly) BOOL isProcessing;

/**
 A flag determines that all input data decoded.
 */
@property (assign, nonatomic, readonly) BOOL endOfInput;

/**
 Open input source and initializes necessary resources.

 @param url A url object to be used as a source path during playback.

 @return `YES` if success, otherwise `NO`.
 */
- (BOOL)openWithUrl:(NSURL *)url;

/**
 Closes input unit and corresponding decoder, deallocates unnecessary resources.
 */
- (void)close;

/**
 Returns current `PCM` audio format.

 @return An `ASBD` struct with current audio format.
 */
@property (readonly) AudioStreamBasicDescription format;

/**
 Returns current track metadata.

 @discussion Dictionary data format depends on the track format. Cover art is included as `NSData` object.

 @return Metadata dictionary or `nil` if track don't have metadata.
 */
@property (readonly, copy) NSDictionary * _Nullable metadata;

/**
 Returns frames number for the current source.

 @return A frames number for the current source.
 */
@property (readonly) double framesCount;

/**
 Seeks to the time within playing track without flushing buffer.

 @param time  Time interval offset in `seconds`.
 @param flush Defines if data should be flushed during seek.
 */
- (void)seek:(double)time withDataFlush:(BOOL)flush;

/**
 Seeks to the time within playing track without flushing buffer.

 @param time Time interval offset in `seconds`.
 */
- (void)seek:(double)time;

/**
 Returns and removes `amount` of bytes from the beginning of the buffer with decoded data.

 @param amount Amount of bytes to return.
 @param buffer Destination buffer. Memory should be preallocated.

 @return Actual amount of shifted bytes.
 */
- (int)shiftBytes:(NSUInteger)amount buffer:(nonnull void *)buffer;


//extra

@property (readonly, copy) NSURL * _Nullable currentURL;

@property (readonly) float preloadProgress;

- (void)addItemStatusObserver:(nonnull NSObject *)observer forKeyPaths:(nonnull NSSet *)keyPaths options:(NSKeyValueObservingOptions)options;

- (void)removeItemStatusObserver;

@end
