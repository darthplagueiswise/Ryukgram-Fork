// Profile post/reel card overlays — views, likes, date.
//
// Reels (IGSundialGridVideoCell) already has IG's _playCountLabel — retext it,
// add a capsule. Posts (IGMediaThumbnailCell) has no label, draw our own row.
//
// Missing counts (posts grid, reels on IG 433+) refetch via batched
// /media/infos/, debounced so we don't hit cards the user flies past.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIIcon.h"
#import "../../Networking/SCIInstagramAPI.h"
#import <substrate.h>
#import <objc/runtime.h>

static const NSInteger kSCIViewsRowTag      = 0x52435601;
static const NSInteger kSCILikesRowTag      = 0x52434C01;
static const NSInteger kSCIDateRowTag       = 0x52434401;
static const NSInteger kSCIViewsBackdropTag = 0x52435602;

static const void *kSCIThumbCellMediaKey = &kSCIThumbCellMediaKey;
static const void *kSCIThumbCellPKKey    = &kSCIThumbCellPKKey;

static BOOL sciFullViews(void)    { return [SCIUtils getBoolPref:@"reel_card_full_views"]; }
static BOOL sciShowLikes(void)    { return [SCIUtils getBoolPref:@"reel_card_show_likes"]; }
static BOOL sciShowDate(void)     { return [SCIUtils getBoolPref:@"reel_card_show_date"]; }
static BOOL sciFetchMissing(void) { return [SCIUtils getBoolPref:@"reel_card_fetch_missing"]; }
static BOOL sciShortNumbers(void) { return [SCIUtils getBoolPref:@"reel_card_shortened_numbers"]; }
static BOOL sciAnyOn(void) { return sciFullViews() || sciShowLikes() || sciShowDate(); }


static NSString *sciCount(long long n) {
	return [SCIUtils formatCount:n shortened:sciShortNumbers()];
}

