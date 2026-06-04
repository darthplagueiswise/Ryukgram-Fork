// Shared list UI for exclude / locked / hidden chat lists. Configure with
// SCIIDListConfig; the VC owns search, sort, edit, add, swipe, and menus.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIIDListConfig : NSObject

@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *searchPlaceholder;
@property (nonatomic, copy)   NSString *addAlertTitle;
@property (nonatomic, copy)   NSString *addAlertMessage;
@property (nonatomic, copy)   NSString *addAlertPlaceholder;
@property (nonatomic, copy)   NSArray<NSString *> *sortTitles;       // nil = no sort button
@property (nonatomic)         BOOL allowsEdit;                       // default YES
@property (nonatomic)         BOOL allowsAdd;                        // default YES

@property (nonatomic, copy)   NSArray<id> * _Nonnull(^itemsProvider)(void);
@property (nonatomic, copy)   NSString * _Nonnull(^titleProvider)(id item);
@property (nonatomic, copy, nullable) NSString * _Nullable(^subtitleProvider)(id item);
@property (nonatomic, copy, nullable) UIImage  * _Nullable(^iconProvider)(id item);
@property (nonatomic, copy)   BOOL(^matchesQuery)(id item, NSString *query);
@property (nonatomic, copy, nullable) NSArray * _Nonnull(^sortedItems)(NSArray *items, NSInteger mode);
@property (nonatomic, copy, nullable) void(^onTapItem)(id item, UIViewController *vc);
@property (nonatomic, copy)   void(^onRemoveItem)(id item);
@property (nonatomic, copy, nullable) void(^onAddRequest)(NSString *query, UIViewController *vc, void(^reload)(void));
@property (nonatomic, copy, nullable) UIMenu * _Nullable(^contextMenuForItem)(id item, void(^reload)(void));
@property (nonatomic, copy, nullable) NSArray<UIContextualAction *> * _Nonnull(^leadingSwipeActionsForItem)(id item, void(^reload)(void));
@property (nonatomic, copy, nullable) NSArray<UIBarButtonItem *> * _Nonnull(^extraBatchActions)(NSArray *selectedItems, void(^reload)(void), void(^exitEdit)(void));

@end


@interface SCIIDListViewController : UIViewController
@property (nonatomic, strong, readonly) SCIIDListConfig *config;
- (instancetype)initWithConfig:(SCIIDListConfig *)config;
- (void)reload;
@end

NS_ASSUME_NONNULL_END
