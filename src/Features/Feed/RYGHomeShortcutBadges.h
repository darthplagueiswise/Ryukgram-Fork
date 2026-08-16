// Unread-count badges for home-shortcut actions: features bump on new items,
// the count clears when the user opens that surface. Persisted, scoped per active account.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const RYGHomeShortcutBadgesDidChangeNotification;

@interface RYGHomeShortcutBadges : NSObject
+ (void)bumpActionID:(NSString *)actionID;
+ (void)addCount:(NSInteger)delta toActionID:(NSString *)actionID;
+ (void)clearActionID:(NSString *)actionID;
+ (NSInteger)countForActionID:(NSString *)actionID;
+ (NSInteger)totalForActionIDs:(NSArray<NSString *> *)actionIDs;
@end

NS_ASSUME_NONNULL_END
