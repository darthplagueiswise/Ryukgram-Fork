// Profile post/reel card overlays — views, likes, comments, shares, reposts,
// date. Which stats show and their order are user-configurable.
//
// Reels (IGSundialGridVideoCell) already has IG's _playCountLabel — retext it,
// add a capsule. Posts (IGMediaThumbnailCell) has no label, draw our own row.
//
// Missing counts refetch via batched /media/infos/, debounced so we don't hit
// cards the user flies past.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGIcon.h"
#import "../../Networking/RYGInstagramAPI.h"
#import <substrate.h>
#import <objc/runtime.h>

static const NSInteger kRYGViewsRowTag      = 0x52435601;
static const NSInteger kRYGLikesRowTag      = 0x52434C01;
static const NSInteger kRYGDateRowTag       = 0x52434401;
static const NSInteger kRYGCommentsRowTag   = 0x52434301;
static const NSInteger kRYGSharesRowTag      = 0x52435301;
static const NSInteger kRYGRepostsRowTag    = 0x52435201;
static const NSInteger kRYGViewsBackdropTag = 0x52435602;

static const void *kRYGThumbCellMediaKey = &kRYGThumbCellMediaKey;
static const void *kRYGThumbCellPKKey    = &kRYGThumbCellPKKey;

static BOOL rygFullViews(void)    { return [RYGUtils getBoolPref:@"reel_card_full_views"]; }
static BOOL rygShowLikes(void)    { return [RYGUtils getBoolPref:@"reel_card_show_likes"]; }
static BOOL rygShowDate(void)     { return [RYGUtils getBoolPref:@"reel_card_show_date"]; }
static BOOL rygShowComments(void) { return [RYGUtils getBoolPref:@"reel_card_show_comments"]; }
static BOOL rygShowShares(void)   { return [RYGUtils getBoolPref:@"reel_card_show_shares"]; }
static BOOL rygShowReposts(void)  { return [RYGUtils getBoolPref:@"reel_card_show_reposts"]; }
static BOOL rygMasterOn(void)     { return [RYGUtils getBoolPref:@"reel_card_master_enabled"]; }
static BOOL rygFetchMissing(void) { return [RYGUtils getBoolPref:@"reel_card_fetch_missing"]; }
static BOOL rygShortNumbers(void) { return [RYGUtils getBoolPref:@"reel_card_shortened_numbers"]; }
static BOOL rygAnyMetricOn(void) { return rygFullViews() || rygShowLikes() || rygShowDate()
	|| rygShowComments() || rygShowShares() || rygShowReposts(); }
static BOOL rygAnyOn(void) { return rygMasterOn() && rygAnyMetricOn(); }

static BOOL rygMetricEnabled(NSString *m) {
	if ([m isEqualToString:@"views"])    return rygFullViews();
	if ([m isEqualToString:@"likes"])    return rygShowLikes();
	if ([m isEqualToString:@"comments"]) return rygShowComments();
	if ([m isEqualToString:@"shares"])   return rygShowShares();
	if ([m isEqualToString:@"reposts"])  return rygShowReposts();
	if ([m isEqualToString:@"date"])     return rygShowDate();
	return NO;
}

static NSInteger rygTagForMetric(NSString *m) {
	if ([m isEqualToString:@"views"])    return kRYGViewsRowTag;
	if ([m isEqualToString:@"likes"])    return kRYGLikesRowTag;
	if ([m isEqualToString:@"comments"]) return kRYGCommentsRowTag;
	if ([m isEqualToString:@"shares"])   return kRYGSharesRowTag;
	if ([m isEqualToString:@"reposts"])  return kRYGRepostsRowTag;
	if ([m isEqualToString:@"date"])     return kRYGDateRowTag;
	return 0;
}

static NSString *rygIconForMetric(NSString *m) {
	if ([m isEqualToString:@"views"])    return @"ig_icon_eye_outline_12";
	if ([m isEqualToString:@"likes"])    return @"direct-like";
	if ([m isEqualToString:@"comments"]) return @"ig_icon_comment_outline_24";
	if ([m isEqualToString:@"shares"])   return @"ig_icon_direct_prism_outline_24";
	if ([m isEqualToString:@"reposts"])  return @"ig_icon_reshare_outline_24";
	if ([m isEqualToString:@"date"])     return @"clock-small";
	return @"";
}

static NSArray<NSString *> *RYGReelCardCanonMetrics(void) {
	return @[@"views", @"likes", @"comments", @"shares", @"reposts", @"date"];
}

static NSArray<NSString *> *RYGReelCardMetricOrder(void) {
	NSString *raw = [RYGUtils getStringPref:@"reel_card_order"] ?: @"";
	NSArray<NSString *> *canon = RYGReelCardCanonMetrics();
	NSMutableArray<NSString *> *out = [NSMutableArray array];
	for (NSString *p in [raw componentsSeparatedByString:@","]) {
		NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([canon containsObject:t] && ![out containsObject:t]) [out addObject:t];
	}
	for (NSString *c in canon) if (![out containsObject:c]) [out addObject:c];
	return out;
}


