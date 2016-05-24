//
// AFSENInputUnit.m
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

#import "AFSENInputUnit.h"

#import "AFSENPluginManager.h"

@interface AFSENInputUnit () <AFSENSourceDelegate> {
    int bytesPerFrame;
    BOOL _shouldSeek;
    long seekFrame;
}

@property (nonatomic,strong) NSMapTable *observerInfo;
@property (strong, nonatomic) NSMutableData *data;
@property (strong, nonatomic) id<AFSENSource> source;
@property (strong, nonatomic) id<AFSENDecoder> decoder;
@property (assign, nonatomic) BOOL endOfInput;
@property (strong, nonatomic) NSURL *url;
@property (strong, nonatomic) dispatch_queue_t lock_queue;
@property (assign, nonatomic) void *inputBuffer;

@end

@implementation AFSENInputUnit

- (instancetype)init {
    self = [super init];
    if (self) {
        self.lock_queue = dispatch_queue_create("com.sonan.lock",DISPATCH_QUEUE_SERIAL);
        self.data = [[NSMutableData alloc] init];
        self.inputBuffer = malloc(CHUNK_SIZE);
        _endOfInput = NO;
    }
    return self;
}

- (void)dealloc {
    [self removeItemStatusObserver];
    [self close];
    free(self.inputBuffer);
    self.source.sourceDelegate = nil;
    self.url = nil;
}

#pragma mark - public

- (BOOL)openWithUrl:(NSURL *)url {
    self.url = url;
    self.source = [[AFSENPluginManager sharedManager] sourceForURL:url error:nil];
    self.source.sourceDelegate = self;
    if (!self.source || ![self.source open:url]){
        return NO;
    }
    self.decoder = [[AFSENPluginManager sharedManager] decoderForSource:self.source error:nil];
    if (!self.decoder || ![self.decoder open:self.source]){
        return NO;
    }
    int bitsPerSample = [(_decoder.properties)[@"bitsPerSample"] intValue];
	int channels = [(_decoder.properties)[@"channels"] intValue];
    bytesPerFrame = (bitsPerSample/8) * channels;
    return YES;
}

- (NSURL *)currentURL{
    return self.url;
}

- (float)preloadProgress{
    long size = [self.source size];
    long current = [self.source preloadSize];
    if(size!=0){
        return (float)current/(float)size;
    }
    return 0.0;
}

- (void)close {
    [_source close];
    [_decoder close];
}

- (void)process {
    _isProcessing = YES;
    int amountInBuffer = 0;
    int framesRead = 0;

    do {
        if (_data.length >= BUFFER_SIZE) {
            framesRead = 1;
            break;
        }

        if (_shouldSeek) {
            [_decoder seek:seekFrame];
            _shouldSeek = NO;
        }
        int framesToRead = 0;
        if(bytesPerFrame>0){
            framesToRead = CHUNK_SIZE/bytesPerFrame;
        }
        framesRead = [_decoder readAudio:self.inputBuffer frames:framesToRead];
        amountInBuffer = (framesRead * bytesPerFrame);

        __weak typeof (self) weakSelf = self;
        dispatch_sync(self.lock_queue, ^{
            [weakSelf.data appendBytes:weakSelf.inputBuffer length:amountInBuffer];
        });
    } while (framesRead > 0);

    if (framesRead <= 0) {
        [self setEndOfInput:YES];
    }

    _isProcessing = NO;
}

- (double)framesCount {
    NSNumber *frames = (_decoder.properties)[@"totalFrames"];
    return frames.doubleValue;
}

- (void)seek:(double)time withDataFlush:(BOOL)flush {
    if (flush) {
         __weak typeof (self) weakSelf = self;
        dispatch_sync(self.lock_queue, ^{
            weakSelf.data = [[NSMutableData alloc] init];
        });
    }
    seekFrame = time * [(_decoder.properties)[@"sampleRate"] floatValue];
    _shouldSeek = YES;
}

- (void)seek:(double)time {
    [self seek:time withDataFlush:NO];
}

- (AudioStreamBasicDescription)format {
    return propertiesToASBD(_decoder.properties);
}

- (NSDictionary *)metadata {
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    NSDictionary *commonMeta = [[_decoder metadata] copy];
    if(commonMeta.count>0){
        [dict addEntriesFromDictionary:commonMeta];
    }
    if(fabs(self.format.mSampleRate)>FLT_EPSILON){
        double trackDuration = self.framesCount/self.format.mSampleRate;
        dict[@"duration"] = @(trackDuration);
    }
    return dict;
}

- (int)shiftBytes:(NSUInteger)amount buffer:(void *)buffer {
    int bytesToRead = MIN(amount, _data.length);

     __weak typeof (self) weakSelf = self;
    dispatch_sync(self.lock_queue, ^{
        memcpy(buffer, weakSelf.data.bytes, bytesToRead);
        [weakSelf.data replaceBytesInRange:NSMakeRange(0, bytesToRead) withBytes:NULL length:0];
    });

    return bytesToRead;
}

- (void)addItemStatusObserver:(NSObject *)observer forKeyPaths:(NSSet *)keyPaths options:(NSKeyValueObservingOptions)options{
    @synchronized(self) {
        if(self.observerInfo){
            [self removeItemStatusObserver];
        }
        self.observerInfo = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory];
        [keyPaths enumerateObjectsUsingBlock:^(NSString *key, BOOL *stop) {
            @try {[self addObserver:observer forKeyPath:key options:options context:NULL];}@catch (NSException *exception) {}
            [self.observerInfo setObject:observer forKey:key];
        }];
    }
}

- (void)removeItemStatusObserver{
    @synchronized(self) {
        if(self.observerInfo){
            NSArray *keys = [self.observerInfo keyEnumerator].allObjects;
            for (NSString *key in keys) {
                id value = [self.observerInfo objectForKey:key];
                NSParameterAssert(value);
                if(value){
                    @try {[self removeObserver:value forKeyPath:key]; }@catch (NSException *exception) {}
                }
            }
            self.observerInfo = nil;
        }
    }
}

#pragma mark - private

- (void)sourceDidReceiveData:(id<AFSENSource>)source{
    if(source==self.source && [self.inputUnitDelegate respondsToSelector:@selector(inputUnit:didChangePreloadProgress:)]){
        [self.inputUnitDelegate inputUnit:self didChangePreloadProgress:self.preloadProgress];
    }
}

- (void)source:(id<AFSENSource>)source didFailWithError:(NSError *)error{
    if(source==self.source && [self.inputUnitDelegate respondsToSelector:@selector(inputUnit:didFailWithError:)]){
        [self.inputUnitDelegate inputUnit:self didFailWithError:error];
    }
}

@end
