//
// ORGMEngine.m
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

#import "ORGMEngine.h"

#import "ORGMInputUnit.h"
#import "ORGMOutputUnit.h"
#import "ORGMConverter.h"
#import "ORGMCommonProtocols.h"

@interface ORGMEngine () <ORGMInputUnitDelegate,ORGMOutputUnitDelegate>
@property (strong, nonatomic) ORGMInputUnit *input;
@property (strong, nonatomic) ORGMOutputUnit *output;
@property (strong, nonatomic) ORGMConverter *converter;
@property (assign, nonatomic) ORGMEngineState currentState;
@property (strong, nonatomic) NSError *currentError;
@property (assign, nonatomic) float lastPreloadProgress;
@end

@implementation ORGMEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        self.volume = 100.0f;
        [self setup];
        [self setCurrentState:ORGMEngineStateStopped];
    }
    return self;
}

- (void)dealloc {
    [_input removeObserver:self forKeyPath:@"endOfInput"];
    self.output.outputUnitDelegate = nil;
    self.output = nil;
    self.input.inputUnitDelegate = nil;
    self.input = nil;
    self.converter = nil;
    self.delegate = nil;
}

- (void)setCurrentState:(ORGMEngineState)currentState{
    if(_currentState!=currentState){
        _currentState = currentState;
        if ([_delegate respondsToSelector:@selector(engine:didChangeState:)]) {
            dispatch_async([ORGMQueues callback_queue], ^{
                [_delegate engine:self didChangeState:_currentState];
            });
        }
    }
}

#pragma mark - public

- (void)playUrl:(NSURL *)url withOutputUnitClass:(Class)outputUnitClass {
    if (!outputUnitClass || ![outputUnitClass isSubclassOfClass:[ORGMOutputUnit class]]) {

        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:NSLocalizedString(@"Output unit should be subclass of ORGMOutputUnit", nil)
                                     userInfo:nil];
    }

    if (self.currentState == ORGMEngineStatePlaying) [self stop];
    dispatch_async([ORGMQueues processing_queue], ^{
        self.currentError = nil;

        ORGMInputUnit *input = [[ORGMInputUnit alloc] init];
        self.input = input;
        self.input.inputUnitDelegate = self;

        if (![_input openWithUrl:url]) {
            self.currentState = ORGMEngineStateError;
            self.currentError = [NSError errorWithDomain:kErrorDomain
                                                    code:ORGMEngineErrorCodesSourceFailed
                                                userInfo:@{ NSLocalizedDescriptionKey:
                                                            NSLocalizedString(@"Couldn't open source", nil) }];
            return;
        }
        [_input addObserver:self forKeyPath:@"endOfInput"
                    options:NSKeyValueObservingOptionNew
                    context:nil];

        ORGMConverter *converter = [[ORGMConverter alloc] initWithInputUnit:_input];
        self.converter = converter;

        ORGMOutputUnit *output = [[outputUnitClass alloc] initWithConverter:_converter];
        output.outputFormat = _outputFormat;
        self.output = output;
        self.output.outputUnitDelegate = self;
        [_output setVolume:_volume];

        if (![_converter setupWithOutputUnit:_output]) {
            self.currentState = ORGMEngineStateError;
            self.currentError = [NSError errorWithDomain:kErrorDomain
                                                    code:ORGMEngineErrorCodesConverterFailed
                                                userInfo:@{ NSLocalizedDescriptionKey:
                                                            NSLocalizedString(@"Couldn't setup converter", nil) }];
            return;
        }

        if([_delegate respondsToSelector:@selector(engine:didChangeCurrentURL:prevItemURL:)]) {
            dispatch_async([ORGMQueues callback_queue], ^{
                [_delegate engine:self didChangeCurrentURL:url prevItemURL:nil];
            });
        }
        
        [self setCurrentState:ORGMEngineStatePlaying];
        
        dispatch_source_merge_data([ORGMQueues buffering_source], 1);
    });
}

- (void)playUrl:(NSURL *)url {
   [self playUrl:url withOutputUnitClass:[ORGMOutputUnit class]];
}

- (NSURL *)currentURL{
    return self.input.currentURL;
}

- (float)preloadProgress{
    return self.input.preloadProgress;
}

- (BOOL)isReadyToPlay{
    return self.output.isReadyToPlay;
}

- (void)pause {
    if (_currentState != ORGMEngineStatePlaying)
        return;

    [_output pause];
    [self setCurrentState:ORGMEngineStatePaused];
}

