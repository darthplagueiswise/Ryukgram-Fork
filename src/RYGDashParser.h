// RYGDashParser — parses DASH MPD manifests from IGMedia for HD streams.

#import <Foundation/Foundation.h>

@interface RYGDashRepresentation : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) NSInteger bandwidth;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic, copy) NSString *qualityLabel;
@property (nonatomic, assign) float frameRate; // 0 if unknown
@property (nonatomic, copy) NSString *codecs;
@end

typedef NS_ENUM(NSInteger, RYGVideoQuality) {
    RYGVideoQualityLowest,
    RYGVideoQualityMedium,
    RYGVideoQualityHighest,
    RYGVideoQualityAsk
};

@interface RYGDashParser : NSObject

+ (NSArray<RYGDashRepresentation *> *)parseManifest:(NSString *)xmlString;
+ (RYGDashRepresentation *)bestVideoFromRepresentations:(NSArray<RYGDashRepresentation *> *)reps;
+ (RYGDashRepresentation *)bestAudioFromRepresentations:(NSArray<RYGDashRepresentation *> *)reps;
+ (NSArray<RYGDashRepresentation *> *)videoRepresentations:(NSArray<RYGDashRepresentation *> *)reps;
+ (NSArray<RYGDashRepresentation *> *)audioRepresentations:(NSArray<RYGDashRepresentation *> *)reps;
+ (RYGDashRepresentation *)representationForQuality:(RYGVideoQuality)quality
                                fromRepresentations:(NSArray<RYGDashRepresentation *> *)reps;
+ (NSString *)dashManifestForMedia:(id)media;

@end
