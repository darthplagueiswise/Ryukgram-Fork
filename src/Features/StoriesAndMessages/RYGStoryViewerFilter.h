// Shared filter / sort model for the story-viewer list (both the list UI and the
// options sheet read/write this). Sticky per-account via RYGAccountScopedDefaults.
#import <Foundation/Foundation.h>
#import "../../RYGAccountScopedDefaults.h"
#import "../../Localization/RYGLocalization.h"

#define SVK_SORT    @"story_viewer_sort_key"
#define SVK_FILTER  @"story_viewer_filter_mask"
#define SVK_REVERSE @"story_viewer_reverse"

typedef NS_ENUM(NSInteger, RYGSVSort) {
    RYGSVSortDefault = 0,
    RYGSVSortName,
    RYGSVSortVerified,
    RYGSVSortFollowing,
    RYGSVSortFollowsMe,
    RYGSVSortMutual,
    RYGSVSortReacted,
};

typedef NS_OPTIONS(NSUInteger, RYGSVFilter) {
    RYGSVFilterMutual       = 1 << 0,
    RYGSVFilterIFollow      = 1 << 1,
    RYGSVFilterFollowsMe    = 1 << 2,
    RYGSVFilterVerified     = 1 << 3,
    RYGSVFilterReacted      = 1 << 4,
    RYGSVFilterPinned       = 1 << 5,
    RYGSVFilterNotFollowsMe = 1 << 6,
};

// `reacted` = liked (the ❤️ reaction) or sent an emoji reaction — both are one concept.
typedef struct { BOOL following, followedBy, verified, reacted; } RYGSVAttr;

static inline RYGSVSort rygSVSort(void)    { return (RYGSVSort)[[RYGAccountScopedDefaults objectForKey:SVK_SORT] integerValue]; }
static inline RYGSVFilter rygSVFilter(void){ return (RYGSVFilter)[[RYGAccountScopedDefaults objectForKey:SVK_FILTER] unsignedIntegerValue]; }
static inline BOOL rygSVReverse(void)      { return [[RYGAccountScopedDefaults objectForKey:SVK_REVERSE] boolValue]; }
static inline void rygSVSetSort(RYGSVSort v)     { [RYGAccountScopedDefaults setObject:@(v) forKey:SVK_SORT]; }
static inline void rygSVSetFilter(RYGSVFilter v) { [RYGAccountScopedDefaults setObject:@(v) forKey:SVK_FILTER]; }
static inline void rygSVSetReverse(BOOL v)       { [RYGAccountScopedDefaults setObject:@(v) forKey:SVK_REVERSE]; }
static inline BOOL rygSVActive(void)       { return rygSVSort() != RYGSVSortDefault || rygSVFilter() != 0 || rygSVReverse(); }

static inline BOOL rygSVPassesNonPinned(RYGSVFilter f, RYGSVAttr a) {
    if ((f & RYGSVFilterMutual)       && !(a.following && a.followedBy)) return NO;
    if ((f & RYGSVFilterIFollow)      && !a.following)                   return NO;
    if ((f & RYGSVFilterFollowsMe)    && !a.followedBy)                  return NO;
    if ((f & RYGSVFilterNotFollowsMe) && a.followedBy)                   return NO;
    if ((f & RYGSVFilterVerified)     && !a.verified)                    return NO;
    if ((f & RYGSVFilterReacted)      && !a.reacted)                     return NO;
    return YES;
}

static inline NSArray<NSDictionary *> *rygSVFilterRows(void) {
    return @[
        @{@"t": RYGLocalized(@"Pinned"),             @"i": @"pin.fill",                        @"v": @(RYGSVFilterPinned)},
        @{@"t": RYGLocalized(@"Mutuals"),            @"i": @"person.2.fill",                   @"v": @(RYGSVFilterMutual)},
        @{@"t": RYGLocalized(@"People I follow"),    @"i": @"person.fill.checkmark",           @"v": @(RYGSVFilterIFollow)},
        @{@"t": RYGLocalized(@"Follows me"),         @"i": @"arrow.left.circle.fill",          @"v": @(RYGSVFilterFollowsMe)},
        @{@"t": RYGLocalized(@"Doesn't follow you"), @"i": @"person.crop.circle.badge.xmark",  @"v": @(RYGSVFilterNotFollowsMe)},
        @{@"t": RYGLocalized(@"Verified"),           @"i": @"checkmark.seal.fill",             @"v": @(RYGSVFilterVerified)},
        @{@"t": RYGLocalized(@"Reacted"),            @"i": @"heart.fill",                      @"v": @(RYGSVFilterReacted)},
    ];
}
static inline NSArray<NSDictionary *> *rygSVSortRows(void) {
    return @[
        @{@"t": RYGLocalized(@"Default (recent first)"), @"i": @"clock",                  @"v": @(RYGSVSortDefault)},
        @{@"t": RYGLocalized(@"Name (A–Z)"),             @"i": @"textformat",             @"v": @(RYGSVSortName)},
        @{@"t": RYGLocalized(@"Verified first"),         @"i": @"checkmark.seal.fill",    @"v": @(RYGSVSortVerified)},
        @{@"t": RYGLocalized(@"People I follow first"),  @"i": @"person.fill.checkmark",  @"v": @(RYGSVSortFollowing)},
        @{@"t": RYGLocalized(@"Follows me first"),       @"i": @"arrow.left.circle.fill", @"v": @(RYGSVSortFollowsMe)},
        @{@"t": RYGLocalized(@"Mutuals first"),          @"i": @"person.2.fill",          @"v": @(RYGSVSortMutual)},
        @{@"t": RYGLocalized(@"Reacted first"),          @"i": @"heart.fill",             @"v": @(RYGSVSortReacted)},
    ];
}