static NSString *rygCount(long long n) {
	return [RYGUtils formatCount:n shortened:rygShortNumbers()];
}

static NSString *rygDateText(NSDate *d) {
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


static id rygObjIvar(id obj, const char *name) {
	if (!obj || !name) return nil;
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return nil;
	const char *enc = ivar_getTypeEncoding(iv);
	if (!enc || enc[0] != '@') return nil;
	@try { return object_getIvar(obj, iv); } @catch (__unused id e) { return nil; }
}

static long long rygLLIvar(id obj, const char *name) {
	if (!obj || !name) return 0;
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return 0;
	const char *enc = ivar_getTypeEncoding(iv);
	if (!enc) return 0;
	ptrdiff_t off = ivar_getOffset(iv);
	void *base = (__bridge void *)obj;
	if (enc[0] == 'q') return *(long long *)((char *)base + off);
	if (enc[0] == 'Q') return (long long) *(unsigned long long *)((char *)base + off);
	return 0;
}

static long long rygMediaLikes(id media) {
	if (!media) return 0;
	Ivar iv = class_getInstanceVariable([media class], "_likeCount");
	if (iv) {
		const char *enc = ivar_getTypeEncoding(iv);
		if (enc && (enc[0] == 'q' || enc[0] == 'Q')) {
			long long n = rygLLIvar(media, "_likeCount");
			if (n > 0) return n;
		}
	}
	id fc = [RYGUtils fieldCacheValue:media forKey:@"like_count"];
	if ([fc isKindOfClass:NSNumber.class]) return [fc longLongValue];
	@try {
		id v = [media valueForKey:@"likeCount"];
		if ([v isKindOfClass:NSNumber.class]) return [v longLongValue];
	} @catch (__unused id e) {}
	return 0;
}

static long long rygMediaFCCount(id media, NSString *key) {
	if (!media) return -1;
	id fc = [RYGUtils fieldCacheValue:media forKey:key];
	if ([fc isKindOfClass:NSNumber.class]) return [fc longLongValue];
	return -1;
}

static long long rygMediaPlayCount(id media) {
	if (!media) return 0;
	id fc = [RYGUtils fieldCacheValue:media forKey:@"play_count"];
	if ([fc isKindOfClass:NSNumber.class]) return [fc longLongValue];
	fc = [RYGUtils fieldCacheValue:media forKey:@"view_count"];
	if ([fc isKindOfClass:NSNumber.class]) return [fc longLongValue];
	id v = rygObjIvar(media, "_playCount");
	if ([v isKindOfClass:NSNumber.class]) return [v longLongValue];
	return 0;
}

static NSDate *rygMediaTakenAt(id media) {
	if (!media) return nil;
	id v = rygObjIvar(media, "_takenAt");
	if ([v isKindOfClass:NSDate.class]) return v;
	id fc = [RYGUtils fieldCacheValue:media forKey:@"taken_at"];
	if ([fc isKindOfClass:NSNumber.class]) return [NSDate dateWithTimeIntervalSince1970:[fc doubleValue]];
	if ([fc isKindOfClass:NSDate.class]) return fc;
	@try {
		id k = [media valueForKey:@"takenAt"];
		if ([k isKindOfClass:NSDate.class]) return k;
		if ([k isKindOfClass:NSNumber.class]) return [NSDate dateWithTimeIntervalSince1970:[k doubleValue]];
	} @catch (__unused id e) {}
	return nil;
}


static UIView *rygHostForCell(UIView *cell) {
	if ([cell isKindOfClass:[UICollectionViewCell class]]) {
		return ((UICollectionViewCell *)cell).contentView;
	}
	return cell;
}

static const NSInteger kRYGRowBgTag = 3;

// Dark rounded capsule with its fill inside an RYGChromeCanvas so Hide UI on
// Capture redacts it. Caller drives the frame; icons/labels go in -contentContainer.
static RYGChromeCanvas *rygChromeCapsule(NSInteger tag) {
	RYGChromeCanvas *canvas = [RYGChromeCanvas new];
	canvas.tag = tag;
	canvas.userInteractionEnabled = NO;
	canvas.translatesAutoresizingMaskIntoConstraints = YES;

	UIView *host = canvas.contentContainer;

	UIView *bg = [[UIView alloc] init];
	bg.tag = kRYGRowBgTag;
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

static UIView *rygEnsureRow(UIView *cell, NSInteger tag, NSString *iconName) {
	UIView *host = rygHostForCell(cell);
	UIView *row = [host viewWithTag:tag];
	if (row) return row;

	RYGChromeCanvas *canvas = rygChromeCapsule(tag);
	UIView *content = canvas.contentContainer;

	UIImageView *icon = [[UIImageView alloc] init];
	icon.tag = 1;
	UIImage *img = [RYGIcon fbImageNamed:iconName] ?: [RYGIcon sfImageNamed:iconName];
	if (img) icon.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	icon.tintColor = UIColor.whiteColor;
	icon.contentMode = UIViewContentModeScaleAspectFit;
	[content addSubview:icon];

	UILabel *lbl = [[UILabel alloc] init];
	lbl.tag = 2;
	lbl.textColor = UIColor.whiteColor;
	lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
	[content addSubview:lbl];

	[host addSubview:canvas];
	return canvas;
}

static void rygPositionRow(UIView *row, NSString *text, CGFloat x, CGFloat y) {
	UILabel *lbl = (UILabel *)[row viewWithTag:2];
	UIImageView *icon = (UIImageView *)[row viewWithTag:1];
	if (!lbl || !icon) return;

	const CGFloat padH = 5;
	const CGFloat gap = 3;
	const CGFloat iconSize = 11;
	const CGFloat rowH = 15;

	lbl.text = text ?: @"";
	[lbl sizeToFit];
	CGFloat lblW = lbl.frame.size.width;

	icon.frame = CGRectMake(padH, (rowH - iconSize) / 2.0, iconSize, iconSize);
	lbl.frame = CGRectMake(padH + iconSize + gap, 0, lblW, rowH);

	row.frame = CGRectMake(x, y, padH * 2 + iconSize + gap + lblW, rowH);
	[row.superview bringSubviewToFront:row];
}

static void rygClearRow(UIView *cellView, NSInteger tag) {
	UIView *r = [cellView viewWithTag:tag];
	if (r) [r removeFromSuperview];
}

// Stacks enabled metric rows upward from firstY (bottom row at firstY).
static void rygStackRows(UIView *cellView, CGFloat x, CGFloat firstY,
                         CGFloat rowH, CGFloat rowGap, NSArray<NSDictionary *> *specs) {
	CGFloat y = firstY;
	for (NSDictionary *s in specs) {
		UIView *row = rygEnsureRow(cellView, [s[@"tag"] integerValue], s[@"icon"]);
		rygPositionRow(row, s[@"text"], x, y);
		y -= (rowH + rowGap);
	}
}

// Capsule sibling sitting just below IG's own _playCountLabel in z-order.
static void rygEnsureViewsBackdrop(UIView *target) {
	if (!target || !target.superview) return;
	UIView *superview = target.superview;
	UIView *backdrop = [superview viewWithTag:kRYGViewsBackdropTag];
	if (!backdrop) {
		backdrop = rygChromeCapsule(kRYGViewsBackdropTag);
	}
	CGRect tf = target.frame;
	const CGFloat padH = 5;
	const CGFloat padV = 1;
	backdrop.frame = CGRectMake(tf.origin.x - padH,
	                            tf.origin.y - padV,
	                            tf.size.width + padH * 2,
	                            tf.size.height + padV * 2);
	[superview insertSubview:backdrop belowSubview:target];
}

static void rygRemoveViewsBackdrop(UIView *cell) {
	UIView *b = [cell.superview viewWithTag:kRYGViewsBackdropTag];
	if (b) [b removeFromSuperview];
	UIView *b2 = [cell viewWithTag:kRYGViewsBackdropTag];
	if (b2) [b2 removeFromSuperview];
}


// IG 433 dropped the cell's _mediaAccess ivar — media lives on the owning
// section controller now (_video); our SC hook also binds it to the cell.
static id rygMediaForGridCell(id cell) {
	id m = rygObjIvar(cell, "_mediaAccess");
	if (m) return m;
	m = rygObjIvar(rygObjIvar(cell, "_delegate"), "_video");
	if (m) return m;
	return objc_getAssociatedObject(cell, kRYGThumbCellMediaKey);
}

static NSString *rygMediaPK(id media);
static NSString *rygNormalizePK(NSString *pk);
static NSMutableDictionary<NSString *, NSDictionary *> *rygInfoCache(void);
static void rygScheduleFetchForPK(NSString *pk);

static void (*orig_gridCell_layoutSubviews)(id, SEL);
static void new_gridCell_layoutSubviews(id self, SEL _cmd) {
	orig_gridCell_layoutSubviews(self, _cmd);

	UIView *cellView = (UIView *)self;

	if (!rygAnyOn()) {
		rygClearRow(cellView, kRYGLikesRowTag);
		rygClearRow(cellView, kRYGCommentsRowTag);
		rygClearRow(cellView, kRYGSharesRowTag);
		rygClearRow(cellView, kRYGRepostsRowTag);
		rygClearRow(cellView, kRYGDateRowTag);
		rygRemoveViewsBackdrop(cellView);
		return;
	}

	id media     = rygMediaForGridCell(self);
	id playLabel = rygObjIvar(self, "_playCountLabel");

	NSString *pk = rygMediaPK(media);
	if (!pk.length) {
		id raw = rygObjIvar(self, "_mediaPK");
		if ([raw isKindOfClass:NSString.class]) pk = rygNormalizePK(raw);
	}
	if (pk.length) {
		NSString *cur = objc_getAssociatedObject(self, kRYGThumbCellPKKey);
		if (![cur isEqualToString:pk]) {
			objc_setAssociatedObject(self, kRYGThumbCellPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
		}
	}

	if (rygFullViews() && playLabel) {
		long long count = rygLLIvar(playLabel, "_count");
		UILabel *inner = (UILabel *)rygObjIvar(playLabel, "_label");
		if (count > 0 && inner) {
			NSString *txt = rygCount(count);
			if (![inner.text isEqualToString:txt]) {
				inner.text = txt;
				[inner sizeToFit];
				CGRect lf = inner.frame; lf.origin = CGPointMake(16, 0); inner.frame = lf;
				UIView *pv = (UIView *)playLabel;
				CGRect pf = pv.frame; pf.size.width = 16 + lf.size.width; pv.frame = pf;
			}
		}
	}

	UIView *pv = (UIView *)playLabel;
	UILabel *innerLbl = (UILabel *)rygObjIvar(playLabel, "_label");
	BOOL pvHasFrame = pv && pv.frame.size.width > 4 && pv.frame.size.height > 4;
	BOOL innerHasText = innerLbl && innerLbl.text.length > 0 && !innerLbl.hidden;
	BOOL viewsVisible = (pvHasFrame && !pv.hidden && pv.alpha > 0.05
	                     && rygLLIvar(playLabel, "_count") > 0
	                     && innerHasText);

	if (viewsVisible) rygEnsureViewsBackdrop(pv);
	else              rygRemoveViewsBackdrop(cellView);

	const CGFloat capsulePadH = 5;
	const CGFloat rowH = 15;
	const CGFloat rowGap = 3;
	// Align our rows with the capsule's left edge — IG's label sits at
	// pv.origin.x but the backdrop extends padH to its left.
	CGFloat x = pvHasFrame ? (pv.frame.origin.x - capsulePadH) : 8;
	CGFloat bottomSlotY = pvHasFrame ? pv.frame.origin.y : (cellView.bounds.size.height - (rowH + 8));
	CGFloat yAboveBottom = bottomSlotY - (rowH + rowGap);

	long long likes = rygMediaLikes(media);
	BOOL hasLikes = likes > 0
		|| (media && [[RYGUtils fieldCacheValue:media forKey:@"like_count"] isKindOfClass:NSNumber.class]);
	long long comments = rygMediaFCCount(media, @"comment_count"); BOOL hasComments = comments >= 0;
	long long shares   = rygMediaFCCount(media, @"reshare_count");  BOOL hasShares   = shares >= 0;
	long long reposts  = rygMediaFCCount(media, @"media_repost_count"); BOOL hasReposts = reposts >= 0;
	NSDate *date = rygMediaTakenAt(media);
	BOOL hasDate = (date != nil);

	NSDictionary *cached = pk.length ? rygInfoCache()[pk] : nil;
	if (cached) {
		if (!hasLikes) { long long v = [cached[@"likes"] longLongValue]; if (v >= 0) { likes = v; hasLikes = YES; } }
		if (!hasComments) { long long v = [cached[@"comments"] longLongValue]; if (v >= 0) { comments = v; hasComments = YES; } }
		if (!hasShares) { long long v = [cached[@"shares"] longLongValue]; if (v >= 0) { shares = v; hasShares = YES; } }
		if (!hasReposts) { long long v = [cached[@"reposts"] longLongValue]; if (v >= 0) { reposts = v; hasReposts = YES; } }
		if (!hasDate) { id t = cached[@"takenAt"]; if ([t isKindOfClass:NSDate.class]) { date = t; hasDate = YES; } }
	} else if (pk.length && ((rygShowLikes() && !hasLikes) || (rygShowDate() && !hasDate)
	           || (rygShowComments() && !hasComments) || (rygShowShares() && !hasShares)
	           || (rygShowReposts() && !hasReposts))) {
		rygScheduleFetchForPK(pk);
	}

	NSString *dateTxt = rygDateText(date);
	NSDictionary<NSString *, id> *textByMetric = @{
		@"likes":    (hasLikes && likes > 0) ? rygCount(likes) : [NSNull null],
		@"comments": (hasComments && comments > 0) ? rygCount(comments) : [NSNull null],
		@"shares":   (hasShares && shares > 0) ? rygCount(shares) : [NSNull null],
		@"reposts":  (hasReposts && reposts > 0) ? rygCount(reposts) : [NSNull null],
		@"date":     (dateTxt.length) ? dateTxt : [NSNull null],
	};
	NSMutableArray<NSDictionary *> *specs = [NSMutableArray array];
	for (NSString *m in [RYGReelCardMetricOrder() reverseObjectEnumerator]) {
		if ([m isEqualToString:@"views"]) continue;
		id text = textByMetric[m];
		if (rygMetricEnabled(m) && [text isKindOfClass:NSString.class]) {
			[specs addObject:@{ @"tag": @(rygTagForMetric(m)), @"icon": rygIconForMetric(m), @"text": text }];
		} else {
			rygClearRow(cellView, rygTagForMetric(m));
		}
	}

	rygStackRows(cellView, x, viewsVisible ? yAboveBottom : bottomSlotY, rowH, rowGap, specs);
}

static void (*orig_gridCell_prepareForReuse)(id, SEL);
static void new_gridCell_prepareForReuse(id self, SEL _cmd) {
	objc_setAssociatedObject(self, kRYGThumbCellMediaKey, nil, OBJC_ASSOCIATION_ASSIGN);
	objc_setAssociatedObject(self, kRYGThumbCellPKKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
	orig_gridCell_prepareForReuse(self, _cmd);
}

static id (*orig_gridSC_cellForItemAtIndex)(id, SEL, NSInteger);
static id new_gridSC_cellForItemAtIndex(id self, SEL _cmd, NSInteger index) {
	id cell = orig_gridSC_cellForItemAtIndex(self, _cmd, index);
	if (!cell) return cell;
	id media = rygObjIvar(self, "_video");
	if (!media) {
		NSArray *list = rygObjIvar(self, "_mediaList");
		if ([list isKindOfClass:NSArray.class] && index >= 0 && (NSUInteger)index < list.count) media = list[index];
	}
	if (media) {
		objc_setAssociatedObject(cell, kRYGThumbCellMediaKey, media, OBJC_ASSOCIATION_ASSIGN);
		NSString *pk = rygMediaPK(media);
		if (pk.length) {
			objc_setAssociatedObject(cell, kRYGThumbCellPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
		}
		[cell setNeedsLayout];
	}
	return cell;
}


// `_media` lags behind on cell reuse; the IGListKit object is authoritative.
static id rygCurrentMediaForSC(id sc) {
	if (!sc) return nil;
	@try {
		id obj = [sc valueForKey:@"object"];
		if (obj) return obj;
	} @catch (__unused id e) {}
	return rygObjIvar(sc, "_media");
}

// IGMedia stores pks as "<mediaPK>_<userPK>"; /media/infos/ returns bare pk.
// Normalize everything to bare so cache lookups line up.
static NSString *rygNormalizePK(NSString *pk) {
	if (![pk isKindOfClass:NSString.class] || !pk.length) return nil;
	NSRange r = [pk rangeOfString:@"_"];
	return r.location == NSNotFound ? pk : [pk substringToIndex:r.location];
}

static NSString *rygMediaPK(id media) {
	if (!media) return nil;
	id pk = [RYGUtils fieldCacheValue:media forKey:@"pk"];
	if ([pk isKindOfClass:NSString.class] && [(NSString *)pk length]) return rygNormalizePK(pk);
	@try {
		id v = [media valueForKey:@"pk"];
		if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return rygNormalizePK(v);
	} @catch (__unused id e) {}
	return nil;
}

// In-memory only — fresh counts on every session. Scroll-pause gated so we
// don't fire requests for cards the user flies past.
static NSMutableDictionary<NSString *, NSDictionary *> *rygInfoCache(void) {
	static NSMutableDictionary *d; static dispatch_once_t once;
	dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
	return d;
}

static NSMutableSet<NSString *> *rygInflight(void) {
	static NSMutableSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}

static NSMutableOrderedSet<NSString *> *rygPending(void) {
	static NSMutableOrderedSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableOrderedSet new]; });
	return s;
}

static dispatch_block_t rygPendingFlushBlock = nil;
static BOOL rygBatchInFlight = NO;
static const NSUInteger kRYGBatchMaxPKs = 50;
static const NSTimeInterval kRYGScrollPauseDelay = 0.2;

static void rygFlushPendingBatch(void);

static BOOL rygIsCardCell(UIView *v) {
	static Class thumbCls; static Class gridCls; static dispatch_once_t once;
	dispatch_once(&once, ^{
		thumbCls = NSClassFromString(@"IGMediaThumbnailCell");
		gridCls  = NSClassFromString(@"IGSundialGridVideoCell");
	});
	return (thumbCls && [v isKindOfClass:thumbCls]) || (gridCls && [v isKindOfClass:gridCls]);
}

static void rygEnumerateCardCells(void (^block)(UIView *cell, NSString *pk)) {
	for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) continue;
		for (UIWindow *win in ((UIWindowScene *)scene).windows) {
			NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:win];
			while (stack.count) {
				UIView *v = stack.lastObject; [stack removeLastObject];
				if (rygIsCardCell(v)) {
					block(v, objc_getAssociatedObject(v, kRYGThumbCellPKKey));
				}
				for (UIView *sv in v.subviews) [stack addObject:sv];
			}
		}
	}
}

