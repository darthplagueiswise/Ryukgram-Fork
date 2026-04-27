#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SCIResolverReportKind) {
    SCIResolverReportKindDogfoodDeveloper = 0,
    SCIResolverReportKindMobileConfigSymbols = 1,
    SCIResolverReportKindFull = 2,
};

@interface SCIResolverReportViewController : UIViewController

- (instancetype)initWithKind:(SCIResolverReportKind)kind title:(NSString *)title;

@end
