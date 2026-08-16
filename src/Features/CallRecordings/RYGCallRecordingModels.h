#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGCallRecording : NSObject

@property (nonatomic, copy)   NSString *recordingId;
@property (nonatomic, copy, nullable) NSString *threadId;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, assign) BOOL isVideo;

@property (nonatomic, copy, nullable) NSString *peerPk;
@property (nonatomic, copy, nullable) NSString *peerUsername;
@property (nonatomic, copy, nullable) NSString *peerFullName;
@property (nonatomic, copy, nullable) NSString *peerProfilePicURL;

@property (nonatomic, copy, nullable) NSString *threadTitle;
@property (nonatomic, copy, nullable) NSString *threadAvatarURL;

@property (nonatomic, strong) NSDate  *startedAt;
@property (nonatomic, assign) double   durationSeconds;
@property (nonatomic, assign) unsigned long long fileSizeBytes;

@property (nonatomic, copy) NSString *mediaPath;
@property (nonatomic, copy, nullable) NSString *customName;

+ (instancetype)recordingFromJSONDict:(NSDictionary *)dict;
- (NSDictionary *)toJSONDict;

@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSString *avatarURL;

@end

@interface RYGCallRecordingGroup : NSObject
@property (nonatomic, copy, nullable) NSString *threadId;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, copy, nullable) NSString *threadTitle;
@property (nonatomic, copy, nullable) NSString *threadAvatarURL;

@property (nonatomic, copy) NSString *peerPk;
@property (nonatomic, copy, nullable) NSString *peerUsername;
@property (nonatomic, copy, nullable) NSString *peerFullName;
@property (nonatomic, copy, nullable) NSString *peerProfilePicURL;

@property (nonatomic, copy, nullable) NSString *customName;
@property (nonatomic, assign) NSUInteger unreadCount;
@property (nonatomic, strong) NSArray<RYGCallRecording *> *recordings;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) unsigned long long totalBytes;
@property (nonatomic, readonly, nullable) NSDate *lastRecordedAt;
@property (nonatomic, readonly, nullable) RYGCallRecording *latest;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly, nullable) NSString *avatarURL;
@end

NS_ASSUME_NONNULL_END
