// Stat pills on Search/Explore media cards: photo (IGMediaThumbnailCell) and
// video (IGDiscoveryGridTopReelsCell, IGDiscoveryGridFeedItemVideoCell) grids.
// Same capsule look as profile card details; IG's own view-count label is
// hidden and redrawn as a pill so every metric matches. Missing counts
// backfill via batched /media/infos/. Profile grids are excluded so
// ProfileReelCardDetails keeps ownership there.

#import "../../Utils.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGIcon.h"
#import "../../Networking/RYGInstagramAPI.h"
#import <substrate.h>
#import <objc/runtime.h>

static const NSInteger kSRViewsTag    = 0x53525601;
static const NSInteger kSRLikesTag    = 0x53524C01;
static const NSInteger kSRCommentsTag = 0x53524301;
static const NSInteger kSRSharesTag   = 0x53525301;
static const NSInteger kSRRepostsTag  = 0x53525201;
static const NSInteger kSRDateTag     = 0x53524401;
static const NSInteger kSRRowBgTag    = 0x5352B603;

static const void *kSRPKKey = &kSRPKKey;

static BOOL srMasterOn(void)    { return [RYGUtils getBoolPref:@"search_card_enabled"]; }
static BOOL srShowViews(void)   { return [RYGUtils getBoolPref:@"search_card_full_views"]; }
static BOOL srShowLikes(void)   { return [RYGUtils getBoolPref:@"search_card_show_likes"]; }
static BOOL srShowComments(void){ return [RYGUtils getBoolPref:@"search_card_show_comments"]; }
static BOOL srShowShares(void)  { return [RYGUtils getBoolPref:@"search_card_show_shares"]; }
static BOOL srShowReposts(void) { return [RYGUtils getBoolPref:@"search_card_show_reposts"]; }
static BOOL srShowDate(void)    { return [RYGUtils getBoolPref:@"search_card_show_date"]; }
static BOOL srShort(void)       { return [RYGUtils getBoolPref:@"search_card_shortened_numbers"]; }
static BOOL srFetchMissing(void){ return [RYGUtils getBoolPref:@"search_card_fetch_missing"]; }
static BOOL srAnyMetricOn(void) { return srShowViews() || srShowLikes() || srShowComments() || srShowShares() || srShowReposts() || srShowDate(); }
static BOOL srEnabled(void)     { return srMasterOn() && srAnyMetricOn(); }

static BOOL srMetricOn(NSString *m) {
	if ([m isEqualToString:@"views"])    return srShowViews();
	if ([m isEqualToString:@"likes"])    return srShowLikes();
	if ([m isEqualToString:@"comments"]) return srShowComments();
	if ([m isEqualToString:@"shares"])   return srShowShares();
	if ([m isEqualToString:@"reposts"])  return srShowReposts();
	if ([m isEqualToString:@"date"])     return srShowDate();
	return NO;
}
static NSInteger srTagFor(NSString *m) {
	if ([m isEqualToString:@"views"])    return kSRViewsTag;
	if ([m isEqualToString:@"likes"])    return kSRLikesTag;
	if ([m isEqualToString:@"comments"]) return kSRCommentsTag;
	if ([m isEqualToString:@"shares"])   return kSRSharesTag;
	if ([m isEqualToString:@"reposts"])  return kSRRepostsTag;
	if ([m isEqualToString:@"date"])     return kSRDateTag;
	return 0;
}
static NSString *srIconFor(NSString *m) {
	if ([m isEqualToString:@"views"])    return @"ig_icon_eye_outline_12";
	if ([m isEqualToString:@"likes"])    return @"direct-like";
	if ([m isEqualToString:@"comments"]) return @"ig_icon_comment_outline_24";
	if ([m isEqualToString:@"shares"])   return @"ig_icon_direct_prism_outline_24";
	if ([m isEqualToString:@"reposts"])  return @"ig_icon_reshare_outline_24";
	if ([m isEqualToString:@"date"])     return @"clock-small";
	return @"";
}

