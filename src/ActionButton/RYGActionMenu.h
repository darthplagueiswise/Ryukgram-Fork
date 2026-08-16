#import <UIKit/UIKit.h>

@class RYGActionMenuConfig;
@class RYGActionConfigSection;

NS_ASSUME_NONNULL_BEGIN

@interface RYGAction : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *subtitle;
@property (nonatomic, copy, readonly, nullable) NSString *systemIconName;
@property (nonatomic, copy, readonly, nullable) void (^handler)(void);
@property (nonatomic, copy, readonly, nullable) NSArray<RYGAction *> *children;
@property (nonatomic, assign, readonly) BOOL destructive;
@property (nonatomic, assign, readonly) BOOL isSeparator;
@property (nonatomic, assign, readonly) BOOL disabled;
// Stable id (matches RYGActionCatalog) so handlers survive title localization.
@property (nonatomic, copy, nullable) NSString *actionID;

+ (instancetype)actionWithTitle:(NSString *)title
                           icon:(nullable NSString *)icon
                        handler:(void(^)(void))handler;

// Must be first in the array. Renders as a small grey caption.
+ (instancetype)headerWithTitle:(NSString *)title;

+ (instancetype)actionWithTitle:(NSString *)title
                       subtitle:(nullable NSString *)subtitle
                           icon:(nullable NSString *)icon
                    destructive:(BOOL)destructive
                        handler:(void(^)(void))handler;

+ (instancetype)actionWithTitle:(NSString *)title
                           icon:(nullable NSString *)icon
                       children:(NSArray<RYGAction *> *)children;

// Group divider. Adjacent non-separator actions fold into one inline submenu.
+ (instancetype)separator;

// Greyed-out, non-tappable. For showing context values inside a menu.
+ (instancetype)infoRowWithTitle:(NSString *)title icon:(nullable NSString *)icon;
@end


@interface RYGActionMenu : NSObject

+ (UIMenu *)buildMenuWithActions:(NSArray<RYGAction *> *)actions;
+ (UIMenu *)buildMenuWithActions:(NSArray<RYGAction *> *)actions title:(nullable NSString *)title;

// Walks config sections, asks `resolver` for each action ID, returns the flat
// list ready for buildMenuWithActions:. Disabled actions and nil resolver
// returns are dropped silently. `dateHeader` (if set) becomes the leading
// grey caption.
+ (NSArray<RYGAction *> *)actionsForConfig:(RYGActionMenuConfig *)config
                                 dateHeader:(nullable NSString *)dateHeader
                                   resolver:(RYGAction * _Nullable (^)(NSString *actionID))resolver;

// Same, but `includeDisabled:YES` keeps menu-disabled actions in the list so
// the default-tap path can still fire one the user hid from the menu.
+ (NSArray<RYGAction *> *)actionsForConfig:(RYGActionMenuConfig *)config
                                 dateHeader:(nullable NSString *)dateHeader
                                   resolver:(RYGAction * _Nullable (^)(NSString *actionID))resolver
                            includeDisabled:(BOOL)includeDisabled;

@end

NS_ASSUME_NONNULL_END
