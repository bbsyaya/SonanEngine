//
// AFSEN.m
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

#import "AFSEN.h"

#import "AFSENInputUnit.h"
#import "AFSENOutputUnit.h"
#import "AFSENConverter.h"
#import "AFSENCommonProtocols.h"

@interface AFSEN () <AFSENInputUnitDelegate, AFSENOutputUnitDelegate>

@property (strong, nonatomic) AFSENInputUnit *input;
@property (strong, nonatomic) AFSENOutputUnit *output;
@property (strong, nonatomic) AFSENConverter *converter;
@property (assign, nonatomic) AFSENState currentState;
@property (strong, nonatomic) NSError *currentError;
@property (assign, nonatomic) float lastPreloadProgress;
@property (strong, nonatomic) dispatch_queue_t callback_queue;
@property (strong, nonatomic) dispatch_queue_t processing_queue;
@property (strong, nonatomic) dispatch_source_t buffering_source;

@end

@implementation AFSEN

- (instancetype)init {
    self = [super init];
    if (self) {
        self.callback_queue = dispatch_queue_create("com.sonan.callback", DISPATCH_QUEUE_SERIAL);
        self.processing_queue = dispatch_queue_create("com.sonan.processing", DISPATCH_QUEUE_SERIAL);
        self.buffering_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD,0, 0, self.processing_queue);
        dispatch_resume(self.buffering_source);
        self.volume = 100.0f;
        [self setup];
        self.currentState = AFSENStateStopped;
    }
    return self;
}

- (void)dealloc {
    self.delegate = nil;
    self.input.inputUnitDelegate = nil;
    [self.input removeItemStatusObserver];
    self.input = nil;
    self.output.outputUnitDelegate = nil;
    self.output = nil;
    self.converter = nil;
    self.callback_queue = nil;
    self.processing_queue = nil;
    self.buffering_source = nil;
}

- (void)setCurrentState:(AFSENState)currentState{
    if(_currentState!=currentState){
        _currentState = currentState;
        if ([self.delegate respondsToSelector:@selector(engine:didChangeState:)]) {
            __weak typeof (self) weakSelf = self;
            dispatch_async(self.callback_queue, ^{
                [weakSelf.delegate engine:weakSelf didChangeState:currentState];
            });
        }
    }
}

#pragma mark - public
- (void)playUrl:(NSURL *)url withOutputUnitClass:(Class)outputUnitClass {
    if (![outputUnitClass isSubclassOfClass:[AFSENOutputUnit class]]) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Output unit should be subclass of AFSENOutputUnit"
                                     userInfo:nil];
    }
    
    if (self.currentState == AFSENStatePlaying){
        [self stop];
    }
    __weak typeof (self) weakSelf = self;
    dispatch_async(self.processing_queue, ^{
        weakSelf.currentError = nil;
        
        AFSENInputUnit *input = [[AFSENInputUnit alloc] init];
        weakSelf.input = input;
        weakSelf.input.inputUnitDelegate = weakSelf;
        
        if (![weakSelf.input openWithUrl:url]) {
            weakSelf.currentState = AFSENStateError;
            weakSelf.currentError = [NSError errorWithDomain:kErrorDomain
                                                        code:AFSENErrorCodesSourceFailed
                                                    userInfo:@{ NSLocalizedDescriptionKey:
                                                                    NSLocalizedString(@"Couldn't open source", nil) }];
            return;
        }
        [weakSelf.input addItemStatusObserver:weakSelf forKeyPaths:[NSSet setWithArray:@[@"endOfInput"]] options:NSKeyValueObservingOptionNew];
        AFSENConverter *converter = [[AFSENConverter alloc] initWithInputUnit:weakSelf.input bufferingSource:weakSelf.buffering_source];
        weakSelf.converter = converter;
        
        AFSENOutputUnit *output = [[outputUnitClass alloc] initWithConverter:weakSelf.converter];
        output.outputFormat = weakSelf.outputFormat;
        [weakSelf.output.converter.inputUnit removeItemStatusObserver];
        weakSelf.output = output;
        weakSelf.output.outputUnitDelegate = weakSelf;
        [weakSelf.output setVolume:weakSelf.volume];
        
        if (![weakSelf.converter setupWithOutputUnit:weakSelf.output]) {
            weakSelf.currentState = AFSENStateError;
            weakSelf.currentError = [NSError errorWithDomain:kErrorDomain
                                                        code:AFSENErrorCodesConverterFailed
                                                    userInfo:@{ NSLocalizedDescriptionKey:
                                                                    NSLocalizedString(@"Couldn't setup converter", nil) }];
            return;
        }
        
        if([weakSelf.delegate respondsToSelector:@selector(engine:didChangeCurrentURL:prevItemURL:)]) {
            dispatch_async(weakSelf.callback_queue, ^{
                [weakSelf.delegate engine:weakSelf didChangeCurrentURL:url prevItemURL:nil];
            });
        }
        weakSelf.currentState = AFSENStatePlaying;
        dispatch_source_merge_data(weakSelf.buffering_source, 1);
    });
}

