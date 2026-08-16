#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT CGFloat const RYGMediaChromeTopBarContentHeight;
FOUNDATION_EXPORT CGFloat const RYGMediaChromeBottomBarHeight;

UIBlurEffect *RYGMediaChromeBlurEffect(void);
void RYGApplyMediaChromeNavigationBar(UINavigationBar *bar);

UILabel *RYGMediaChromeTitleLabel(NSString *text);
UIImage *RYGMediaChromeTopIcon(NSString *resourceName);
UIImage *RYGMediaChromeBottomIcon(NSString *resourceName);
UIBarButtonItem *RYGMediaChromeTopBarButtonItem(NSString *resourceName, id target, SEL action);

UIView *RYGMediaChromeInstallBottomBar(UIView *hostView);
UIButton *RYGMediaChromeBottomButton(NSString *resourceName, NSString *accessibilityLabel);
UIStackView *RYGMediaChromeInstallBottomRow(UIView *bottomBar, NSArray<UIView *> *row);

NS_ASSUME_NONNULL_END