static NSArray<NSNumber *> *srAllTags(void) {
	return @[@(kSRViewsTag), @(kSRLikesTag), @(kSRCommentsTag), @(kSRSharesTag), @(kSRRepostsTag), @(kSRDateTag)];
}
static NSArray<NSString *> *srMetricOrder(void) {
	NSArray *canon = @[@"views", @"likes", @"comments", @"shares", @"reposts", @"date"];
	NSString *raw = [RYGUtils getStringPref:@"search_card_order"] ?: @"";
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *p in [raw componentsSeparatedByString:@","]) {
		NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([canon containsObject:t] && ![out containsObject:t]) [out addObject:t];
	}
	for (NSString *c in canon) if (![out containsObject:c]) [out addObject:c];
	return out;
}

static NSString *srCount(long long n) { return [RYGUtils formatCount:n shortened:srShort()]; }

static NSString *srDateText(NSDate *d) {
	if (!d) return nil;
	static NSDateFormatter *sameYear; static NSDateFormatter *otherYear; static dispatch_once_t once;
	dispatch_once(&once, ^{
		sameYear = [NSDateFormatter new];
		sameYear.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMM d" options:0 locale:[NSLocale currentLocale]];
		otherYear = [NSDateFormatter new];
		otherYear.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMM d, y" options:0 locale:[NSLocale currentLocale]];
	});
	NSInteger yNow = [[NSCalendar currentCalendar] component:NSCalendarUnitYear fromDate:[NSDate date]];
	NSInteger yD   = [[NSCalendar currentCalendar] component:NSCalendarUnitYear fromDate:d];
	return [(yNow == yD ? sameYear : otherYear) stringFromDate:d];
}


static id srObjIvar(id obj, const char *name) {
	if (!obj || !name) return nil;
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return nil;
	@try {
		id v = object_getIvar(obj, iv);
		return [v isKindOfClass:NSObject.class] ? v : nil;
	} @catch (__unused id e) { return nil; }
}
static long long srNumIvar(id obj, const char *name) {
	id v = srObjIvar(obj, name);
	return [v isKindOfClass:NSNumber.class] ? [v longLongValue] : -1;
}
static NSDate *srDateIvar(id obj, const char *name) {
	id v = srObjIvar(obj, name);
	return [v isKindOfClass:NSDate.class] ? v : nil;
}


