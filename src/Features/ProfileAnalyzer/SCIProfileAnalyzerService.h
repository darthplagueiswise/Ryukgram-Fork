#import <Foundation/Foundation.h>
#import "SCIProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIProfileAnalyzerError) {
    SCIProfileAnalyzerErrorNoSession = 1,
    SCIProfileAnalyzerErrorTooManyFollowers,
    SCIProfileAnalyzerErrorNetwork,
    SCIProfileAnalyzerErrorCancelled,
};

extern const NSInteger SCIProfileAnalyzerMaxFollowerCount;

// userInfo: @"status" (NSString), @"fraction" (NSNumber 0..1).
extern NSNotificationName const SCIProfileAnalyzerProgressDidChangeNotification;
// userInfo: @"user" (NSDictionary, raw IG payload).
extern NSNotificationName const SCIProfileAnalyzerHeaderInfoDidChangeNotification;
// userInfo: @"snapshot" (optional), @"error" (optional).
extern NSNotificationName const SCIProfileAnalyzerDidFinishNotification;

@interface SCIProfileAnalyzerService : NSObject

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
