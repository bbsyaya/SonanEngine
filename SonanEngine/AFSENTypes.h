//
//  AFSENTypes.h
//  SonanEngine
//
//  Created by Perceval FARAMAZ on 22.05.16.
//
//

#ifndef NSErrorSpecifier


#define NSErrorSpecifier

typedef NSError*__nullable __autoreleasing*__nullable NullableReferenceNSError;

/**
 Specifies states of the engine.
 */
typedef NS_ENUM(NSInteger, AFSENState) {
    AFSENStateStopped = 0,
    AFSENStatePlaying,
    AFSENStatePaused,
    AFSENStateError
};

/**
 Specifies states of the buffering process.
 */
typedef NS_ENUM(NSInteger, AFSENBuffererState) {
    AFSENBuffererStateEmpty = 0,
    AFSENBuffererStateActive,
    AFSENBuffererStateError
};

#endif