static RYGChromeCanvas *srCapsule(NSInteger tag) {
	RYGChromeCanvas *canvas = [RYGChromeCanvas new];
	canvas.tag = tag;
	canvas.userInteractionEnabled = NO;
	canvas.translatesAutoresizingMaskIntoConstraints = YES;
	UIView *host = canvas.contentContainer;
	UIView *bg = [UIView new];
	bg.tag = kSRRowBgTag;
	bg.translatesAutoresizingMaskIntoConstraints = NO;
	bg.userInteractionEnabled = NO;
	bg.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
	bg.layer.cornerRadius = 7;
	bg.layer.cornerCurve = kCACornerCurveContinuous;
	[host addSubview:bg];
	[NSLayoutConstraint activateConstraints:@[
		[bg.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
		[bg.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
		[bg.topAnchor constraintEqualToAnchor:host.topAnchor],
		[bg.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
	]];
	return canvas;
}

static UIView *srEnsureRow(UIView *host, NSInteger tag, NSString *iconName) {
	UIView *row = [host viewWithTag:tag];
	if (row) return row;
	RYGChromeCanvas *canvas = srCapsule(tag);
	UIView *content = canvas.contentContainer;
	UIImageView *icon = [UIImageView new];
	icon.tag = 1;
	UIImage *img = [RYGIcon fbImageNamed:iconName] ?: [RYGIcon sfImageNamed:iconName];
	if (img) icon.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	icon.tintColor = UIColor.whiteColor;
	icon.contentMode = UIViewContentModeScaleAspectFit;
	[content addSubview:icon];
	UILabel *lbl = [UILabel new];
	lbl.tag = 2;
	lbl.textColor = UIColor.whiteColor;
	lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
	[content addSubview:lbl];
	[host addSubview:canvas];
	return canvas;
}

static void srPositionRow(UIView *row, NSString *text, CGFloat x, CGFloat y) {
	UILabel *lbl = (UILabel *)[row viewWithTag:2];
	UIImageView *icon = (UIImageView *)[row viewWithTag:1];
	if (!lbl || !icon) return;
	const CGFloat padH = 5, gap = 3, iconSize = 11, rowH = 15;
	lbl.text = text ?: @"";
	[lbl sizeToFit];
	CGFloat lblW = lbl.frame.size.width;
	icon.frame = CGRectMake(padH, (rowH - iconSize) / 2.0, iconSize, iconSize);
	lbl.frame = CGRectMake(padH + iconSize + gap, 0, lblW, rowH);
	row.frame = CGRectMake(x, y, padH * 2 + iconSize + gap + lblW, rowH);
	[row.superview bringSubviewToFront:row];
}

static void srClearRow(UIView *host, NSInteger tag) {
	UIView *r = [host viewWithTag:tag];
	if (r) [r removeFromSuperview];
}
static void srClearAll(UIView *host) {
	for (NSNumber *t in srAllTags()) srClearRow(host, [t integerValue]);
}

static UIView *srFindSubviewOfClass(UIView *root, Class cls) {
	if (!root || !cls) return nil;
	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
	while (stack.count) {
		UIView *v = stack.lastObject; [stack removeLastObject];
		if (v != root && [v isKindOfClass:cls]) return v;
		for (UIView *sv in v.subviews) [stack addObject:sv];
	}
	return nil;
}


// ---- media reads ----

static NSString *srNormalizePK(NSString *pk) {
	if (![pk isKindOfClass:NSString.class] || !pk.length) return nil;
	NSRange r = [pk rangeOfString:@"_"];
	return r.location == NSNotFound ? pk : [pk substringToIndex:r.location];
}
static NSString *srMediaPK(id media) {
	if (!media) return nil;
	id pk = [RYGUtils fieldCacheValue:media forKey:@"pk"];
	if ([pk isKindOfClass:NSString.class] && [pk length]) return srNormalizePK(pk);
	id v = srObjIvar(media, "_pk");
	if ([v isKindOfClass:NSString.class] && [v length]) return srNormalizePK(v);
	@try {
		id kv = [media valueForKey:@"pk"];
		if ([kv isKindOfClass:NSString.class] && [kv length]) return srNormalizePK(kv);
	} @catch (__unused id e) {}
	return nil;
}
static long long srMediaFC(id media, NSString *key) {
	if (!media) return -1;
	id fc = [RYGUtils fieldCacheValue:media forKey:key];
	return [fc isKindOfClass:NSNumber.class] ? [fc longLongValue] : -1;
}
static NSDate *srMediaTakenAt(id media) {
	if (!media) return nil;
	NSDate *d = srDateIvar(media, "_takenAt");
	if (d) return d;
	id fc = [RYGUtils fieldCacheValue:media forKey:@"taken_at"];
	if ([fc isKindOfClass:NSNumber.class]) return [NSDate dateWithTimeIntervalSince1970:[fc doubleValue]];
	if ([fc isKindOfClass:NSDate.class]) return fc;
	return nil;
}


// ---- batched /media/infos/ backfill ----

static NSMutableDictionary<NSString *, NSDictionary *> *srInfoCache(void) {
	static NSMutableDictionary *d; static dispatch_once_t once;
	dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
	return d;
}
static NSMutableSet<NSString *> *srInflight(void) {
	static NSMutableSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}
static NSMutableOrderedSet<NSString *> *srPending(void) {
	static NSMutableOrderedSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableOrderedSet new]; });
	return s;
}
static dispatch_block_t srFlushBlock = nil;
static BOOL srBatchInFlight = NO;
static const NSUInteger kSRBatchMax = 50;
static const NSTimeInterval kSRPause = 0.25;

static void srFlush(void);
static void srScheduleFlush(void) {
	if (srFlushBlock) { dispatch_block_cancel(srFlushBlock); srFlushBlock = nil; }
	dispatch_block_t b = dispatch_block_create((dispatch_block_flags_t)0, ^{ srFlushBlock = nil; srFlush(); });
	srFlushBlock = b;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSRPause * NSEC_PER_SEC)), dispatch_get_main_queue(), b);
}
static void srScheduleFetch(NSString *pk) {
	if (!pk.length || !srFetchMissing()) return;
	NSMutableDictionary *cache = srInfoCache();
	@synchronized(cache) {
		if (cache[pk]) return;
		if ([srInflight() containsObject:pk]) return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		if (![srPending() containsObject:pk]) [srPending() addObject:pk];
		srScheduleFlush();
	});
}

static void srKickVisible(void);
static void srDropOffscreenPending(void);

