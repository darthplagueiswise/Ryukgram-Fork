// Lock group registry. Each gateable RyukGram surface is one group with its
// own enable / timeout / relock-on-background / independent-session prefs.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted when any per-group pref changes — observers should reload and
// pop / refresh their cells.
extern NSString *const SCILockPrefsDidChangeNotification;

// Group identifiers (also used as pref-key suffix and session key).
extern NSString *const SCILockGroupApp;
extern NSString *const SCILockGroupSettings;
extern NSString *const SCILockGroupGallery;
extern NSString *const SCILockGroupKeepDeleted;
extern NSString *const SCILockGroupProfileAnalyzer;
extern NSString *const SCILockGroupMessagesTab;
extern NSString *const SCILockGroupChats;
extern NSString *const SCILockGroupHiddenReveal;

@interface SCILockGroupInfo : NSObject
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSString *displayDescription;
@property (nonatomic, readonly) NSString *iconSymbol;
@property (nonatomic, readonly) BOOL defaultIndependentSession;
@end

FOUNDATION_EXPORT NSArray<SCILockGroupInfo *> *SCILockAllGroups(void);
FOUNDATION_EXPORT SCILockGroupInfo * _Nullable SCILockGroupInfoFor(NSString *identifier);

FOUNDATION_EXPORT NSString *SCILockPrefEnabled(NSString *groupID);
FOUNDATION_EXPORT NSString *SCILockPrefRelockOnBackground(NSString *groupID);
FOUNDATION_EXPORT NSString *SCILockPrefIdleTimeout(NSString *groupID);
FOUNDATION_EXPORT NSString *SCILockPrefIndependentSession(NSString *groupID);
FOUNDATION_EXPORT NSString *SCILockPrefRelockOnDismiss(NSString *groupID);

NS_ASSUME_NONNULL_END
