#import <Foundation/Foundation.h>
#import "RYGProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGProfileAnalyzerError) {
    RYGProfileAnalyzerErrorNoSession = 1,
    RYGProfileAnalyzerErrorTooManyFollowers,
    RYGProfileAnalyzerErrorNetwork,
    RYGProfileAnalyzerErrorCancelled,
};

extern const NSInteger RYGProfileAnalyzerMaxFollowerCount;

// userInfo: @"status" (NSString), @"fraction" (NSNumber 0..1).
extern NSNotificationName const RYGProfileAnalyzerProgressDidChangeNotification;
// userInfo: @"user" (NSDictionary, raw IG payload).
extern NSNotificationName const RYGProfileAnalyzerHeaderInfoDidChangeNotification;
// userInfo: @"snapshot" (optional), @"error" (optional).
extern NSNotificationName const RYGProfileAnalyzerDidFinishNotification;

@interface RYGProfileAnalyzerService : NSObject

@property (nonatomic, readonly) BOOL isRunning;

// Latest broadcast progress — used by mid-run VC mounts to paint immediately.
@property (nonatomic, readonly, copy)   NSString *lastStatus;
@property (nonatomic, readonly, assign) double    lastFraction;
@property (nonatomic, readonly, copy, nullable) NSDictionary *lastHeaderInfo;

+ (instancetype)sharedService;

- (void)start;
- (void)cancel;

// VC visibility hooks. Pill (de)materialises on 0↔1 transitions while a scan is in flight.
- (void)attachObserver;
- (void)detachObserver;

@end

NS_ASSUME_NONNULL_END