static void srFlush(void) {
	if (srBatchInFlight) { srScheduleFlush(); return; }
	srDropOffscreenPending();
	NSMutableOrderedSet *pending = srPending();
	if (!pending.count) return;
	NSRange r = NSMakeRange(0, MIN(kSRBatchMax, pending.count));
	NSArray *batch = [[pending array] subarrayWithRange:r];
	[pending removeObjectsInRange:r];
	NSMutableDictionary *cache = srInfoCache();
	@synchronized(cache) { [srInflight() addObjectsFromArray:batch]; }
	srBatchInFlight = YES;
	[RYGInstagramAPI fetchMediaInfosForMediaIds:batch completion:^(NSDictionary *resp, NSError *err) {
		NSArray *items = [resp[@"items"] isKindOfClass:NSArray.class] ? resp[@"items"] : @[];
		@synchronized(cache) {
			for (NSDictionary *item in items) {
				if (![item isKindOfClass:NSDictionary.class]) continue;
				id pkVal = item[@"pk"] ?: item[@"id"];
				NSString *pk = srNormalizePK([pkVal isKindOfClass:NSString.class] ? pkVal : [pkVal description]);
				if (!pk.length) continue;
				long long likes = [item[@"like_count"] isKindOfClass:NSNumber.class] ? [item[@"like_count"] longLongValue] : -1;
				id pc = item[@"play_count"] ?: item[@"view_count"];
				long long plays = [pc isKindOfClass:NSNumber.class] ? [pc longLongValue] : -1;
				long long comments = [item[@"comment_count"] isKindOfClass:NSNumber.class] ? [item[@"comment_count"] longLongValue] : -1;
				long long shares = [item[@"reshare_count"] isKindOfClass:NSNumber.class] ? [item[@"reshare_count"] longLongValue] : -1;
				long long reposts = [item[@"media_repost_count"] isKindOfClass:NSNumber.class] ? [item[@"media_repost_count"] longLongValue] : -1;
				NSDate *taken = [item[@"taken_at"] isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[item[@"taken_at"] doubleValue]] : nil;
				cache[pk] = @{ @"likes": @(likes), @"plays": @(plays), @"comments": @(comments), @"shares": @(shares), @"reposts": @(reposts), @"takenAt": taken ?: [NSNull null] };
			}
			for (NSString *pk in batch) if (!cache[pk]) cache[pk] = @{ @"likes": @(-1), @"plays": @(-1), @"comments": @(-1), @"shares": @(-1), @"reposts": @(-1), @"takenAt": [NSNull null] };
			[srInflight() minusSet:[NSSet setWithArray:batch]];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			srBatchInFlight = NO;
			srKickVisible();
			if (srPending().count) srScheduleFlush();
		});
	}];
}


// ---- render ----

static BOOL srIsOurMediaCell(UIView *v) {
	static Class a, b, c; static dispatch_once_t once;
	dispatch_once(&once, ^{
		a = NSClassFromString(@"IGMediaThumbnailCell");
		b = NSClassFromString(@"IGDiscoveryGridTopReelsCell");
		c = NSClassFromString(@"IGDiscoveryGridFeedItemVideoCell");
	});
	return (a && [v isKindOfClass:a]) || (b && [v isKindOfClass:b]) || (c && [v isKindOfClass:c]);
}
static void srCollectCells(UIView *v, NSMutableArray *out) {
	if (srIsOurMediaCell(v)) [out addObject:v];
	for (UIView *sv in v.subviews) srCollectCells(sv, out);
}
static NSArray *srVisibleCells(void) {
	NSMutableArray *cells = [NSMutableArray array];
	for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows) if (!w.hidden) srCollectCells(w, cells);
	}
	return cells;
}
static void srKickVisible(void) {
	for (UIView *c in srVisibleCells()) if (c.window) [c setNeedsLayout];
}
static void srDropOffscreenPending(void) {
	NSMutableOrderedSet *pending = srPending();
	if (!pending.count) return;
	NSMutableSet *visible = [NSMutableSet set];
	for (UIView *c in srVisibleCells()) {
		if (!c.window) continue;
		NSString *pk = objc_getAssociatedObject(c, kSRPKKey);
		if (pk.length) [visible addObject:pk];
	}
	NSMutableArray *drop = [NSMutableArray array];
	for (NSString *pk in pending) if (![visible containsObject:pk]) [drop addObject:pk];
	if (drop.count) [pending removeObjectsInArray:drop];
}

