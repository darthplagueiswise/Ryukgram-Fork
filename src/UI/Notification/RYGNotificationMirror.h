#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Mirrors toasts into the iOS notification centre while IG is backgrounded so
// short-lived pills aren't missed. Pref gating, dedup/throttle and permission
// checks all live here.
@interface RYGNotificationMirror : NSObject

// Main thread only.
+ (BOOL)appIsBackgrounded;

// When on, mirrored notifications also present while IG is in the foreground.
+ (BOOL)mirrorsWhileForeground;

// Pref gating only — does not check app state.
+ (BOOL)shouldMirrorAction:(nullable NSString *)actionID;

// Safe to call from any thread. onTap runs when the user taps the mirrored
// notification (kept in memory — a tap after IG was killed just opens the app).
+ (void)mirrorActionID:(nullable NSString *)actionID
                 title:(NSString *)title
              subtitle:(nullable NSString *)subtitle
                 onTap:(nullable void (^)(void))onTap;

// Per-action mirror pref defaults (notif_mirror_<id> = "on"/"off").
+ (NSDictionary<NSString *, NSString *> *)defaultPerActionPrefs;

@end

NS_ASSUME_NONNULL_END
