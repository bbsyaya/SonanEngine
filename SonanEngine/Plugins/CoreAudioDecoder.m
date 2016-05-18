//
// CoreAudioDecoder.m
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

#import <unistd.h>
#import <AudioToolbox/AudioToolbox.h>

#import "CoreAudioDecoder.h"

const int ID3V1_SIZE = 128;

@interface CoreAudioDecoder () {
    id<ORGMSource>  _source;
    AudioFileID     _audioFile;
    ExtAudioFileRef _in;
    int bitrate;
    int bitsPerSample;
    int channels;
    float frequency;
    long totalFrames;
}
@property (strong, nonatomic) NSMutableDictionary *metadata;
@end

@implementation CoreAudioDecoder

- (void)dealloc {
    [self close];
}

#pragma mark - ORGMDecoder
+ (NSArray *)fileTypes {
    OSStatus err;
    UInt32 size;
    NSArray *sAudioExtensions;
    size = sizeof(sAudioExtensions);
    err  = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AllExtensions, 0, NULL, &size, &sAudioExtensions);
    if (noErr != err) {
        return nil;
    }
    return sAudioExtensions;
}

- (NSDictionary *)properties {
    return @{@"channels": @(channels),
            @"bitsPerSample": @(bitsPerSample),
            @"bitrate": @(bitrate),
            @"sampleRate": @(frequency),
            @"totalFrames": @(totalFrames),
            @"seekable": @YES,
            @"endian": @"big"};
}

- (NSMutableDictionary *)metadata {
    return _metadata;
}

- (int)readAudio:(void *)buf frames:(UInt32)frames {
    OSStatus err;
    AudioBufferList bufferList;
    UInt32 frameCount;

    bufferList.mNumberBuffers              = 1;
    bufferList.mBuffers[0].mNumberChannels = channels;
    bufferList.mBuffers[0].mData           = buf;
    bufferList.mBuffers[0].mDataByteSize   = frames * channels * (bitsPerSample/8);

    frameCount = frames;
    err        = ExtAudioFileRead(_in, &frameCount, &bufferList);
    if (err != noErr) {
        return 0;
    }

    return frameCount;
}

- (BOOL)open:(id<ORGMSource>)source {
    self.metadata = [NSMutableDictionary dictionary];
    _source = source;
    OSStatus result = AudioFileOpenWithCallbacks((__bridge void * _Nonnull)(_source), audioFile_ReadProc, NULL,
                                                 audioFile_GetSizeProc, NULL, 0,
                                                 &_audioFile);

    if (noErr != result) {
        return NO;
    }
    result = ExtAudioFileWrapAudioFileID(_audioFile, false, &_in);
    if (noErr != result) {
        return NO;
    }
    return [self readInfoFromExtAudioFileRef];
}

- (long)seek:(long)frame {
    OSStatus err;
    err = ExtAudioFileSeek(_in, frame);
    if (noErr != err) {
        return -1;
    }
    return frame;
}

- (void)close {
    ExtAudioFileDispose(_in);
    AudioFileClose(_audioFile);
    [_source close];
}

#pragma mark - private

- (BOOL)readInfoFromExtAudioFileRef {
    OSStatus err;
    UInt32 size;
    AudioStreamBasicDescription asbd;

    size = sizeof(asbd);
    err  = ExtAudioFileGetProperty(_in,
            kExtAudioFileProperty_FileDataFormat,
            &size,
            &asbd);
    if (err != noErr) {
        ExtAudioFileDispose(_in);
        return NO;
    }

    bitrate       = 0;
    bitsPerSample = asbd.mBitsPerChannel;
    channels      = asbd.mChannelsPerFrame;
    frequency     = asbd.mSampleRate;

    if(0 == bitsPerSample) {
        bitsPerSample = 16;
    }

    AudioStreamBasicDescription	result;
    bzero(&result, sizeof(AudioStreamBasicDescription));

    result.mFormatID    = kAudioFormatLinearPCM;
    result.mFormatFlags = kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsBigEndian;

    result.mSampleRate       = frequency;
    result.mChannelsPerFrame = channels;
    result.mBitsPerChannel   = bitsPerSample;

    result.mBytesPerPacket  = channels * (bitsPerSample / 8);
    result.mFramesPerPacket = 1;
    result.mBytesPerFrame   = channels * (bitsPerSample / 8);

    err = ExtAudioFileSetProperty(_in, kExtAudioFileProperty_ClientDataFormat,
            sizeof(result), &result);
    if(noErr != err) {
        ExtAudioFileDispose(_in);
        return NO;
    }

    AudioFileID audioFile;
    size = sizeof(AudioFileID);
    err = ExtAudioFileGetProperty(_in,
            kExtAudioFileProperty_AudioFile,
            &size,
            &audioFile);

    if (err == noErr) {
        self.metadata = [self metadataForFile:audioFile];
    }

    Float64 total = 0;
    size = sizeof(total);
    err = AudioFileGetProperty(audioFile, kAudioFilePropertyEstimatedDuration, &size, &total);
    if(err == noErr) totalFrames = total * frequency;

    return YES;
}