// host = cell we hang capsules on; metadata may be nil (reels); media = IGMedia.
static void srRender(UIView *host, id metadata, id media) {
	if (!srEnabled()) { srClearAll(host); return; }

	NSString *pk = srMediaPK(media);
	objc_setAssociatedObject(host, kSRPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);

	long long views = metadata ? srNumIvar(metadata, "_viewCount_viewCount") : -1;
	if (views < 0 && metadata) views = srNumIvar(metadata, "_playCount_playCount");
	if (views < 0 && metadata) views = srNumIvar(metadata, "_playCountAndTimestamp_playCount");
	if (views < 0) { views = srMediaFC(media, @"play_count"); if (views < 0) views = srMediaFC(media, @"view_count"); }

	long long likes = metadata ? srNumIvar(metadata, "_likeCount_likeCount") : -1;
	if (likes < 0) likes = srMediaFC(media, @"like_count");
	long long comments = srMediaFC(media, @"comment_count");
	long long shares   = srMediaFC(media, @"reshare_count");
	long long reposts  = srMediaFC(media, @"media_repost_count");
	NSDate *date = metadata ? (srDateIvar(metadata, "_timestamp_postDate") ?: srDateIvar(metadata, "_playCountAndTimestamp_postDate")) : nil;
	if (!date) date = srMediaTakenAt(media);

	NSDictionary *cached = pk.length ? srInfoCache()[pk] : nil;
	if (cached) {
		if (views < 0)    { long long v = [cached[@"plays"] longLongValue];    if (v >= 0) views = v; }
		if (likes < 0)    { long long v = [cached[@"likes"] longLongValue];    if (v >= 0) likes = v; }
		if (comments < 0) { long long v = [cached[@"comments"] longLongValue]; if (v >= 0) comments = v; }
		if (shares < 0)   { long long v = [cached[@"shares"] longLongValue];   if (v >= 0) shares = v; }
		if (reposts < 0)  { long long v = [cached[@"reposts"] longLongValue];  if (v >= 0) reposts = v; }
		if (!date) { id t = cached[@"takenAt"]; if ([t isKindOfClass:NSDate.class]) date = t; }
	}

	BOOL needFetch = pk.length && !cached &&
		((srShowViews() && views < 0) || (srShowLikes() && likes < 0) || (srShowComments() && comments < 0)
		 || (srShowShares() && shares < 0) || (srShowReposts() && reposts < 0) || (srShowDate() && !date));

	if (needFetch) srScheduleFetch(pk);

	NSString *dateTxt = srDateText(date);
	NSDictionary *textByMetric = @{
		@"views":    (views > 0)    ? srCount(views)    : [NSNull null],
		@"likes":    (likes > 0)    ? srCount(likes)    : [NSNull null],
		@"comments": (comments > 0) ? srCount(comments) : [NSNull null],
		@"shares":   (shares > 0)   ? srCount(shares)   : [NSNull null],
		@"reposts":  (reposts > 0)  ? srCount(reposts)  : [NSNull null],
		@"date":     (dateTxt.length) ? dateTxt         : [NSNull null],
	};

	Class countLabelCls = NSClassFromString(@"IGVideoIconCountLabel");
	UIView *nativeLabel = countLabelCls ? srFindSubviewOfClass(host, countLabelCls) : nil;
	CGRect anchor = (nativeLabel && nativeLabel.frame.size.height > 1) ? [nativeLabel convertRect:nativeLabel.bounds toView:host] : CGRectZero;
	BOOL haveAnchor = anchor.size.height > 1;

	// Only restyle views into a pill when we can hide IG's own label, else leave
	// IG's native count so we never double it or hide it with nothing to show.
	BOOL drawingViews = srMetricOn(@"views") && [textByMetric[@"views"] isKindOfClass:NSString.class] && nativeLabel != nil;
	if (nativeLabel) nativeLabel.hidden = drawingViews;

	const CGFloat rowH = 15, rowGap = 3;
	CGFloat x = haveAnchor ? anchor.origin.x : 8;
	CGFloat bottomY = haveAnchor ? anchor.origin.y : (host.bounds.size.height - (rowH + 8));

	CGFloat y = bottomY;
	for (NSString *m in [srMetricOrder() reverseObjectEnumerator]) {
		BOOL isViews = [m isEqualToString:@"views"];
		id text = textByMetric[m];
		if (srMetricOn(m) && (!isViews || drawingViews) && [text isKindOfClass:NSString.class]) {
			UIView *row = srEnsureRow(host, srTagFor(m), srIconFor(m));
			srPositionRow(row, text, x, y);
			y -= (rowH + rowGap);
		} else {
			srClearRow(host, srTagFor(m));
		}
	}
}


