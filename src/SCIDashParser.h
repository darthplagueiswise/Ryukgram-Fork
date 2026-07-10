// SCIDashParser — parses DASH MPD manifests from IGMedia for HD streams.

#import <Foundation/Foundation.h>

@interface SCIDashRepresentation : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) NSInteger bandwidth;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic, copy) NSString *qualityLabel;
@property (nonatomic, assign) float frameRate; // 0 if unknown
@property (nonatomic, copy) NSString *codecs;
@end

typedef NS_ENUM(NSInteger, SCIVideoQuality) {
    SCIVideoQualityLowest,
    SCIVideoQualityMedium,
    SCIVideoQualityHighest,
    SCIVideoQualityAsk
};

@interface SCIDashParser : NSObject

+ (NSArray<SCIDashRepresentation *> *)parseManifest:(NSString *)xmlString;
+ (SCIDashRepresentation *)bestVideoFromRepresentations:(NSArray<SCIDashRepresentation *> *)reps;
+ (SCIDashRepresentation *)bestAudioFromRepresentations:(NSArray<SCIDashRepresentation *> *)reps;
+ (NSArray<SCIDashRepresentation *> *)videoRepresentations:(NSArray<SCIDashRepresentation *> *)reps;
+ (SCIDashRepresentation *)representationForQuality:(SCIVideoQuality)quality
                                fromRepresentations:(NSArray<SCIDashRepresentation *> *)reps;
+ (NSString *)dashManifestForMedia:(id)media;

@end
