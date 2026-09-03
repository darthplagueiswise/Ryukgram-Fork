// Single source of truth for the shortcut button (home top bar + messages-only
// inbox header): pref keys, catalog (id ↔ title ↔ symbol), wiring and firing.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kRYGHomeShortcutActionsPrefKey;
extern NSString *const kRYGHomeShortcutEnabledPrefKey;
extern NSString *const kRYGHomeShortcutIconPrefKey;

// Posted on any reorder/toggle/icon change; the injected buttons rebuild live.
extern NSNotificationName const RYGHomeShortcutConfigDidChangeNotification;

@interface RYGHomeShortcutAction : NSObject
@property (nonatomic, copy, readonly) NSString *actionID;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *symbol;
@end

@class RYGChromeButton;

@interface RYGHomeShortcutCatalog : NSObject
+ (NSArray<RYGHomeShortcutAction *> *)allActions;
+ (nullable RYGHomeShortcutAction *)actionForID:(NSString *)actionID;
+ (NSArray<NSString *> *)availableIcons;
/// Enabled action IDs in user order. Empty when master toggle is off.
+ (NSArray<NSString *> *)enabledActionIDs;
/// `contextView` resolves the window / nearest VC for presenting.
+ (void)fireActionID:(NSString *)actionID contextView:(UIView *)contextView;

/// Glyph for the injected button, honoring the icon override.
+ (NSString *)currentSymbol;
/// Symbol + tap-or-menu on a chrome button; idempotent while the config is unchanged.
+ (void)configureButton:(RYGChromeButton *)button;
/// Red unread-count dot, hidden when the enabled actions have no new items.
+ (void)updateBadgeOnButton:(RYGChromeButton *)button;
/// Force the next configureButton: to rebuild after a live config change.
+ (void)invalidateButton:(RYGChromeButton *)button;
@end

NS_ASSUME_NONNULL_END
