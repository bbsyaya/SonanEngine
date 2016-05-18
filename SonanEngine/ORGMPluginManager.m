//
// ORGMPluginManager.m
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

#import "ORGMPluginManager.h"

#import "HTTPSource.h"
#import "FileSource.h"

#import "CoreAudioDecoder.h"
#import "CueSheetDecoder.h"

#import "CueSheetContainer.h"
#import "M3uContainer.h"

@interface ORGMPluginManager ()
@property(strong, nonatomic) NSMutableDictionary *sources;
@property(strong, nonatomic) NSMutableDictionary *decoders;
@property(strong, nonatomic) NSDictionary *containers;
@end

@implementation ORGMPluginManager

+ (ORGMPluginManager *)sharedManager {
    static ORGMPluginManager *_sharedManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedManager = [[ORGMPluginManager alloc] init];
    });
    
    return _sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        
        /* Sources */
        self.sources = [[NSMutableDictionary alloc] init];
        [self registerSource:[HTTPSource class] forScheme:[HTTPSource scheme]];
        [self registerSource:[HTTPSource class] forScheme:@"https"];
        [self registerSource:[FileSource class] forScheme:[FileSource scheme]];
                 
        /* Decoders */
        NSMutableDictionary *decodersDict = [NSMutableDictionary dictionary];
        [[CoreAudioDecoder fileTypes] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            decodersDict[obj] = [CoreAudioDecoder class];
        }];
        [[CueSheetDecoder fileTypes] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            decodersDict[obj] = [CueSheetDecoder class];
        }];
        self.decoders = decodersDict;
        
        Class class;
        if ((class = NSClassFromString(@"FlacDecoder"))) [self registerDecoder:class forFileTypes:@[ @"flac" ]];
        if ((class = NSClassFromString(@"OpusFileDecoder"))) [self registerDecoder:class forFileTypes:@[ @"opus" ]];
        
        /* Containers */        
        NSMutableDictionary *containersDict = [NSMutableDictionary dictionary];
        [[CueSheetContainer fileTypes] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            containersDict[obj] = [CueSheetContainer class];
        }];
        [[M3uContainer fileTypes] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            containersDict[obj] = [M3uContainer class];
        }];
        
        self.containers = containersDict;
    }
    return self;
}

- (void)registerSource:(Class)sourceClass forScheme:(NSString *)scheme{
    @synchronized(self.sources) {
        (self.sources)[scheme] = sourceClass;
    }
}

- (id<ORGMSource>)sourceForURL:(NSURL *)url error:(NullableReferenceNSError)error {
    id<ORGMSource> result;
    if (_resolver && (result = [_resolver sourceForURL:url error:error])) {
        return result;
    }

	NSString *scheme = url.scheme;	
	Class source = _sources[scheme];
	if (!source) {
        NSParameterAssert(NO);
        if (error) {
            NSString *message = [NSString stringWithFormat:@"%@ %@",
                                 NSLocalizedString(@"Unable to find source for scheme", nil),
                                 scheme];
            *error = [NSError errorWithDomain:kErrorDomain
                                         code:ORGMEngineErrorCodesSourceFailed
                                     userInfo:@{ NSLocalizedDescriptionKey: message }];
        }
        return nil;
    }
	return [[source alloc] init];
}

- (id<ORGMDecoder>)decoderForSource:(id<ORGMSource>)source error:(NullableReferenceNSError)error {
    if (!source || ![source url]) {
        NSParameterAssert(NO);
        return nil;
    }

    id<ORGMDecoder> result;
    if (_resolver && (result = [_resolver decoderForSource:source error:error])) {
        return result;
    }

	NSString *extension = [source pathExtension];
	Class decoder = _decoders[extension.lowercaseString];
	if (!decoder) {
        NSParameterAssert(NO);
        if (error) {
            NSString *message = [NSString stringWithFormat:@"%@ %@",
                                 NSLocalizedString(@"Unable to find decoder for extension", nil),
                                 extension];
            *error = [NSError errorWithDomain:kErrorDomain
                                         code:ORGMEngineErrorCodesDecoderFailed
                                     userInfo:@{ NSLocalizedDescriptionKey: message }];
        }
        return nil;
	}
    
	return [[decoder alloc] init];
}

- (NSArray *)supportedFileExtensions{
    return [(self.decoders).allKeys arrayByAddingObjectsFromArray:(self.containers).allKeys];
}

- (NSArray *)urlsForContainerURL:(NSURL *)url error:(NullableReferenceNSError)error {
    NSArray *result;
    if (_resolver && (result = [_resolver urlsForContainerURL:url error:error])) {
        return result;
    }

	NSString *ext = url.path.pathExtension;
	Class container = _containers[ext.lowercaseString];
	if (!container) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"%@ %@",
                                 NSLocalizedString(@"Unable to find container for extension", nil),
                                 ext];
            *error = [NSError errorWithDomain:kErrorDomain
                                         code:ORGMEngineErrorCodesContainerFailed
                                     userInfo:@{ NSLocalizedDescriptionKey: message }];
        }
        return nil;
	}
    
	return [container urlsForContainerURL:url];
}

#pragma mark - private

- (void)registerDecoder:(Class)class forFileTypes:(NSArray *)fileTypes {
    
    [fileTypes enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        _decoders[obj] = class;
    }];
}

@end
