#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGDeveloperFeatureViewController : UITableViewController
- (instancetype)initWithTitle:(NSString *)title
                      keywords:(NSArray<NSString *> *)keywords
               wordmarkPreview:(BOOL)wordmarkPreview
        allowsRecommendedApply:(BOOL)allowsRecommendedApply;
@end

NS_ASSUME_NONNULL_END