// ---- hooks ----

// Profile grids are owned by ProfileReelCardDetails — skip them here.
static BOOL srIsProfileCell(id cell) {
	static Class prof; static dispatch_once_t once;
	dispatch_once(&once, ^{ prof = NSClassFromString(@"IGMediaThumbnailSectionController"); });
	id delegate = srObjIvar(cell, "_delegate");
	return prof && [delegate isKindOfClass:prof];
}
static id srMediaFromThumbCell(id cell) {
	id delegate = srObjIvar(cell, "_delegate");
	id gridItem = srObjIvar(delegate, "_gridItem");
	id media = srObjIvar(gridItem, "_model");
	if (media) return media;
	// SERP / other section controllers keep the media elsewhere — probe common ivars.
	media = srObjIvar(delegate, "_media") ?: srObjIvar(delegate, "_model");
	if ([media isKindOfClass:NSClassFromString(@"IGMedia")]) return media;
	@try { id kv = [delegate valueForKey:@"media"]; if ([kv isKindOfClass:NSClassFromString(@"IGMedia")]) return kv; } @catch (__unused id e) {}
	return nil;
}

static void (*orig_thumb_layout)(id, SEL);
static void new_thumb_layout(id self, SEL _cmd) {
	orig_thumb_layout(self, _cmd);
	UIView *host = (UIView *)self;
	if (!srEnabled() || srIsProfileCell(self)) { srClearAll(host); return; }
	srRender(host, srObjIvar(self, "_metadata"), srMediaFromThumbCell(self));
}

static id srMediaFromReelsCell(id cell) {
	id model = srObjIvar(cell, "_model");
	id media = srObjIvar(model, "media");
	return media;
}
static void srRenderVideoCell(id self) {
	UIView *host = (UIView *)self;
	if (!srEnabled()) { srClearAll(host); return; }
	srRender(host, nil, srMediaFromReelsCell(self));
}

static void (*orig_reels_layout)(id, SEL);
static void new_reels_layout(id self, SEL _cmd) {
	orig_reels_layout(self, _cmd);
	srRenderVideoCell(self);
}

static void (*orig_feeditem_layout)(id, SEL);
static void new_feeditem_layout(id self, SEL _cmd) {
	orig_feeditem_layout(self, _cmd);
	srRenderVideoCell(self);
}


static NSMutableSet *srHookedKeys(void) {
	static NSMutableSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}
static void srHookIfPresent(NSString *clsName, SEL sel, IMP newImp, IMP *origStore) {
	NSString *key = [NSString stringWithFormat:@"%@|%@", clsName, NSStringFromSelector(sel)];
	if ([srHookedKeys() containsObject:key]) return;
	Class c = NSClassFromString(clsName);
	if (!c) return;
	MSHookMessageEx(c, sel, newImp, origStore);
	[srHookedKeys() addObject:key];
}
static void srTryAttach(void) {
	srHookIfPresent(@"IGMediaThumbnailCell", @selector(layoutSubviews), (IMP)new_thumb_layout, (IMP *)&orig_thumb_layout);
	srHookIfPresent(@"IGDiscoveryGridTopReelsCell", @selector(layoutSubviews), (IMP)new_reels_layout, (IMP *)&orig_reels_layout);
	srHookIfPresent(@"IGDiscoveryGridFeedItemVideoCell", @selector(layoutSubviews), (IMP)new_feeditem_layout, (IMP *)&orig_feeditem_layout);
}

%ctor {
	@autoreleasepool {
		if (!srEnabled()) return;
		srTryAttach();
		[[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification object:nil queue:nil
		                                              usingBlock:^(NSNotification *note) { srTryAttach(); }];
		for (int delay = 1; delay <= 10; delay++) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ srTryAttach(); });
		}
	}
}