- (NSMutableDictionary *)metadataForFile:(AudioFileID)audioFile {

    if ([_source isRemoteSource] &&
        [[_source pathExtension] isEqualToString:@"mp3"]) {

        uint16_t data;
        [_source seek:0 whence:SEEK_SET];
        [_source read:&data amount:2];
        if (data != 17481) return nil; // ID == 17481
    }

    AudioFileID fileID  = audioFile;
    OSStatus err = noErr;
    
    UInt32 id3DataSize = 0;
    char* rawID3Tag = NULL;
    
    //  Reads in the raw ID3 tag info
    err = AudioFileGetPropertyInfo(fileID, kAudioFilePropertyID3Tag, &id3DataSize, NULL);
    if(err != noErr) {
        return nil;
    }
    
    //  Allocate the raw tag data
    rawID3Tag = (char *) malloc(id3DataSize);
    
    if(rawID3Tag == NULL) {
        return nil;
    }
    
    err = AudioFileGetProperty(fileID, kAudioFilePropertyID3Tag, &id3DataSize, rawID3Tag);
    if(err != noErr) {
        return nil;
    }
    
    UInt32 id3TagSize = 0;
    UInt32 id3TagSizeLength = 0;
    err = AudioFormatGetProperty(kAudioFormatProperty_ID3TagSize, id3DataSize, rawID3Tag, &id3TagSizeLength, &id3TagSize);
    
    if(err != noErr) {
        switch(err) {
            case kAudioFormatUnspecifiedError:
                NSLog(@"err: audio format unspecified error");
                return nil;
            case kAudioFormatUnsupportedPropertyError:
                NSLog(@"err: audio format unsupported property error");
                return nil;
            case kAudioFormatBadPropertySizeError:
                NSLog(@"err: audio format bad property size error");
                return nil;
            case kAudioFormatBadSpecifierSizeError:
                NSLog(@"err: audio format bad specifier size error");
                return nil;
            case kAudioFormatUnsupportedDataFormatError:
                NSLog(@"err: audio format unsupported data format error");
                return nil;
            case kAudioFormatUnknownFormatError:
                NSLog(@"err: audio format unknown format error");
                return nil;
            default:
                NSLog(@"err: some other audio format error");
                return nil;
        }
    }
    
    CFDictionaryRef piDict = nil;
    UInt32 piDataSize = sizeof(piDict);
    
    //  Populates a CFDictionary with the ID3 tag properties
    err = AudioFileGetProperty(fileID, kAudioFilePropertyInfoDictionary, &piDataSize, &piDict);
    if(err != noErr) {
        NSLog(@"AudioFileGetProperty failed for property info dictionary");
        return nil;
    }
    
    //  Toll free bridge the CFDictionary so that we can interact with it via objc
    NSDictionary* nsDict = (__bridge NSDictionary*)piDict;
    
    //  ALWAYS CLEAN UP!
    CFRelease(piDict);
    
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    if(nsDict.count>0){
        [result addEntriesFromDictionary:nsDict];
    }
    nsDict = nil;
    free(rawID3Tag);
    
    return result;
}

#pragma mark - callback functions

static OSStatus audioFile_ReadProc(void *inClientData,
                                   SInt64 inPosition,
                                   UInt32 requestCount,
                                   void *buffer,
                                   UInt32 *actualCount) {
    id<ORGMSource> source = (__bridge id<ORGMSource>)(inClientData);

    // Skip potential id3v1 tags over HTTP connection
    if ([source isRemoteSource] &&
        [source size] - inPosition == ID3V1_SIZE) {

        *actualCount = ID3V1_SIZE;
        return noErr;
    }

    [source seek:(long)inPosition whence:0];
    *actualCount = [source read:buffer amount:requestCount];

    return noErr;
}

static SInt64 audioFile_GetSizeProc(void *inClientData) {
    id<ORGMSource> source = (__bridge id<ORGMSource>)(inClientData);
    SInt64 len = [source size];
    return len;
}

@end
