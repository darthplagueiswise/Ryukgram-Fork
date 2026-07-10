#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCISearchBarStyler : NSObject
+ (BOOL)shouldUseNativeGlass;
+ (void)styleSearchBar:(UISearchBar *)searchBar;
@end

NS_ASSUME_NONNULL_END