static void rygKickAllVisibleCards(void) {
	rygEnumerateCardCells(^(UIView *cell, NSString *pk) {
		if (cell.window) [cell setNeedsLayout];
	});
}

static void rygScheduleFlushAfterPause(void) {
	if (rygPendingFlushBlock) {
		dispatch_block_cancel(rygPendingFlushBlock);
		rygPendingFlushBlock = nil;
	}
	dispatch_block_t block = dispatch_block_create((dispatch_block_flags_t)0, ^{
		rygPendingFlushBlock = nil;
		rygFlushPendingBatch();
	});
	rygPendingFlushBlock = block;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRYGScrollPauseDelay * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), block);
}

static void rygDropOffscreenPendingPKs(void) {
	NSMutableOrderedSet *pending = rygPending();
	if (!pending.count) return;
	NSMutableSet<NSString *> *visiblePKs = [NSMutableSet set];
	rygEnumerateCardCells(^(UIView *cell, NSString *pk) {
		if (cell.window && pk.length) [visiblePKs addObject:pk];
	});
	NSMutableArray *drop = [NSMutableArray array];
	for (NSString *pk in pending) {
		if (![visiblePKs containsObject:pk]) [drop addObject:pk];
	}
	if (drop.count) [pending removeObjectsInArray:drop];
}

