#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SCIDeletedMessagesChipBar;

@protocol SCIDeletedMessagesChipBarDelegate <NSObject>
- (void)chipBar:(SCIDeletedMessagesChipBar *)bar didSelectIndex:(NSInteger)index;
@end

// Horizontally scrollable, single-select chip strip. Used for kind filter and
// date filter alike. Each chip carries a localized title + optional SF Symbol.
@interface SCIDeletedMessagesChipBar : UIView

@property (nonatomic, weak)   id<SCIDeletedMessagesChipBarDelegate> delegate;
@property (nonatomic, assign) NSInteger selectedIndex;

- (void)setItems:(NSArray<NSString *> *)titles symbols:(nullable NSArray<NSString *> *)symbols;

@end

NS_ASSUME_NONNULL_END