- (void)playUrl:(NSURL *)url {
   [self playUrl:url withOutputUnitClass:[AFSENOutputUnit class]];
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
    if (self.currentState != AFSENStatePlaying){
        return;
    }
    [self.output pause];
    self.currentState = AFSENStatePaused;
}

- (void)resume {
    if (self.currentState != AFSENStatePaused){
        return;
    }
    [self.output resume];
    self.currentState = AFSENStatePlaying;
}

- (void)stop {
     __weak typeof (self) weakSelf = self;
    dispatch_async(self.processing_queue, ^{
        weakSelf.input.inputUnitDelegate = nil;
        [weakSelf.input removeItemStatusObserver];
        weakSelf.input = nil;
        weakSelf.output.outputUnitDelegate = nil;
        weakSelf.output = nil;
        weakSelf.converter = nil;
        weakSelf.currentState = AFSENStateStopped;
    });
}

- (double)trackTime {
    return [self.output framesToSeconds:self.input.framesCount];
}

- (double)amountPlayed {
    return [self.output amountPlayed];
}

- (NSDictionary *)metadata {
    return [self.input metadata];
}

- (void)seekToTime:(double)time withDataFlush:(BOOL)flush {
    [self.output seek:time];
    [self.input seek:time withDataFlush:flush];
    if (flush) {
        [self.converter flushBuffer];
    }
}

- (void)seekToTime:(double)time {
    [self seekToTime:time withDataFlush:NO];
}

- (void)setNextUrl:(NSURL *)url withDataFlush:(BOOL)flush {
    NSURL *prevURL = self.currentURL;
    if (!url) {
        [self stop];
    } else {
        __weak typeof (self) weakSelf = self;
        dispatch_async(self.processing_queue, ^{
            if ([weakSelf.input openWithUrl:url]==NO) {
                weakSelf.currentState = AFSENStateError;
                weakSelf.currentError = [NSError errorWithDomain:kErrorDomain
                                                        code:AFSENErrorCodesSourceFailed
                                                    userInfo:@{ NSLocalizedDescriptionKey:
                                                                    NSLocalizedString(@"Couldn't open source", nil) }];
                [weakSelf stop];
            }
            else {
                [weakSelf.converter reinitWithNewInput:weakSelf.input withDataFlush:flush];
                [weakSelf.output seek:0.0]; //to reset amount played
                weakSelf.currentState = AFSENStatePlaying; //trigger delegate method
                if([weakSelf.delegate respondsToSelector:@selector(engine:didChangeCurrentURL:prevItemURL:)]) {
                    dispatch_async(weakSelf.callback_queue, ^{
                        [weakSelf.delegate engine:weakSelf didChangeCurrentURL:url prevItemURL:prevURL];
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
    if (self.delegate==nil){
        return;
    }
    if ([keyPath isEqualToString:@"endOfInput"]) {
        NSURL *nextUrl = nil;
        if([self.delegate respondsToSelector:@selector(engineExpectsNextUrl:)]){
            nextUrl = [self.delegate engineExpectsNextUrl:self];
        }
        //play buffered
        if (nextUrl==nil) {
            self.currentState = AFSENStateStopped;
            return;
        }
        __weak typeof (self) weakSelf = self;
        dispatch_async(self.callback_queue, ^{
            [weakSelf setNextUrl:nextUrl withDataFlush:NO];
        });
    }
}

- (void)setup {
    __weak typeof (self) weakSelf = self;
    dispatch_source_set_event_handler(self.buffering_source, ^{
        [weakSelf.input process];
        [weakSelf.converter process];
    });
}

- (void)setVolume:(float)volume {
    _volume = volume;
    [self.output setVolume:volume];
}

- (void)inputUnit:(AFSENInputUnit *)unit didChangePreloadProgress:(float)progress{
    if( unit==self.input && (ABS(_lastPreloadProgress-progress)>0.05 || (fabs(progress - 1.0) < FLT_EPSILON) || (fabs(progress) < FLT_EPSILON))){
        _lastPreloadProgress = progress;
        if(unit==self.input && [self.delegate respondsToSelector:@selector(engine:didChangePreloadProgress:)]){
            __weak typeof (self) weakSelf = self;
            dispatch_async(self.callback_queue, ^{
                [weakSelf.delegate engine:weakSelf didChangePreloadProgress:progress];
            });
        }
    }
}

- (void)inputUnit:(AFSENInputUnit *)unit didFailWithError:(NSError *)error{
    if(unit==self.input && [self.delegate respondsToSelector:@selector(engine:didFailCurrentItemWithError:)]){
        __weak typeof (self) weakSelf = self;
        dispatch_async(self.callback_queue, ^{
            [weakSelf.delegate engine:weakSelf didFailCurrentItemWithError:error];
        });
    }
}

- (void)outputUnit:(AFSENOutputUnit *)unit didChangeReadyToPlay:(BOOL)readyToPlay{
    if(unit==self.output && [self.delegate respondsToSelector:@selector(engine:didChangeReadyToPlay:)]){
        __weak typeof (self) weakSelf = self;
        dispatch_async(self.callback_queue, ^{
            [weakSelf.delegate engine:weakSelf didChangeReadyToPlay:readyToPlay];
        });
    }
}

@end