static void rygScheduleFetchForPK(NSString *pk) {
	if (!pk.length || !rygFetchMissing()) return;
	NSMutableDictionary *cache = rygInfoCache();
	NSMutableSet *inflight = rygInflight();
	@synchronized(cache) {
		if (cache[pk]) return;
		if ([inflight containsObject:pk]) return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		NSMutableOrderedSet *pending = rygPending();
		if (![pending containsObject:pk]) [pending addObject:pk];
		rygScheduleFlushAfterPause();
	});
}

static void rygFlushPendingBatch(void) {
	if (rygBatchInFlight) { rygScheduleFlushAfterPause(); return; }
	rygDropOffscreenPendingPKs();
	NSMutableOrderedSet *pending = rygPending();
	if (!pending.count) return;

	NSRange r = NSMakeRange(0, MIN(kRYGBatchMaxPKs, pending.count));
	NSArray *batch = [[pending array] subarrayWithRange:r];
	[pending removeObjectsInRange:r];

	NSMutableDictionary *cache = rygInfoCache();
	NSMutableSet *inflight = rygInflight();
	@synchronized(cache) { [inflight addObjectsFromArray:batch]; }

	rygBatchInFlight = YES;
	[RYGInstagramAPI fetchMediaInfosForMediaIds:batch completion:^(NSDictionary *resp, NSError *err) {
		NSArray *items = [resp[@"items"] isKindOfClass:NSArray.class] ? resp[@"items"] : @[];
		@synchronized(cache) {
			for (NSDictionary *item in items) {
				if (![item isKindOfClass:NSDictionary.class]) continue;
				id pkVal = item[@"pk"] ?: item[@"id"];
				NSString *pkRaw = [pkVal isKindOfClass:NSString.class] ? pkVal : [pkVal description];
				NSString *pk = rygNormalizePK(pkRaw);
				if (!pk.length) continue;
				long long likes = -1, plays = -1, comments = -1, shares = -1, reposts = -1;
				NSDate *taken = nil;
				id lc = item[@"like_count"];
				id pc = item[@"play_count"] ?: item[@"view_count"];
				id cc = item[@"comment_count"];
				id sc = item[@"reshare_count"];
				id rc = item[@"media_repost_count"];
				id ta = item[@"taken_at"];
				if ([lc isKindOfClass:NSNumber.class]) likes = [lc longLongValue];
				if ([pc isKindOfClass:NSNumber.class]) plays = [pc longLongValue];
				if ([cc isKindOfClass:NSNumber.class]) comments = [cc longLongValue];
				if ([sc isKindOfClass:NSNumber.class]) shares = [sc longLongValue];
				if ([rc isKindOfClass:NSNumber.class]) reposts = [rc longLongValue];
				if ([ta isKindOfClass:NSNumber.class]) taken = [NSDate dateWithTimeIntervalSince1970:[ta doubleValue]];
				cache[pk] = @{ @"likes": @(likes), @"plays": @(plays), @"comments": @(comments),
				               @"shares": @(shares), @"reposts": @(reposts), @"takenAt": taken ?: [NSNull null] };
			}
			// Sentinel for pks not in the response — stops a refetch loop.
			for (NSString *pk in batch) {
				if (!cache[pk]) cache[pk] = @{ @"likes": @(-1), @"plays": @(-1), @"comments": @(-1),
				                              @"shares": @(-1), @"reposts": @(-1), @"takenAt": [NSNull null] };
			}
			[inflight minusSet:[NSSet setWithArray:batch]];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			rygBatchInFlight = NO;
			rygKickAllVisibleCards();
			if (rygPending().count) rygScheduleFlushAfterPause();
		});
	}];
}