static NSString *sciDateText(NSDate *d) {
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


static id sciObjIvar(id obj, const char *name) {
	if (!obj || !name) return nil;
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return nil;
	const char *enc = ivar_getTypeEncoding(iv);
	if (!enc || enc[0] != '@') return nil;
	@try { return object_getIvar(obj, iv); } @catch (__unused id e) { return nil; }
}

static long long sciLLIvar(id obj, const char *name) {
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

static long long sciMediaLikes(id media) {
	if (!media) return 0;
	Ivar iv = class_getInstanceVariable([media class], "_likeCount");
	if (iv) {
		const char *enc = ivar_getTypeEncoding(iv);
		if (enc && (enc[0] == 'q' || enc[0] == 'Q')) {
			long long n = sciLLIvar(media, "_likeCount");
			if (n > 0) return n;
		}
	}
	id fc = [SCIUtils fieldCacheValue:media forKey:@"like_count"];
	if ([fc isKindOfClass:NSNumber.class]) return [fc longLongValue];
	@try {
		id v = [media valueForKey:@"likeCount"];
		if ([v isKindOfClass:NSNumber.class]) return [v longLongValue];
	} @catch (__unused id e) {}
	return 0;
}

static long long sciMediaPlayCount(id media) {
	if (!media) return 0;
	id fc = [SCIUtils fieldCacheValue:media forKey:@"play_count"];
	if ([fc isKindOfClass:NSNumber.class]) return [fc longLongValue];
	fc = [SCIUtils fieldCacheValue:media forKey:@"view_count"];
	if ([fc isKindOfClass:NSNumber.class]) return [fc longLongValue];
	id v = sciObjIvar(media, "_playCount");
	if ([v isKindOfClass:NSNumber.class]) return [v longLongValue];
	return 0;
}

static NSDate *sciMediaTakenAt(id media) {
	if (!media) return nil;
	id v = sciObjIvar(media, "_takenAt");
	if ([v isKindOfClass:NSDate.class]) return v;
	id fc = [SCIUtils fieldCacheValue:media forKey:@"taken_at"];
	if ([fc isKindOfClass:NSNumber.class]) return [NSDate dateWithTimeIntervalSince1970:[fc doubleValue]];
	if ([fc isKindOfClass:NSDate.class]) return fc;
	@try {
		id k = [media valueForKey:@"takenAt"];
		if ([k isKindOfClass:NSDate.class]) return k;
		if ([k isKindOfClass:NSNumber.class]) return [NSDate dateWithTimeIntervalSince1970:[k doubleValue]];
	} @catch (__unused id e) {}
	return nil;
}


static UIView *sciHostForCell(UIView *cell) {
	if ([cell isKindOfClass:[UICollectionViewCell class]]) {
		return ((UICollectionViewCell *)cell).contentView;
	}
	return cell;
}

static const NSInteger kSCIRowBgTag = 3;

// Dark rounded capsule with its fill inside an SCIChromeCanvas so Hide UI on
// Capture redacts it. Caller drives the frame; icons/labels go in -contentContainer.
static SCIChromeCanvas *sciChromeCapsule(NSInteger tag) {
	SCIChromeCanvas *canvas = [SCIChromeCanvas new];
	canvas.tag = tag;
	canvas.userInteractionEnabled = NO;
	canvas.translatesAutoresizingMaskIntoConstraints = YES;

	UIView *host = canvas.contentContainer;

	UIView *bg = [[UIView alloc] init];
	bg.tag = kSCIRowBgTag;
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

static UIView *sciEnsureRow(UIView *cell, NSInteger tag, NSString *iconName) {
	UIView *host = sciHostForCell(cell);
	UIView *row = [host viewWithTag:tag];
	if (row) return row;

	SCIChromeCanvas *canvas = sciChromeCapsule(tag);
	UIView *content = canvas.contentContainer;

	UIImageView *icon = [[UIImageView alloc] init];
	icon.tag = 1;
	UIImage *img = [SCIIcon fbImageNamed:iconName];
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

static void sciPositionRow(UIView *row, NSString *text, CGFloat x, CGFloat y) {
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

// Capsule sibling sitting just below IG's own _playCountLabel in z-order.
static void sciEnsureViewsBackdrop(UIView *target) {
	if (!target || !target.superview) return;
	UIView *superview = target.superview;
	UIView *backdrop = [superview viewWithTag:kSCIViewsBackdropTag];
	if (!backdrop) {
		backdrop = sciChromeCapsule(kSCIViewsBackdropTag);
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

static void sciRemoveViewsBackdrop(UIView *cell) {
	UIView *b = [cell.superview viewWithTag:kSCIViewsBackdropTag];
	if (b) [b removeFromSuperview];
	UIView *b2 = [cell viewWithTag:kSCIViewsBackdropTag];
	if (b2) [b2 removeFromSuperview];
}


// IG 433 dropped the cell's _mediaAccess ivar — media lives on the owning
// section controller now (_video); our SC hook also binds it to the cell.
static id sciMediaForGridCell(id cell) {
	id m = sciObjIvar(cell, "_mediaAccess");
	if (m) return m;
	m = sciObjIvar(sciObjIvar(cell, "_delegate"), "_video");
	if (m) return m;
	return objc_getAssociatedObject(cell, kSCIThumbCellMediaKey);
}

static NSString *sciMediaPK(id media);
static NSString *sciNormalizePK(NSString *pk);
static NSMutableDictionary<NSString *, NSDictionary *> *sciInfoCache(void);
static void sciScheduleFetchForPK(NSString *pk);

static void (*orig_gridCell_layoutSubviews)(id, SEL);
static void new_gridCell_layoutSubviews(id self, SEL _cmd) {
	orig_gridCell_layoutSubviews(self, _cmd);

	UIView *cellView = (UIView *)self;

	if (!sciAnyOn()) {
		UIView *l = [cellView viewWithTag:kSCILikesRowTag]; if (l) [l removeFromSuperview];
		UIView *d = [cellView viewWithTag:kSCIDateRowTag];  if (d) [d removeFromSuperview];
		sciRemoveViewsBackdrop(cellView);
		return;
	}

	id media     = sciMediaForGridCell(self);
	id playLabel = sciObjIvar(self, "_playCountLabel");

	NSString *pk = sciMediaPK(media);
	if (!pk.length) {
		id raw = sciObjIvar(self, "_mediaPK");
		if ([raw isKindOfClass:NSString.class]) pk = sciNormalizePK(raw);
	}
	if (pk.length) {
		NSString *cur = objc_getAssociatedObject(self, kSCIThumbCellPKKey);
		if (![cur isEqualToString:pk]) {
			objc_setAssociatedObject(self, kSCIThumbCellPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
		}
	}

	if (sciFullViews() && playLabel) {
		long long count = sciLLIvar(playLabel, "_count");
		UILabel *inner = (UILabel *)sciObjIvar(playLabel, "_label");
		if (count > 0 && inner) {
			NSString *txt = sciCount(count);
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
	UILabel *innerLbl = (UILabel *)sciObjIvar(playLabel, "_label");
	BOOL pvHasFrame = pv && pv.frame.size.width > 4 && pv.frame.size.height > 4;
	BOOL innerHasText = innerLbl && innerLbl.text.length > 0 && !innerLbl.hidden;
	BOOL viewsVisible = (pvHasFrame && !pv.hidden && pv.alpha > 0.05
	                     && sciLLIvar(playLabel, "_count") > 0
	                     && innerHasText);

	if (viewsVisible) sciEnsureViewsBackdrop(pv);
	else              sciRemoveViewsBackdrop(cellView);

	const CGFloat capsulePadH = 5;
	const CGFloat rowH = 15;
	const CGFloat rowGap = 3;
	// Align our rows with the capsule's left edge — IG's label sits at
	// pv.origin.x but the backdrop extends padH to its left.
	CGFloat x = pvHasFrame ? (pv.frame.origin.x - capsulePadH) : 8;
	CGFloat bottomSlotY = pvHasFrame ? pv.frame.origin.y : (cellView.bounds.size.height - (rowH + 8));
	CGFloat yAboveBottom = bottomSlotY - (rowH + rowGap);

	long long likes = sciMediaLikes(media);
	BOOL hasLikes = likes > 0
		|| (media && [[SCIUtils fieldCacheValue:media forKey:@"like_count"] isKindOfClass:NSNumber.class]);
	NSDate *date = sciMediaTakenAt(media);
	BOOL hasDate = (date != nil);

	NSDictionary *cached = pk.length ? sciInfoCache()[pk] : nil;
	if (cached) {
		if (!hasLikes) {
			long long cl = [cached[@"likes"] longLongValue];
			if (cl >= 0) { likes = cl; hasLikes = YES; }
		}
		if (!hasDate) {
			id t = cached[@"takenAt"];
			if ([t isKindOfClass:NSDate.class]) { date = t; hasDate = YES; }
		}
	} else if (pk.length && ((sciShowLikes() && !hasLikes) || (sciShowDate() && !hasDate))) {
		sciScheduleFetchForPK(pk);
	}

	if (sciShowLikes()) {
		UIView *row = sciEnsureRow(cellView, kSCILikesRowTag, @"direct-like");
		sciPositionRow(row, hasLikes ? sciCount(likes) : @"-", x, viewsVisible ? yAboveBottom : bottomSlotY);
	} else {
		UIView *r = [cellView viewWithTag:kSCILikesRowTag]; if (r) [r removeFromSuperview];
	}

	if (sciShowDate()) {
		NSString *txt = sciDateText(date) ?: @"-";
		UIView *row = sciEnsureRow(cellView, kSCIDateRowTag, @"clock-small");
		CGFloat dateY;
		if (viewsVisible && sciShowLikes())   dateY = yAboveBottom - (rowH + rowGap);
		else if (viewsVisible)                 dateY = yAboveBottom;
		else if (sciShowLikes())               dateY = yAboveBottom;
		else                                    dateY = bottomSlotY;
		sciPositionRow(row, txt, x, dateY);
	} else {
		UIView *r = [cellView viewWithTag:kSCIDateRowTag]; if (r) [r removeFromSuperview];
	}
}

static void (*orig_gridCell_prepareForReuse)(id, SEL);
static void new_gridCell_prepareForReuse(id self, SEL _cmd) {
	objc_setAssociatedObject(self, kSCIThumbCellMediaKey, nil, OBJC_ASSOCIATION_ASSIGN);
	objc_setAssociatedObject(self, kSCIThumbCellPKKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
	orig_gridCell_prepareForReuse(self, _cmd);
}

static id (*orig_gridSC_cellForItemAtIndex)(id, SEL, NSInteger);
static id new_gridSC_cellForItemAtIndex(id self, SEL _cmd, NSInteger index) {
	id cell = orig_gridSC_cellForItemAtIndex(self, _cmd, index);
	if (!cell) return cell;
	id media = sciObjIvar(self, "_video");
	if (!media) {
		NSArray *list = sciObjIvar(self, "_mediaList");
		if ([list isKindOfClass:NSArray.class] && index >= 0 && (NSUInteger)index < list.count) media = list[index];
	}
	if (media) {
		objc_setAssociatedObject(cell, kSCIThumbCellMediaKey, media, OBJC_ASSOCIATION_ASSIGN);
		NSString *pk = sciMediaPK(media);
		if (pk.length) {
			objc_setAssociatedObject(cell, kSCIThumbCellPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
		}
		[cell setNeedsLayout];
	}
	return cell;
}


// `_media` lags behind on cell reuse; the IGListKit object is authoritative.
static id sciCurrentMediaForSC(id sc) {
	if (!sc) return nil;
	@try {
		id obj = [sc valueForKey:@"object"];
		if (obj) return obj;
	} @catch (__unused id e) {}
	return sciObjIvar(sc, "_media");
}

// IGMedia stores pks as "<mediaPK>_<userPK>"; /media/infos/ returns bare pk.
// Normalize everything to bare so cache lookups line up.
static NSString *sciNormalizePK(NSString *pk) {
	if (![pk isKindOfClass:NSString.class] || !pk.length) return nil;
	NSRange r = [pk rangeOfString:@"_"];
	return r.location == NSNotFound ? pk : [pk substringToIndex:r.location];
}

static NSString *sciMediaPK(id media) {
	if (!media) return nil;
	id pk = [SCIUtils fieldCacheValue:media forKey:@"pk"];
	if ([pk isKindOfClass:NSString.class] && [(NSString *)pk length]) return sciNormalizePK(pk);
	@try {
		id v = [media valueForKey:@"pk"];
		if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return sciNormalizePK(v);
	} @catch (__unused id e) {}
	return nil;
}

//
// In-memory only — fresh counts on every session. Scroll-pause gated so we
// don't fire requests for cards the user flies past.

static NSMutableDictionary<NSString *, NSDictionary *> *sciInfoCache(void) {
	static NSMutableDictionary *d; static dispatch_once_t once;
	dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
	return d;
}

static NSMutableSet<NSString *> *sciInflight(void) {
	static NSMutableSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}

static NSMutableOrderedSet<NSString *> *sciPending(void) {
	static NSMutableOrderedSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableOrderedSet new]; });
	return s;
}

static dispatch_block_t sciPendingFlushBlock = nil;
static BOOL sciBatchInFlight = NO;
static const NSUInteger kSCIBatchMaxPKs = 50;
static const NSTimeInterval kSCIScrollPauseDelay = 0.2;

static void sciFlushPendingBatch(void);

static BOOL sciIsCardCell(UIView *v) {
	static Class thumbCls; static Class gridCls; static dispatch_once_t once;
	dispatch_once(&once, ^{
		thumbCls = NSClassFromString(@"IGMediaThumbnailCell");
		gridCls  = NSClassFromString(@"IGSundialGridVideoCell");
	});
	return (thumbCls && [v isKindOfClass:thumbCls]) || (gridCls && [v isKindOfClass:gridCls]);
}

static void sciEnumerateCardCells(void (^block)(UIView *cell, NSString *pk)) {
	for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) continue;
		for (UIWindow *win in ((UIWindowScene *)scene).windows) {
			NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:win];
			while (stack.count) {
				UIView *v = stack.lastObject; [stack removeLastObject];
				if (sciIsCardCell(v)) {
					block(v, objc_getAssociatedObject(v, kSCIThumbCellPKKey));
				}
				for (UIView *sv in v.subviews) [stack addObject:sv];
			}
		}
	}
}

static void sciKickCellsForPK(NSString *pk) {
	if (!pk.length) return;
	sciEnumerateCardCells(^(UIView *cell, NSString *cellPK) {
		if ([cellPK isEqualToString:pk]) [cell setNeedsLayout];
	});
}

static void sciScheduleFlushAfterPause(void) {
	if (sciPendingFlushBlock) {
		dispatch_block_cancel(sciPendingFlushBlock);
		sciPendingFlushBlock = nil;
	}
	dispatch_block_t block = dispatch_block_create((dispatch_block_flags_t)0, ^{
		sciPendingFlushBlock = nil;
		sciFlushPendingBatch();
	});
	sciPendingFlushBlock = block;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSCIScrollPauseDelay * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), block);
}

static void sciDropOffscreenPendingPKs(void) {
	NSMutableOrderedSet *pending = sciPending();
	if (!pending.count) return;
	NSMutableSet<NSString *> *visiblePKs = [NSMutableSet set];
	sciEnumerateCardCells(^(UIView *cell, NSString *pk) {
		if (cell.window && pk.length) [visiblePKs addObject:pk];
	});
	NSMutableArray *drop = [NSMutableArray array];
	for (NSString *pk in pending) {
		if (![visiblePKs containsObject:pk]) [drop addObject:pk];
	}
	if (drop.count) [pending removeObjectsInArray:drop];
}

static void sciScheduleFetchForPK(NSString *pk) {
	if (!pk.length || !sciFetchMissing()) return;
	NSMutableDictionary *cache = sciInfoCache();
	NSMutableSet *inflight = sciInflight();
	@synchronized(cache) {
		if (cache[pk]) return;
		if ([inflight containsObject:pk]) return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		NSMutableOrderedSet *pending = sciPending();
		if (![pending containsObject:pk]) [pending addObject:pk];
		sciScheduleFlushAfterPause();
	});
}

static void sciFlushPendingBatch(void) {
	if (sciBatchInFlight) { sciScheduleFlushAfterPause(); return; }
	sciDropOffscreenPendingPKs();
	NSMutableOrderedSet *pending = sciPending();
	if (!pending.count) return;

	NSRange r = NSMakeRange(0, MIN(kSCIBatchMaxPKs, pending.count));
	NSArray *batch = [[pending array] subarrayWithRange:r];
	[pending removeObjectsInRange:r];

	NSMutableDictionary *cache = sciInfoCache();
	NSMutableSet *inflight = sciInflight();
	@synchronized(cache) { [inflight addObjectsFromArray:batch]; }

	sciBatchInFlight = YES;
	[SCIInstagramAPI fetchMediaInfosForMediaIds:batch completion:^(NSDictionary *resp, NSError *err) {
		NSArray *items = [resp[@"items"] isKindOfClass:NSArray.class] ? resp[@"items"] : @[];
		NSMutableArray<NSString *> *kickPks = [NSMutableArray array];
		@synchronized(cache) {
			for (NSDictionary *item in items) {
				if (![item isKindOfClass:NSDictionary.class]) continue;
				id pkVal = item[@"pk"] ?: item[@"id"];
				NSString *pkRaw = [pkVal isKindOfClass:NSString.class] ? pkVal : [pkVal description];
				NSString *pk = sciNormalizePK(pkRaw);
				if (!pk.length) continue;
				long long likes = -1, plays = -1;
				NSDate *taken = nil;
				id lc = item[@"like_count"];
				id pc = item[@"play_count"] ?: item[@"view_count"];
				id ta = item[@"taken_at"];
				if ([lc isKindOfClass:NSNumber.class]) likes = [lc longLongValue];
				if ([pc isKindOfClass:NSNumber.class]) plays = [pc longLongValue];
				if ([ta isKindOfClass:NSNumber.class]) taken = [NSDate dateWithTimeIntervalSince1970:[ta doubleValue]];
				cache[pk] = @{ @"likes": @(likes), @"plays": @(plays), @"takenAt": taken ?: [NSNull null] };
				[kickPks addObject:pk];
			}
			// Sentinel for pks not in the response — stops a refetch loop.
			for (NSString *pk in batch) {
				if (!cache[pk]) cache[pk] = @{ @"likes": @(-1), @"plays": @(-1), @"takenAt": [NSNull null] };
			}
			[inflight minusSet:[NSSet setWithArray:batch]];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			sciBatchInFlight = NO;
			for (NSString *pk in kickPks) sciKickCellsForPK(pk);
			if (sciPending().count) sciScheduleFlushAfterPause();
		});
	}];
}


static void sciBindCellToMedia(id cell, id media) {
	if (!cell || !media) return;
	objc_setAssociatedObject(cell, kSCIThumbCellMediaKey, media, OBJC_ASSOCIATION_ASSIGN);
	NSString *pk = sciMediaPK(media);
	if (pk.length) {
		objc_setAssociatedObject(cell, kSCIThumbCellPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
		NSDictionary *fc = [SCIUtils fieldCacheForObject:media];
		BOOL hasLikes = [fc[@"like_count"] isKindOfClass:NSNumber.class];
		if (!hasLikes && !sciInfoCache()[pk]) sciScheduleFetchForPK(pk);
	}
	[cell setNeedsLayout];
}

static id (*orig_thumbSC_cellForItemAtIndex)(id, SEL, NSInteger);
static id new_thumbSC_cellForItemAtIndex(id self, SEL _cmd, NSInteger index) {
	id cell = orig_thumbSC_cellForItemAtIndex(self, _cmd, index);
	if (cell) sciBindCellToMedia(cell, sciCurrentMediaForSC(self));
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
		if (cell) sciBindCellToMedia(cell, object);
	} @catch (__unused id e) {}
}

static id sciMediaForThumbCell(UIView *cell) {
	id delegate = sciObjIvar(cell, "_delegate");
	if (delegate) {
		id m = sciCurrentMediaForSC(delegate);
		if (m) return m;
	}
	return objc_getAssociatedObject(cell, kSCIThumbCellMediaKey);
}

static void sciRenderThumbCell(UIView *cellView) {
	if (!cellView) return;
	if (!sciAnyOn()) {
		UIView *v = [cellView viewWithTag:kSCIViewsRowTag]; if (v) [v removeFromSuperview];
		UIView *l = [cellView viewWithTag:kSCILikesRowTag]; if (l) [l removeFromSuperview];
		UIView *d = [cellView viewWithTag:kSCIDateRowTag];  if (d) [d removeFromSuperview];
		return;
	}

	id media = sciMediaForThumbCell(cellView);
	NSString *pk = sciMediaPK(media);
	NSDictionary *fc = [SCIUtils fieldCacheForObject:media];

	BOOL hasPlays = [fc[@"play_count"] isKindOfClass:NSNumber.class];
	BOOL hasLikes = [fc[@"like_count"] isKindOfClass:NSNumber.class];
	BOOL hasDate  = [fc[@"taken_at"]  isKindOfClass:NSNumber.class] || [fc[@"taken_at"] isKindOfClass:NSDate.class];

	long long plays = hasPlays ? sciMediaPlayCount(media) : 0;
	long long likes = hasLikes ? sciMediaLikes(media) : 0;
	NSDate *date    = hasDate  ? sciMediaTakenAt(media) : nil;

	NSDictionary *cached = pk.length ? sciInfoCache()[pk] : nil;
	if (cached) {
		if (!hasLikes) {
			long long cl = [cached[@"likes"] longLongValue];
			if (cl >= 0) { likes = cl; hasLikes = YES; }
		}
		if (!hasPlays) {
			long long cp = [cached[@"plays"] longLongValue];
			if (cp >= 0) { plays = cp; hasPlays = YES; }
		}
		if (!hasDate) {
			id t = cached[@"takenAt"];
			if ([t isKindOfClass:NSDate.class]) { date = t; hasDate = YES; }
		}
	}

	BOOL showViews = sciFullViews() && hasPlays && plays > 0;
	const CGFloat rowH = 15;
	const CGFloat rowGap = 3;
	const CGFloat x = 8;
	CGFloat bottomY = cellView.bounds.size.height - (rowH + 6);
	CGFloat y = bottomY;

	if (showViews) {
		UIView *row = sciEnsureRow(cellView, kSCIViewsRowTag, @"ig_icon_eye_outline_12");
		sciPositionRow(row, sciCount(plays), x, y);
		y -= (rowH + rowGap);
	} else {
		UIView *r = [cellView viewWithTag:kSCIViewsRowTag]; if (r) [r removeFromSuperview];
	}

	if (sciShowLikes() && hasLikes) {
		UIView *row = sciEnsureRow(cellView, kSCILikesRowTag, @"direct-like");
		sciPositionRow(row, sciCount(likes), x, y);
		y -= (rowH + rowGap);
	} else {
		UIView *r = [cellView viewWithTag:kSCILikesRowTag]; if (r) [r removeFromSuperview];
	}

	if (sciShowDate() && hasDate) {
		NSString *txt = sciDateText(date);
		if (txt.length) {
			UIView *row = sciEnsureRow(cellView, kSCIDateRowTag, @"clock-small");
			sciPositionRow(row, txt, x, y);
		} else {
			UIView *r = [cellView viewWithTag:kSCIDateRowTag]; if (r) [r removeFromSuperview];
		}
	} else {
		UIView *r = [cellView viewWithTag:kSCIDateRowTag]; if (r) [r removeFromSuperview];
	}
}

static void (*orig_thumbCell_layoutSubviews)(id, SEL);
static void new_thumbCell_layoutSubviews(id self, SEL _cmd) {
	orig_thumbCell_layoutSubviews(self, _cmd);
	sciRenderThumbCell((UIView *)self);
}


static NSMutableSet *sciHookedKeys(void) {
	static NSMutableSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}

static void sciHookIfPresent(NSString *clsName, SEL sel, IMP newImp, IMP *origStore) {
	NSString *key = [NSString stringWithFormat:@"%@|%@", clsName, NSStringFromSelector(sel)];
	NSMutableSet *set = sciHookedKeys();
	if ([set containsObject:key]) return;
	Class c = NSClassFromString(clsName);
	if (!c) return;
	MSHookMessageEx(c, sel, newImp, origStore);
	[set addObject:key];
}

static void sciTryAttachAll(void) {
	sciHookIfPresent(@"IGSundialGridVideoCell", @selector(layoutSubviews),
	                 (IMP)new_gridCell_layoutSubviews, (IMP *)&orig_gridCell_layoutSubviews);
	sciHookIfPresent(@"IGSundialGridVideoCell", @selector(prepareForReuse),
	                 (IMP)new_gridCell_prepareForReuse, (IMP *)&orig_gridCell_prepareForReuse);
	sciHookIfPresent(@"IGSundialGridVideoSectionController", @selector(cellForItemAtIndex:),
	                 (IMP)new_gridSC_cellForItemAtIndex, (IMP *)&orig_gridSC_cellForItemAtIndex);
	sciHookIfPresent(@"IGMediaThumbnailCell", @selector(layoutSubviews),
	                 (IMP)new_thumbCell_layoutSubviews, (IMP *)&orig_thumbCell_layoutSubviews);
	sciHookIfPresent(@"IGMediaThumbnailSectionController", @selector(cellForItemAtIndex:),
	                 (IMP)new_thumbSC_cellForItemAtIndex, (IMP *)&orig_thumbSC_cellForItemAtIndex);
	sciHookIfPresent(@"IGMediaThumbnailSectionController", @selector(didUpdateToObject:),
	                 (IMP)new_thumbSC_didUpdateToObject, (IMP *)&orig_thumbSC_didUpdateToObject);
}

%ctor {
	@autoreleasepool {
		if (!sciAnyOn()) return;
		sciTryAttachAll();
		[[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification
		                                                  object:nil
		                                                   queue:nil
		                                              usingBlock:^(NSNotification *note) {
			sciTryAttachAll();
		}];
		for (int delay = 1; delay <= 10; delay++) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
			               dispatch_get_main_queue(), ^{ sciTryAttachAll(); });
		}
	}
}