- (void)resume {
    if (_currentState != ORGMEngineStatePaused)
        return;

    [_output resume];
    [self setCurrentState:ORGMEngineStatePlaying];
}

- (void)stop {
    dispatch_async([ORGMQueues processing_queue], ^{
        [self.input removeObserver:self forKeyPath:@"endOfInput"];
        self.output.outputUnitDelegate = nil;
        self.output = nil;
        self.input.inputUnitDelegate = nil;
        self.input = nil;
        self.converter = nil;
        [self setCurrentState:ORGMEngineStateStopped];
    });
}

- (double)trackTime {
    return [_output framesToSeconds:_input.framesCount];
}

- (double)amountPlayed {
    return [_output amountPlayed];
}

- (NSDictionary *)metadata {
    return [_input metadata];
}

- (void)seekToTime:(double)time withDataFlush:(BOOL)flush {
    [_output seek:time];
    [_input seek:time withDataFlush:flush];
    if (flush) [_converter flushBuffer];
}

- (void)seekToTime:(double)time {
    [self seekToTime:time withDataFlush:NO];
}

- (void)setNextUrl:(NSURL *)url withDataFlush:(BOOL)flush {
    NSURL *prevURL = self.currentURL;
    if (!url) {
        [self stop];
    } else {
        dispatch_async([ORGMQueues processing_queue], ^{
            if ([_input openWithUrl:url]==NO) {
                self.currentState = ORGMEngineStateError;
                self.currentError = [NSError errorWithDomain:kErrorDomain
                                                        code:ORGMEngineErrorCodesSourceFailed
                                                    userInfo:@{ NSLocalizedDescriptionKey:
                                                                    NSLocalizedString(@"Couldn't open source", nil) }];
                [self stop];
            }
            else{
                [_converter reinitWithNewInput:_input withDataFlush:flush];
                [_output seek:0.0]; //to reset amount played
                [self setCurrentState:ORGMEngineStatePlaying]; //trigger delegate method
                if([_delegate respondsToSelector:@selector(engine:didChangeCurrentURL:prevItemURL:)]) {
                    dispatch_async([ORGMQueues callback_queue], ^{
                        [_delegate engine:self didChangeCurrentURL:url prevItemURL:prevURL];
                    });
                }
            }
        });
    }
}

#pragma mark - private

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (!_delegate)
        return;

     if ([keyPath isEqualToString:@"endOfInput"]) {
        NSURL *nextUrl = [_delegate engineExpectsNextUrl:self];
        if (!nextUrl) {
            [self setCurrentState:ORGMEngineStateStopped];
            return;
        }
        dispatch_async([ORGMQueues callback_queue], ^{
            [self setNextUrl:nextUrl withDataFlush:NO];
        });
    }
}

- (void)setup {
    dispatch_source_set_event_handler([ORGMQueues buffering_source], ^{
        [_input process];
        [_converter process];
    });
}

- (void)setVolume:(float)volume {
    _volume = volume;
    [_output setVolume:volume];
}

- (void)inputUnit:(ORGMInputUnit *)unit didChangePreloadProgress:(float)progress{
    if( unit==self.input && (ABS(_lastPreloadProgress-progress)>0.05 || (fabs(progress - 1.0) < FLT_EPSILON) || (fabs(progress) < FLT_EPSILON))){
        _lastPreloadProgress = progress;
        if(unit==self.input && [self.delegate respondsToSelector:@selector(engine:didChangePreloadProgress:)]){
            dispatch_async([ORGMQueues callback_queue], ^{
                [self.delegate engine:self didChangePreloadProgress:progress];
            });
        }
    }
}

- (void)inputUnit:(ORGMInputUnit *)unit didFailWithError:(NSError *)error{
    if(unit==self.input && [self.delegate respondsToSelector:@selector(engine:didFailCurrentItemWithError:)]){
        dispatch_async([ORGMQueues callback_queue], ^{
            [self.delegate engine:self didFailCurrentItemWithError:error];
        });
    }
}

- (void)outputUnit:(ORGMOutputUnit *)unit didChangeReadyToPlay:(BOOL)readyToPlay{
    if(unit==self.output && [self.delegate respondsToSelector:@selector(engine:didChangeReadyToPlay:)]){
        dispatch_async([ORGMQueues callback_queue], ^{
            [self.delegate engine:self didChangeReadyToPlay:readyToPlay];
        });
    }
}

@end