static void rygBindCellToMedia(id cell, id media) {
	if (!cell || !media) return;
	objc_setAssociatedObject(cell, kRYGThumbCellMediaKey, media, OBJC_ASSOCIATION_ASSIGN);
	NSString *pk = rygMediaPK(media);
	if (pk.length) {
		objc_setAssociatedObject(cell, kRYGThumbCellPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
		NSDictionary *fc = [RYGUtils fieldCacheForObject:media];
		BOOL hasLikes = [fc[@"like_count"] isKindOfClass:NSNumber.class];
		if (!hasLikes && !rygInfoCache()[pk]) rygScheduleFetchForPK(pk);
	}
	[cell setNeedsLayout];
}

static id (*orig_thumbSC_cellForItemAtIndex)(id, SEL, NSInteger);
static id new_thumbSC_cellForItemAtIndex(id self, SEL _cmd, NSInteger index) {
	id cell = orig_thumbSC_cellForItemAtIndex(self, _cmd, index);
	if (cell) rygBindCellToMedia(cell, rygCurrentMediaForSC(self));
	return cell;
}

static void (*orig_thumbSC_didUpdateToObject)(id, SEL, id);
static void new_thumbSC_didUpdateToObject(id self, SEL _cmd, id object) {
	orig_thumbSC_didUpdateToObject(self, _cmd, object);
	@try {
		id ctx = [self valueForKey:@"collectionContext"];
		if (!ctx) return;
		id cell = ((id (*)(id, SEL, NSInteger, id))objc_msgSend)(
			ctx, @selector(cellForItemAtIndex:sectionController:), 0, self);
		if (cell) rygBindCellToMedia(cell, object);
	} @catch (__unused id e) {}
}

static id rygMediaForThumbCell(UIView *cell) {
	id delegate = rygObjIvar(cell, "_delegate");
	if (delegate) {
		id m = rygCurrentMediaForSC(delegate);
		if (m) return m;
	}
	return objc_getAssociatedObject(cell, kRYGThumbCellMediaKey);
}

static void rygRenderThumbCell(UIView *cellView) {
	if (!cellView) return;
	if (!rygAnyOn()) {
		rygClearRow(cellView, kRYGViewsRowTag);
		rygClearRow(cellView, kRYGLikesRowTag);
		rygClearRow(cellView, kRYGCommentsRowTag);
		rygClearRow(cellView, kRYGSharesRowTag);
		rygClearRow(cellView, kRYGRepostsRowTag);
		rygClearRow(cellView, kRYGDateRowTag);
		return;
	}

	id media = rygMediaForThumbCell(cellView);
	NSString *pk = rygMediaPK(media);
	NSDictionary *fc = [RYGUtils fieldCacheForObject:media];

	BOOL hasPlays = [fc[@"play_count"] isKindOfClass:NSNumber.class];
	BOOL hasLikes = [fc[@"like_count"] isKindOfClass:NSNumber.class];
	BOOL hasComments = [fc[@"comment_count"] isKindOfClass:NSNumber.class];
	BOOL hasShares   = [fc[@"reshare_count"] isKindOfClass:NSNumber.class];
	BOOL hasReposts  = [fc[@"media_repost_count"] isKindOfClass:NSNumber.class];
	BOOL hasDate  = [fc[@"taken_at"]  isKindOfClass:NSNumber.class] || [fc[@"taken_at"] isKindOfClass:NSDate.class];

	long long plays = hasPlays ? rygMediaPlayCount(media) : 0;
	long long likes = hasLikes ? rygMediaLikes(media) : 0;
	long long comments = hasComments ? rygMediaFCCount(media, @"comment_count") : 0;
	long long shares   = hasShares ? rygMediaFCCount(media, @"reshare_count") : 0;
	long long reposts  = hasReposts ? rygMediaFCCount(media, @"media_repost_count") : 0;
	NSDate *date    = hasDate  ? rygMediaTakenAt(media) : nil;

	NSDictionary *cached = pk.length ? rygInfoCache()[pk] : nil;
	if (cached) {
		if (!hasLikes) { long long v = [cached[@"likes"] longLongValue]; if (v >= 0) { likes = v; hasLikes = YES; } }
		if (!hasPlays) { long long v = [cached[@"plays"] longLongValue]; if (v >= 0) { plays = v; hasPlays = YES; } }
		if (!hasComments) { long long v = [cached[@"comments"] longLongValue]; if (v >= 0) { comments = v; hasComments = YES; } }
		if (!hasShares) { long long v = [cached[@"shares"] longLongValue]; if (v >= 0) { shares = v; hasShares = YES; } }
		if (!hasReposts) { long long v = [cached[@"reposts"] longLongValue]; if (v >= 0) { reposts = v; hasReposts = YES; } }
		if (!hasDate) { id t = cached[@"takenAt"]; if ([t isKindOfClass:NSDate.class]) { date = t; hasDate = YES; } }
	} else if (pk.length && ((rygShowComments() && !hasComments) || (rygShowShares() && !hasShares)
	           || (rygShowReposts() && !hasReposts) || (rygShowLikes() && !hasLikes))) {
		rygScheduleFetchForPK(pk);
	}

	const CGFloat rowH = 15;
	const CGFloat rowGap = 3;
	const CGFloat x = 8;
	CGFloat bottomY = cellView.bounds.size.height - (rowH + 6);

	NSString *dateTxt = rygDateText(date);
	NSDictionary<NSString *, id> *dataByMetric = @{
		@"views":    (hasPlays && plays > 0) ? rygCount(plays) : [NSNull null],
		@"likes":    (hasLikes && likes > 0) ? rygCount(likes) : [NSNull null],
		@"comments": (hasComments && comments > 0) ? rygCount(comments) : [NSNull null],
		@"shares":   (hasShares && shares > 0) ? rygCount(shares) : [NSNull null],
		@"reposts":  (hasReposts && reposts > 0) ? rygCount(reposts) : [NSNull null],
		@"date":     (hasDate && dateTxt.length) ? dateTxt : [NSNull null],
	};
	NSMutableArray<NSDictionary *> *specs = [NSMutableArray array];
	for (NSString *m in [RYGReelCardMetricOrder() reverseObjectEnumerator]) {
		id text = dataByMetric[m];
		if (rygMetricEnabled(m) && [text isKindOfClass:NSString.class]) {
			[specs addObject:@{ @"tag": @(rygTagForMetric(m)), @"icon": rygIconForMetric(m), @"text": text }];
		} else {
			rygClearRow(cellView, rygTagForMetric(m));
		}
	}

	rygStackRows(cellView, x, bottomY, rowH, rowGap, specs);
}

static void (*orig_thumbCell_layoutSubviews)(id, SEL);
static void new_thumbCell_layoutSubviews(id self, SEL _cmd) {
	orig_thumbCell_layoutSubviews(self, _cmd);
	rygRenderThumbCell((UIView *)self);
}


static NSMutableSet *rygHookedKeys(void) {
	static NSMutableSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}

static void rygHookIfPresent(NSString *clsName, SEL sel, IMP newImp, IMP *origStore) {
	NSString *key = [NSString stringWithFormat:@"%@|%@", clsName, NSStringFromSelector(sel)];
	NSMutableSet *set = rygHookedKeys();
	if ([set containsObject:key]) return;
	Class c = NSClassFromString(clsName);
	if (!c) return;
	MSHookMessageEx(c, sel, newImp, origStore);
	[set addObject:key];
}

static void rygTryAttachAll(void) {
	rygHookIfPresent(@"IGSundialGridVideoCell", @selector(layoutSubviews),
	                 (IMP)new_gridCell_layoutSubviews, (IMP *)&orig_gridCell_layoutSubviews);
	rygHookIfPresent(@"IGSundialGridVideoCell", @selector(prepareForReuse),
	                 (IMP)new_gridCell_prepareForReuse, (IMP *)&orig_gridCell_prepareForReuse);
	rygHookIfPresent(@"IGSundialGridVideoSectionController", @selector(cellForItemAtIndex:),
	                 (IMP)new_gridSC_cellForItemAtIndex, (IMP *)&orig_gridSC_cellForItemAtIndex);
	rygHookIfPresent(@"IGMediaThumbnailCell", @selector(layoutSubviews),
	                 (IMP)new_thumbCell_layoutSubviews, (IMP *)&orig_thumbCell_layoutSubviews);
	rygHookIfPresent(@"IGMediaThumbnailSectionController", @selector(cellForItemAtIndex:),
	                 (IMP)new_thumbSC_cellForItemAtIndex, (IMP *)&orig_thumbSC_cellForItemAtIndex);
	rygHookIfPresent(@"IGMediaThumbnailSectionController", @selector(didUpdateToObject:),
	                 (IMP)new_thumbSC_didUpdateToObject, (IMP *)&orig_thumbSC_didUpdateToObject);
}

%ctor {
	@autoreleasepool {
		if (!rygAnyOn()) return;
		rygTryAttachAll();
		[[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification
		                                                  object:nil
		                                                   queue:nil
		                                              usingBlock:^(NSNotification *note) {
			rygTryAttachAll();
		}];
		for (int delay = 1; delay <= 10; delay++) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
			               dispatch_get_main_queue(), ^{ rygTryAttachAll(); });
		}
	}
}
