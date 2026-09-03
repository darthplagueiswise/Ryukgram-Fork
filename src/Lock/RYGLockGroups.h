// Lock group registry. Each gateable RyukGram surface is one group with its
// own enable / timeout / relock-on-background / independent-session prefs.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted when any per-group pref changes — observers should reload and
// pop / refresh their cells.
extern NSString *const RYGLockPrefsDidChangeNotification;

// Group identifiers (also used as pref-key suffix and session key).
extern NSString *const RYGLockGroupApp;
extern NSString *const RYGLockGroupSettings;
extern NSString *const RYGLockGroupGallery;
extern NSString *const RYGLockGroupKeepDeleted;
extern NSString *const RYGLockGroupProfileAnalyzer;
extern NSString *const RYGLockGroupCallRecordings;
extern NSString *const RYGLockGroupActivityLog;
extern NSString *const RYGLockGroupMessagesTab;
extern NSString *const RYGLockGroupChats;
extern NSString *const RYGLockGroupHiddenReveal;

@interface RYGLockGroupInfo : NSObject
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSString *displayDescription;
@property (nonatomic, readonly) NSString *iconSymbol;
@property (nonatomic, readonly) BOOL defaultIndependentSession;
@end

FOUNDATION_EXPORT NSArray<RYGLockGroupInfo *> *RYGLockAllGroups(void);
FOUNDATION_EXPORT RYGLockGroupInfo * _Nullable RYGLockGroupInfoFor(NSString *identifier);

FOUNDATION_EXPORT NSString *RYGLockPrefEnabled(NSString *groupID);
FOUNDATION_EXPORT NSString *RYGLockPrefRelockOnBackground(NSString *groupID);
FOUNDATION_EXPORT NSString *RYGLockPrefIdleTimeout(NSString *groupID);
FOUNDATION_EXPORT NSString *RYGLockPrefIndependentSession(NSString *groupID);
FOUNDATION_EXPORT NSString *RYGLockPrefRelockOnDismiss(NSString *groupID);

NS_ASSUME_NONNULL_END
