// Shared PK → IGUser resolver. The active IGDirectCacheUpdatesApplicator is
// captured by KeepDeletedMessages's `_applyThreadUpdates:` hook (always
// installed regardless of the keep-deleted pref), so lookups work for any
// feature that lands a senderId.

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void rygDirectUserResolverSetActiveApplicator(id applicator);

id _Nullable rygDirectUserResolverUserForPK(NSString * _Nullable pk);
NSString * _Nullable rygDirectUserResolverUsernameForPK(NSString * _Nullable pk);
NSString * _Nullable rygDirectUserResolverProfilePicURLStringForPK(NSString * _Nullable pk);

// Cache a seen IGUser into the persistent pk -> {username, pic} directory so
// later presence/typing lookups for that pk resolve app-wide.
void rygDirectUserResolverRecordUser(id _Nullable user);

// Every pk we've ever seen: array of @{ "pk", "username", "pic" } (pic optional).
NSArray<NSDictionary *> * _Nonnull rygDirectUserResolverAllKnown(void);
NSString * _Nullable rygDirectUserResolverPicForPK(NSString * _Nullable pk);

// IGUser field extraction — KVC-based, exception-safe.
NSString * _Nullable rygDirectUserResolverPKFromUser(id _Nullable user);
NSString * _Nullable rygDirectUserResolverUsernameFromUser(id _Nullable user);
NSString * _Nullable rygDirectUserResolverProfilePicURLStringFromUser(id _Nullable user);

#ifdef __cplusplus
}
#endif
