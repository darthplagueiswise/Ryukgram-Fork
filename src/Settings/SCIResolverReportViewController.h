#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIResolverReportKind) {
    SCIResolverReportKindDogfoodDeveloper = 0,
    SCIResolverReportKindMobileConfigSymbols = 1,
    SCIResolverReportKindFull = 2,
};

@interface SCIResolverReportViewController : UIViewController

- (instancetype)initWithKind:(SCIResolverReportKind)kind title:(NSString *)title NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
