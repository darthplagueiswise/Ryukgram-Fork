// Recolors Direct message bubbles per background (incoming / outgoing / both). Each bubble
// resolves its own thread from its thread VC so styling never leaks across recycled cells.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "RYGChatBackgroundManager.h"
#import "RYGChatBgThreadPickerVC.h"
#import "RYGChatBgIvars.h"
#import "../StoriesAndMessages/RYGUnsentIndicator.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <QuartzCore/QuartzCore.h>

static const void *kRYGOrigBgKey = &kRYGOrigBgKey;
static const void *kRYGOurGradientKey = &kRYGOurGradientKey;
static const void *kRYGApplyingKey = &kRYGApplyingKey;
static const void *kRYGOrigTextColorKey = &kRYGOrigTextColorKey;
static const void *kRYGAppliedTextColorKey = &kRYGAppliedTextColorKey;
static const void *kRYGTextApplyingKey = &kRYGTextApplyingKey;
static const void *kRYGSurfaceSolidKey = &kRYGSurfaceSolidKey;
static const void *kRYGOrigContentsKey = &kRYGOrigContentsKey;
static const void *kRYGBubbleSolidKey = &kRYGBubbleSolidKey;
static const void *kRYGAudioOrigTintKey = &kRYGAudioOrigTintKey;
static const void *kRYGAudioOrigBgKey = &kRYGAudioOrigBgKey;

static void rygRestoreTextInside(UIView *view);
static void rygRestoreParentTextColor(UIView *view);
static void rygRestoreGradientSurface(UIView *gv);
static void rygCaptureOrigBg(UIView *view);
static BOOL rygIsInsideAudioBubble(UIView *view);
static void rygRecolorAudioChrome(UIView *audioRoot, UIColor *color, BOOL apply);

// Visible bubbles, re-applied when colors/sides change in-chat.
static NSHashTable<UIView *> *rygLiveBubbles(void) {
	static NSHashTable *t;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ t = [NSHashTable weakObjectsHashTable]; });
	return t;
}

static NSHashTable<UIView *> *rygLiveTextViews(void) {
	static NSHashTable *t;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ t = [NSHashTable weakObjectsHashTable]; });
	return t;
}

// Per-view thread resolution (cached on the thread VC) so recycled cells never carry a
// previous chat's background into a new one.
static const void *kRYGVCThreadIDKey = &kRYGVCThreadIDKey;

static UIViewController *rygThreadVCForView(UIView *view) {
	static Class tc;
	if (!tc) tc = NSClassFromString(@"IGDirectThreadViewController");
	if (!tc) return nil;

	for (UIResponder *r = view; r; r = r.nextResponder) {
		if ([r isKindOfClass:tc]) return (UIViewController *)r;
	}
	return nil;
}

static NSString *rygThreadIDForView(UIView *view) {
	id vc = rygThreadVCForView(view);
	if (!vc) return nil;

	NSString *cached = objc_getAssociatedObject(vc, kRYGVCThreadIDKey);
	if (cached.length) return cached;

	id session = RYGBgIvarValue(vc, "_threadSession");
	NSString *tid = RYGBgReadTidFromContainer(RYGBgFindThreadKey(session));
	if (tid.length) objc_setAssociatedObject(vc, kRYGVCThreadIDKey, tid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return tid;
}

static NSString *rygBubbleAssetForView(UIView *view) {
	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];
	if (![m isEnabled]) return nil;

	NSString *tid = rygThreadIDForView(view);
	if (!tid.length) return nil;

	NSString *asset = [m resolvedAssetForThreadID:tid];
	if (!asset.length) return nil;

	return [m autoBubbleEnabledForAsset:asset] ? asset : nil;
}

static BOOL rygSideAllowedForAsset(NSString *asset, BOOL outgoing) {
	RYGBubbleSides sides = asset ? [[RYGChatBackgroundManager shared] bubbleSidesForAsset:asset] : RYGBubbleSidesIncoming;
	if (sides == RYGBubbleSidesBoth) return YES;
	return outgoing ? (sides == RYGBubbleSidesOutgoing) : (sides == RYGBubbleSidesIncoming);
}

static RYGBubbleGradientDirection rygGradientDirectionForAsset(NSString *asset) {
	return asset ? [[RYGChatBackgroundManager shared] bubbleGradientDirectionForAsset:asset] : RYGBubbleGradientDirectionDiagonal;
}

static BOOL rygColorVisible(UIColor *color) {
	return color && CGColorGetAlpha(color.CGColor) > 0.05;
}


static NSString *rygActiveUserPk(void) {
	static NSString *cached;
	static CFTimeInterval stamp;

	CFTimeInterval now = CACurrentMediaTime();
	if (cached.length && now - stamp < 2.0) return cached;

	NSString *pk = [RYGUtils currentUserPK];
	if (pk.length) { cached = pk; stamp = now; }

	// Mid-scroll the session lookup can come back empty; the last known pk still holds.
	return pk.length ? pk : cached;
}

// A recycled or mid-layout bubble has no reliable frame, so the sender decides the side.
static BOOL rygSideFromMessage(UIView *view, BOOL *resolved) {
	static Class cellCls;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cellCls = NSClassFromString(@"_TtC19IGDirectMessageCell19IGDirectMessageCell")
				  ?: NSClassFromString(@"IGDirectMessageCell");
	});

	*resolved = NO;
	if (!cellCls) return NO;

	UIView *cell = nil;
	for (UIView *v = view; v; v = v.superview) {
		if ([v isKindOfClass:cellCls]) { cell = v; break; }
	}
	if (!cell) return NO;

	id vm = nil, meta = nil;
	SEL vmSel = NSSelectorFromString(@"viewModel");
	SEL metaSel = NSSelectorFromString(@"messageMetadata");

	@try {
		if ([cell respondsToSelector:vmSel]) vm = ((id (*)(id, SEL))objc_msgSend)(cell, vmSel);
		if ([vm respondsToSelector:metaSel]) meta = ((id (*)(id, SEL))objc_msgSend)(vm, metaSel);
	} @catch (__unused id e) { return NO; }

	id raw = RYGBgIvarValue(meta, "_senderPk");
	NSString *sender = [raw isKindOfClass:NSString.class] ? raw
					 : ([raw isKindOfClass:NSNumber.class] ? [(NSNumber *)raw stringValue] : nil);

	NSString *me = rygActiveUserPk();
	if (!sender.length || !me.length) return NO;

	*resolved = YES;
	return [sender isEqualToString:me];
}

static BOOL rygIsOutgoingBubble(UIView *view, BOOL *known) {
	BOOL resolved = NO;
	BOOL outgoing = rygSideFromMessage(view, &resolved);

	if (known) *known = resolved;
	return outgoing;
}

static void rygEachSubview(UIView *view, void (^block)(UIView *sub)) {
	if (!view || !block) return;

	for (UIView *sub in view.subviews) {
		block(sub);
		rygEachSubview(sub, block);
	}
}

static Class rygIGGradientViewClass(void) {
	static Class c;
	if (!c) c = NSClassFromString(@"IGGradientView");
	return c;
}

static Class rygIGDirectGradientViewClass(void) {
	static Class c;
	if (!c) c = NSClassFromString(@"IGDirectGradientView");
	return c;
}

static BOOL rygIsIGGradientView(UIView *view) {
	Class c = rygIGGradientViewClass();
	return c && [view isKindOfClass:c];
}

static BOOL rygIsIGDirectGradientView(UIView *view) {
	Class c = rygIGDirectGradientViewClass();
	return c && [view isKindOfClass:c];
}

static BOOL rygIsAnyGradientView(UIView *view) {
	return rygIsIGGradientView(view) || rygIsIGDirectGradientView(view);
}

static Class rygIGBubbleViewClass(void) {
	static Class c;
	if (!c) c = NSClassFromString(@"IGDirectMessageBubbleView");
	return c;
}

// Normal messages use IGDirectMessageBubbleView; replies use IGDirectContextReplyBubbleView.
static UIView *rygEnclosingBubble(UIView *view) {
	Class c = rygIGBubbleViewClass();
	for (UIView *v = view; v; v = v.superview) {
		if (c && [v isKindOfClass:c]) return v;
		if ([NSStringFromClass(v.class) containsString:@"ContextReplyBubble"]) return v;
	}
	return nil;
}

static BOOL rygHasNativeGradient(UIView *view) {
	__block BOOL found = NO;

	rygEachSubview(view, ^(UIView *sub) {
		if (!found && rygIsIGGradientView(sub)) found = YES;
	});

	return found;
}

static void rygHideNativeGradients(UIView *view, BOOL hidden) {
	rygEachSubview(view, ^(UIView *sub) {
		if (rygIsIGGradientView(sub)) sub.hidden = hidden;
	});
}

static BOOL rygHasNestedBubbleView(UIView *view) {
	static Class c;
	if (!c) c = NSClassFromString(@"IGDirectMessageBubbleView");

	__block BOOL found = NO;

	rygEachSubview(view, ^(UIView *sub) {
		if (!found && c && sub != view && [sub isKindOfClass:c]) found = YES;
	});

	return found;
}

// The composer reply bar and replied-to status header — left native.
static BOOL rygIsInsideQuotedReply(UIView *view) {
	for (UIView *v = view; v; v = v.superview) {
		NSString *name = NSStringFromClass([v class]);

		if ([name containsString:@"ReplyBar"]) return YES;
		if ([name containsString:@"RepliedToStatus"]) return YES;
	}

	return NO;
}

// In a reply cell the replied-to preview and the reply share the same class chain; the
// preview sits in the top half. Skip anything centered there.
static BOOL rygIsRepliedToPreview(UIView *view) {
	UIView *cell = nil;
	for (UIView *v = view; v; v = v.superview) {
		if ([NSStringFromClass(v.class) containsString:@"QuotedReplyMessageCell"]) { cell = v; break; }
	}
	if (!cell || CGRectIsEmpty(view.bounds) || CGRectGetHeight(cell.bounds) < 1.0) return NO;

	CGRect f = [view convertRect:view.bounds toView:cell];
	return CGRectGetMidY(f) < CGRectGetHeight(cell.bounds) * 0.5;
}

static BOOL rygIsSafeBubbleTarget(UIView *view, BOOL forceTextBubble) {
	if (!view.window) return NO;
	if (CGRectIsEmpty(view.bounds)) return NO;

	if (!forceTextBubble && rygIsInsideQuotedReply(view)) return NO;

	CGRect f = [view convertRect:view.bounds toView:view.window];
	CGFloat screenW = CGRectGetWidth(view.window.bounds);
	CGFloat width = CGRectGetWidth(f);
	CGFloat height = CGRectGetHeight(f);

	if (width < 8.0 || height < 8.0) return NO;
	if (!forceTextBubble && width > screenW * 0.86) return NO;
	if (!forceTextBubble && rygHasNestedBubbleView(view)) return NO;
	if (view.layer.cornerRadius < 4.0 && !rygHasNativeGradient(view)) return NO;

	return YES;
}

static CAGradientLayer *rygGradientLayer(UIView *view) {
	CAGradientLayer *layer = objc_getAssociatedObject(view, kRYGOurGradientKey);
	if (layer) return layer;

	layer = [CAGradientLayer layer];
	objc_setAssociatedObject(view, kRYGOurGradientKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return layer;
}

static void rygRemoveGradient(UIView *view) {
	CAGradientLayer *layer = objc_getAssociatedObject(view, kRYGOurGradientKey);
	if (!layer) return;

	[layer removeFromSuperlayer];
	objc_setAssociatedObject(view, kRYGOurGradientKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Undo only a recolor we painted; untouched surfaces are left alone.
static void rygRestoreGradientSurface(UIView *gv) {
	id origContents = objc_getAssociatedObject(gv, kRYGOrigContentsKey);
	BOOL touched = objc_getAssociatedObject(gv, kRYGOurGradientKey)
				   || objc_getAssociatedObject(gv, kRYGSurfaceSolidKey)
				   || origContents;
	if (!touched) return;

	rygRemoveGradient(gv);
	objc_setAssociatedObject(gv, kRYGSurfaceSolidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	rygHideNativeGradients(gv, NO);

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	gv.layer.backgroundColor = nil;
	// IG's own fill lives in layer contents; without putting it back the bubble ends up empty.
	gv.layer.contents = (origContents && origContents != NSNull.null) ? origContents : nil;
	[CATransaction commit];

	objc_setAssociatedObject(gv, kRYGOrigContentsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void rygRestoreBubble(UIView *view) {
	rygRemoveGradient(view);
	rygHideNativeGradients(view, NO);

	rygEachSubview(view, ^(UIView *sub) {
		if (rygIsAnyGradientView(sub)) rygRestoreGradientSurface(sub);
	});

	if (rygIsInsideAudioBubble(view)) rygRecolorAudioChrome(view, nil, NO);

	rygRestoreTextInside(view);
	rygRestoreParentTextColor(view);

	UIColor *orig = objc_getAssociatedObject(view, kRYGOrigBgKey);

	// Reverting a background we never wrote stamps a stale snapshot over IG's own.
	if (objc_getAssociatedObject(view, kRYGBubbleSolidKey)) {
		objc_setAssociatedObject(view, kRYGBubbleSolidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		view.layer.backgroundColor = orig ? orig.CGColor : nil;
		[CATransaction commit];
	}
}

static void rygApplySolid(UIView *view, UIColor *color) {
	rygCaptureOrigBg(view);
	objc_setAssociatedObject(view, kRYGBubbleSolidKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	rygRemoveGradient(view);
	rygHideNativeGradients(view, YES);

	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	view.layer.backgroundColor = color.CGColor;

	[CATransaction commit];
}

static void rygGradientPoints(RYGBubbleGradientDirection dir, CGPoint *start, CGPoint *end) {
	switch (dir) {
		case RYGBubbleGradientDirectionHorizontal: *start = CGPointMake(0.0, 0.5); *end = CGPointMake(1.0, 0.5); break;
		case RYGBubbleGradientDirectionVertical:   *start = CGPointMake(0.5, 0.0); *end = CGPointMake(0.5, 1.0); break;
		default:                                   *start = CGPointMake(0.0, 0.0); *end = CGPointMake(1.0, 1.0); break;
	}
}

// setBackgroundColor: never fires for bubbles IG fills through its layer, so capture here.
static void rygCaptureOrigBg(UIView *view) {
	if (objc_getAssociatedObject(view, kRYGOrigBgKey)) return;
	if (!view.layer.backgroundColor) return;
	objc_setAssociatedObject(view, kRYGOrigBgKey, [UIColor colorWithCGColor:view.layer.backgroundColor],
							 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void rygApplyLayerGradient(UIView *view, UIColor *first, UIColor *second, RYGBubbleGradientDirection dir) {
	CAGradientLayer *layer = rygGradientLayer(view);

	if (layer.superlayer != view.layer) {
		[view.layer insertSublayer:layer atIndex:0];
	}

	CGPoint start, end;
	rygGradientPoints(dir, &start, &end);

	rygCaptureOrigBg(view);

	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	layer.frame = view.bounds;
	layer.cornerRadius = view.layer.cornerRadius;
	layer.maskedCorners = view.layer.maskedCorners;
	layer.startPoint = start;
	layer.endPoint = end;
	layer.colors = @[
		(__bridge id)first.CGColor,
		(__bridge id)second.CGColor
	];

	[CATransaction commit];
}

static void rygApplyGradientSurface(UIView *gv);

// Outermost gradient surfaces in a bubble: IGDirectGradientView wrappers, plus any standalone
// IGGradientView not already owned by one (avoids double-painting the inner view).
static BOOL rygSurfaceDrawable(UIView *surface, UIView *root) {
	for (UIView *v = surface; v && v != root.superview; v = v.superview) {
		if (v.hidden || v.alpha < 0.02) return NO;
	}
	return YES;
}

static NSArray<UIView *> *rygGradientSurfaces(UIView *root) {
	NSMutableArray<UIView *> *outer = [NSMutableArray array];
	NSMutableArray<UIView *> *inner = [NSMutableArray array];

	// IG hides this wrapper on a recycled bubble; painting it there paints nothing at all.
	rygEachSubview(root, ^(UIView *sub) {
		if (!rygSurfaceDrawable(sub, root)) return;
		if (rygIsIGDirectGradientView(sub)) [outer addObject:sub];
		else if (rygIsIGGradientView(sub)) [inner addObject:sub];
	});

	if (!outer.count) return inner;

	for (UIView *g in inner) {
		BOOL wrapped = NO;
		for (UIView *o in outer) {
			for (UIView *p = g; p; p = p.superview) {
				if (p == o) { wrapped = YES; break; }
			}
			if (wrapped) break;
		}
		if (!wrapped) [outer addObject:g];
	}

	return outer;
}

static BOOL rygLooksLikeBubble(UIView *view, BOOL forceTextBubble) {
	if (!rygIsSafeBubbleTarget(view, forceTextBubble)) return NO;

	// A bubble we gave a gradient layer has a nil background by design — keep maintaining it.
	if (objc_getAssociatedObject(view, kRYGOurGradientKey)) return YES;

	UIColor *orig = objc_getAssociatedObject(view, kRYGOrigBgKey);
	if (rygColorVisible(orig)) return YES;
	if (rygHasNativeGradient(view)) return YES;

	CGColorRef bg = view.layer.backgroundColor;
	return bg && CGColorGetAlpha(bg) > 0.05;
}

static NSString *rygTextFromCoreTextView(id textView) {
	if (!textView || ![textView respondsToSelector:@selector(styledString)]) return nil;

	id ss = ((id (*)(id, SEL))objc_msgSend)(textView, @selector(styledString));
	if (!ss || ![ss respondsToSelector:@selector(attributedString)]) return nil;

	NSAttributedString *as = ((NSAttributedString *(*)(id, SEL))objc_msgSend)(ss, @selector(attributedString));
	return as.string;
}

static BOOL rygStringHasLettersOrNumbers(NSString *s) {
	if (!s.length) return NO;

	NSCharacterSet *set = [NSCharacterSet alphanumericCharacterSet];
	return [s rangeOfCharacterFromSet:set].location != NSNotFound;
}

static BOOL rygStringContainsEmoji(NSString *s) {
	__block BOOL found = NO;

	[s enumerateSubstringsInRange:NSMakeRange(0, s.length)
		options:NSStringEnumerationByComposedCharacterSequences
		usingBlock:^(NSString *sub, __unused NSRange r, __unused NSRange er, BOOL *stop) {
			unichar c = [sub characterAtIndex:0];
			// Surrogate pairs + the BMP symbol/dingbat/arrow blocks cover common emoji.
			if ((c >= 0xD800 && c <= 0xDBFF) || (c >= 0x2190 && c <= 0x2BFF) || c == 0x203C || c == 0x2049) {
				found = YES;
				*stop = YES;
			}
		}];

	return found;
}

static BOOL rygStringLooksEmojiOnly(NSString *s) {
	if (!s.length) return NO;

	NSString *trim = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!trim.length) return NO;

	// Only the bubble-less emoji style is skipped; punctuation-only text ("...") still colors.
	return !rygStringHasLettersOrNumbers(trim) && rygStringContainsEmoji(trim);
}

static BOOL rygBubbleLooksEmojiOnly(UIView *bubble) {
	static Class textClass;
	if (!textClass) textClass = NSClassFromString(@"IGCoreTextView");

	__block BOOL foundText = NO;
	__block BOOL emojiOnly = NO;

	rygEachSubview(bubble, ^(UIView *sub) {
		if (foundText || !textClass || ![sub isKindOfClass:textClass]) return;

		NSString *text = rygTextFromCoreTextView((id)sub);
		if (!text.length) return;

		foundText = YES;
		emojiOnly = rygStringLooksEmojiOnly(text);
	});

	UIView *parent = nil;
	static Class textBubbleClass;
	if (!textBubbleClass) textBubbleClass = NSClassFromString(@"IGDirectTextMessageBubbleView");

	for (UIView *v = bubble.superview; v; v = v.superview) {
		if (textBubbleClass && [v isKindOfClass:textBubbleClass]) {
			parent = v;
			break;
		}
	}

	if (!foundText && parent && [parent respondsToSelector:@selector(textView)]) {
		id tv = ((id (*)(id, SEL))objc_msgSend)(parent, @selector(textView));
		NSString *text = rygTextFromCoreTextView(tv);

		foundText = text.length > 0;
		emojiOnly = rygStringLooksEmojiOnly(text);
	}

	return foundText && emojiOnly;
}

static void rygRecolorTextView(id textView, UIColor *color) {
	if (!textView || !color) return;
	if (![textView respondsToSelector:@selector(styledString)]) return;
	if (![textView respondsToSelector:@selector(setStyledString:)]) return;

	IGStyledString *ss = ((IGStyledString *(*)(id, SEL))objc_msgSend)(textView, @selector(styledString));
	NSAttributedString *as = ss.attributedString;
	NSUInteger len = as.length;

	if (!len) return;

	UIColor *cur = [as attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
	if (cur && [cur isEqual:color]) return;

	// NSNull marks "IG set no explicit color" (e.g. white outgoing text) so restore is faithful.
	if (!objc_getAssociatedObject(textView, kRYGOrigTextColorKey)) {
		objc_setAssociatedObject(textView, kRYGOrigTextColorKey, cur ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	[ss setColor:color range:NSMakeRange(0, len)];
	((void (*)(id, SEL, id))objc_msgSend)(textView, @selector(setStyledString:), ss);
	objc_setAssociatedObject(textView, kRYGAppliedTextColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void rygRestoreTextView(id textView) {
	id orig = objc_getAssociatedObject(textView, kRYGOrigTextColorKey);
	if (!orig) return;

	UIColor *applied = objc_getAssociatedObject(textView, kRYGAppliedTextColorKey);

	objc_setAssociatedObject(textView, kRYGOrigTextColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(textView, kRYGAppliedTextColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	if (![textView respondsToSelector:@selector(styledString)] || ![textView respondsToSelector:@selector(setStyledString:)]) return;

	IGStyledString *ss = ((IGStyledString *(*)(id, SEL))objc_msgSend)(textView, @selector(styledString));
	NSAttributedString *as = ss.attributedString;
	NSUInteger len = as.length;
	if (!len) return;

	// If IG already re-styled this recycled view, don't clobber its fresh color.
	UIColor *now = [as attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
	if (applied && now && ![now isEqual:applied]) return;

	if (![orig isKindOfClass:UIColor.class]) return;

	[ss setColor:(UIColor *)orig range:NSMakeRange(0, len)];
	((void (*)(id, SEL, id))objc_msgSend)(textView, @selector(setStyledString:), ss);
}

static void rygRecolorTextInside(UIView *view, UIColor *color) {
	static Class c;
	if (!c) c = NSClassFromString(@"IGCoreTextView");

	rygEachSubview(view, ^(UIView *sub) {
		if (c && [sub isKindOfClass:c] && !rygIsInsideQuotedReply(sub) && !rygIsRepliedToPreview(sub))
			rygRecolorTextView((id)sub, color);
	});
}

static void rygRestoreTextInside(UIView *view) {
	static Class c;
	if (!c) c = NSClassFromString(@"IGCoreTextView");

	rygEachSubview(view, ^(UIView *sub) {
		if (c && [sub isKindOfClass:c]) rygRestoreTextView((id)sub);
	});
}

static UIView *rygParentTextBubble(UIView *view) {
	static Class c;
	if (!c) c = NSClassFromString(@"IGDirectTextMessageBubbleView");

	for (UIView *v = view.superview; v; v = v.superview) {
		if (c && [v isKindOfClass:c]) return v;
	}

	return nil;
}

static BOOL rygIsBubbleInsideTextBubble(UIView *bubble, UIView *textBubble) {
	if (!bubble || !textBubble) return NO;

	for (UIView *v = bubble.superview; v; v = v.superview) {
		if (v == textBubble) return YES;
	}

	return NO;
}

static void rygRecolorParentTextBubble(UIView *bubble, UIColor *color) {
	UIView *parent = rygParentTextBubble(bubble);
	if (!parent || !color) return;

	if ([parent respondsToSelector:@selector(textView)]) {
		id tv = ((id (*)(id, SEL))objc_msgSend)(parent, @selector(textView));
		rygRecolorTextView(tv, color);
	}

	if ([parent respondsToSelector:@selector(secondaryTextView)]) {
		id tv = ((id (*)(id, SEL))objc_msgSend)(parent, @selector(secondaryTextView));
		rygRecolorTextView(tv, color);
	}
}

static void rygRestoreParentTextColor(UIView *bubble) {
	UIView *parent = rygParentTextBubble(bubble);
	if (!parent) return;

	if ([parent respondsToSelector:@selector(textView)]) {
		rygRestoreTextView(((id (*)(id, SEL))objc_msgSend)(parent, @selector(textView)));
	}

	if ([parent respondsToSelector:@selector(secondaryTextView)]) {
		rygRestoreTextView(((id (*)(id, SEL))objc_msgSend)(parent, @selector(secondaryTextView)));
	}
}

static BOOL rygIsInsideAudioBubble(UIView *view) {
	for (UIView *v = view; v; v = v.superview) {
		if ([NSStringFromClass(v.class) containsString:@"AudioMessageBubble"]) return YES;
	}
	return NO;
}

static void rygSetAudioTint(UIView *v, UIColor *color, BOOL apply) {
	if (apply) {
		if (!objc_getAssociatedObject(v, kRYGAudioOrigTintKey))
			objc_setAssociatedObject(v, kRYGAudioOrigTintKey, v.tintColor ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		v.tintColor = color;
	} else {
		id orig = objc_getAssociatedObject(v, kRYGAudioOrigTintKey);
		if (!orig) return;
		v.tintColor = [orig isKindOfClass:UIColor.class] ? orig : nil;
		objc_setAssociatedObject(v, kRYGAudioOrigTintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
}

// Recolor voice-note chrome to the text color: waveform (IGAudioWaveformView tintColor),
// duration label, and play-button circle (IGDirectGradientView backgroundColor).
static void rygRecolorAudioChrome(UIView *audioRoot, UIColor *color, BOOL apply) {
	if (!color && apply) return;

	rygEachSubview(audioRoot, ^(UIView *sub) {
		NSString *cls = NSStringFromClass(sub.class);

		if ([cls containsString:@"AudioWaveform"]) {
			rygSetAudioTint(sub, color, apply);
			rygEachSubview(sub, ^(UIView *iv) {
				if ([iv isKindOfClass:UIImageView.class]) rygSetAudioTint(iv, color, apply);
			});
		} else if ([sub isKindOfClass:UILabel.class]) {
			UILabel *lbl = (UILabel *)sub;
			if (apply) {
				if (!objc_getAssociatedObject(lbl, kRYGAudioOrigBgKey))
					objc_setAssociatedObject(lbl, kRYGAudioOrigBgKey, lbl.textColor ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				lbl.textColor = color;
			} else {
				id orig = objc_getAssociatedObject(lbl, kRYGAudioOrigBgKey);
				if (orig) {
					lbl.textColor = [orig isKindOfClass:UIColor.class] ? orig : nil;
					objc_setAssociatedObject(lbl, kRYGAudioOrigBgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				}
			}
		} else if (rygIsIGDirectGradientView(sub)) {
			if (apply) {
				if (!objc_getAssociatedObject(sub, kRYGAudioOrigBgKey))
					objc_setAssociatedObject(sub, kRYGAudioOrigBgKey, sub.backgroundColor ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				sub.backgroundColor = color;
			} else {
				id orig = objc_getAssociatedObject(sub, kRYGAudioOrigBgKey);
				if (orig) {
					sub.backgroundColor = [orig isKindOfClass:UIColor.class] ? orig : nil;
					objc_setAssociatedObject(sub, kRYGAudioOrigBgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				}
			}
		}
	});
}

// Only text, audio and reply bubbles are recolored; media / shared / disappearing bubbles
// keep their native look (tinting them hides play icons or half-colors attachments).
static BOOL rygBubbleIsColorableType(UIView *bubble) {
	if (rygParentTextBubble(bubble)) return YES;
	if (rygIsInsideAudioBubble(bubble)) return YES;

	for (UIView *v = bubble; v; v = v.superview) {
		if ([NSStringFromClass(v.class) containsString:@"ContextReplyBubble"]) return YES;
	}
	return NO;
}

// Shared eligibility for the text + gradient-surface paths.
static BOOL rygBubbleEligibleForRecolor(UIView *bubble, NSString *asset) {
	if (!bubble || !bubble.window) return NO;
	if (!rygBubbleIsColorableType(bubble)) return NO;
	BOOL sideKnown = NO;
	BOOL outgoing = rygIsOutgoingBubble(bubble, &sideKnown);
	if (!sideKnown) return NO;
	if (!rygSideAllowedForAsset(asset, outgoing)) return NO;
	if (rygIsInsideQuotedReply(bubble)) return NO;
	if (rygIsRepliedToPreview(bubble)) return NO;
	if (rygBubbleLooksEmojiOnly(bubble)) return NO;
	return YES;
}

// Recolor/restore one text view from its own bubble + thread. Driven by the setStyledString:
// hook so the color re-applies whenever IG (re)sets the text.
static void rygHandleTextView(UIView *tv) {
	if (objc_getAssociatedObject(tv, kRYGTextApplyingKey)) return;
	if (RYGUnsentTintOwnsView(tv)) { rygRestoreTextView((id)tv); return; }

	[rygLiveTextViews() addObject:tv];

	UIView *bubble = rygEnclosingBubble(tv) ?: rygParentTextBubble(tv);
	NSString *asset = bubble ? rygBubbleAssetForView(bubble) : nil;

	if (bubble && asset && rygBubbleEligibleForRecolor(bubble, asset)) {
		UIColor *color = [[RYGChatBackgroundManager shared] autoBubbleTextColorForAsset:asset];
		objc_setAssociatedObject(tv, kRYGTextApplyingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		rygRecolorTextView((id)tv, color);
		objc_setAssociatedObject(tv, kRYGTextApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	} else {
		rygRestoreTextView((id)tv);
	}
}

static void rygApplyGradientSurface(UIView *gv) {
	if (!gv || objc_getAssociatedObject(gv, kRYGApplyingKey)) return;
	if (RYGUnsentTintOwnsView(gv)) return;

	// In an audio message the gradient views are the play button + waveform — handled by
	// rygRecolorAudioChrome, not here.
	if (rygIsInsideAudioBubble(gv)) { rygRestoreGradientSurface(gv); return; }

	UIView *bubble = rygEnclosingBubble(gv);
	NSString *asset = rygBubbleAssetForView(bubble ?: gv);
	NSArray<UIColor *> *colors = asset ? [[RYGChatBackgroundManager shared] bubbleColorsForAsset:asset] : nil;

	if (!bubble || !colors.count || !rygBubbleEligibleForRecolor(bubble, asset)) {
		rygRestoreGradientSurface(gv);
		return;
	}

	objc_setAssociatedObject(gv, kRYGApplyingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	// Suppress IG's gradient (live colors or a pre-rendered image), then paint ours.
	rygHideNativeGradients(gv, YES);

	if (!objc_getAssociatedObject(gv, kRYGOrigContentsKey)) {
		objc_setAssociatedObject(gv, kRYGOrigContentsKey, gv.layer.contents ?: (id)NSNull.null,
								 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	gv.layer.contents = nil;
	[CATransaction commit];

	if (colors.count > 1) {
		objc_setAssociatedObject(gv, kRYGSurfaceSolidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		rygApplyLayerGradient(gv, colors[0], colors[1], rygGradientDirectionForAsset(asset));
	} else {
		rygRemoveGradient(gv);
		objc_setAssociatedObject(gv, kRYGSurfaceSolidKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		gv.layer.backgroundColor = colors[0].CGColor;
		[CATransaction commit];
	}

	objc_setAssociatedObject(gv, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void rygApplyBubbleFallback(UIView *view, BOOL forceTextBubble) {
	if (!view || objc_getAssociatedObject(view, kRYGApplyingKey)) return;
	if (RYGUnsentTintOwnsView(view)) return;

	BOOL sideKnown = NO;
	BOOL outgoing = rygIsOutgoingBubble(view, &sideKnown);

	// An unresolved side must leave the bubble alone; restoring here is what blanked themes.
	if (!sideKnown) return;

	objc_setAssociatedObject(view, kRYGApplyingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	NSString *asset = rygBubbleAssetForView(view);

	if (!asset) {
		rygRestoreBubble(view);
		objc_setAssociatedObject(view, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	// Forced callers (text bubble, event bubble) are already known-colorable.
	if (!forceTextBubble && !rygBubbleIsColorableType(view)) {
		rygRestoreBubble(view);
		objc_setAssociatedObject(view, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	// Side not chosen for this background → leave native.
	if (!rygSideAllowedForAsset(asset, outgoing)) {
		rygRestoreBubble(view);
		objc_setAssociatedObject(view, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	// Replied-to preview (top of a reply cell) is the quoted message — leave native.
	if (rygIsRepliedToPreview(view)) {
		rygRestoreBubble(view);
		objc_setAssociatedObject(view, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	if (!forceTextBubble && rygIsInsideQuotedReply(view)) {
		objc_setAssociatedObject(view, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	if (!rygLooksLikeBubble(view, forceTextBubble)) {
		objc_setAssociatedObject(view, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	// Emoji-only messages keep IG's transparent look.
	if (rygBubbleLooksEmojiOnly(view)) {
		rygRestoreBubble(view);
		objc_setAssociatedObject(view, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	NSArray<UIColor *> *colors = [[RYGChatBackgroundManager shared] bubbleColorsForAsset:asset];

	// Audio: only paint the bubble's own background; surfaces are the play button/waveform.
	BOOL audio = rygIsInsideAudioBubble(view);
	NSArray<UIView *> *surfaces = audio ? @[] : rygGradientSurfaces(view);

	if (colors.count > 1) {
		if (surfaces.count) {
			// The surface owns the fill; IG's own background stays put underneath it.
			for (UIView *s in surfaces) rygApplyGradientSurface(s);
			rygRemoveGradient(view);
		} else {
			if (!audio) rygHideNativeGradients(view, YES);
			rygApplyLayerGradient(view, colors[0], colors[1], rygGradientDirectionForAsset(asset));
		}
	} else if (colors.count == 1) {
		if (audio) {
			rygCaptureOrigBg(view);
			objc_setAssociatedObject(view, kRYGBubbleSolidKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			rygRemoveGradient(view);
			[CATransaction begin];
			[CATransaction setDisableActions:YES];
			view.layer.backgroundColor = colors[0].CGColor;
			[CATransaction commit];
		} else {
			rygApplySolid(view, colors[0]);
			for (UIView *s in surfaces) rygApplyGradientSurface(s);
		}
	} else {
		rygRestoreBubble(view);
		objc_setAssociatedObject(view, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}


	UIColor *textColor = [[RYGChatBackgroundManager shared] autoBubbleTextColorForAsset:asset];

	rygRecolorTextInside(view, textColor);
	rygRecolorParentTextBubble(view, textColor);

	if (audio) rygRecolorAudioChrome(view, textColor, YES);

	objc_setAssociatedObject(view, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void rygApplyInnerBubbleFromTextBubble(UIView *view) {
	if (!view || ![view respondsToSelector:@selector(bubbleView)]) return;

	UIView *bubble = ((UIView *(*)(id, SEL))objc_msgSend)(view, @selector(bubbleView));
	if (!bubble) return;

	if (!rygIsBubbleInsideTextBubble(bubble, view) && bubble.superview != view) return;

	rygApplyBubbleFallback(bubble, YES);
}

%hook IGDirectMessageBubbleView

- (void)setBackgroundColor:(UIColor *)color {
	%orig;

	if (!objc_getAssociatedObject(self, kRYGApplyingKey)) {
		objc_setAssociatedObject(self, kRYGOrigBgKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	[rygLiveBubbles() addObject:self];
	rygApplyBubbleFallback((UIView *)self, NO);
}

- (void)layoutSubviews {
	%orig;
	[rygLiveBubbles() addObject:self];
	rygApplyBubbleFallback((UIView *)self, NO);
}

%end

%hook IGDirectTextMessageBubbleView

- (void)layoutSubviews {
	%orig;
	rygApplyInnerBubbleFromTextBubble((UIView *)self);
}

- (void)_applyBubbleStyleFromViewModel:(id)model {
	%orig;
	rygApplyInnerBubbleFromTextBubble((UIView *)self);
}

%end

// Recolor the moment text is (re)set, so first-load and scroll-in messages never get missed.
%hook IGCoreTextView

- (void)setStyledString:(id)styledString {
	%orig;
	rygHandleTextView((UIView *)self);
}

%end

// Theme gradient re-renders here after layout — re-assert so our color wins (animated themes).
%hook IGDirectGradientView

- (void)layoutSubviews {
	%orig;
	rygApplyGradientSurface((UIView *)self);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
	%orig;
	rygApplyGradientSurface((UIView *)self);
}

%end

%hook IGGradientView

- (void)layoutSubviews {
	%orig;

	// An IGDirectGradientView ancestor already paints + hides us.
	for (UIView *v = self.superview; v; v = v.superview) {
		if (rygIsIGDirectGradientView(v)) return;
	}

	rygApplyGradientSurface((UIView *)self);
}

%end

// Call / event messages (e.g. missed calls) use their own Swift bubble — route its layout
// through the same per-view apply.
static void (*orig_rygEventBubbleLayout)(id, SEL);
static void new_rygEventBubbleLayout(id self, SEL _cmd) {
	orig_rygEventBubbleLayout(self, _cmd);
	[rygLiveBubbles() addObject:(UIView *)self];
	rygApplyBubbleFallback((UIView *)self, YES);
}

static void rygHookEventBubble(NSString *mangled, NSString *bare) {
	Class cls = NSClassFromString(mangled);
	if (!cls) cls = NSClassFromString(bare);
	if (!cls) return;

	MSHookMessageEx(cls, @selector(layoutSubviews), (IMP)new_rygEventBubbleLayout, (IMP *)&orig_rygEventBubbleLayout);
}

%ctor {
	if (![RYGUtils getBoolPref:RYGPrefChatBackgroundEnabled]) return;
	%init;

	rygHookEventBubble(@"_TtC31IGDirectVideoCallEventMessageUI32IGDirectVideoCallEventBubbleView", @"IGDirectVideoCallEventBubbleView");

	[NSNotificationCenter.defaultCenter addObserverForName:RYGChatBackgroundDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *_) {
		for (UIView *bubble in [rygLiveBubbles() allObjects]) {
			objc_setAssociatedObject(bubble, kRYGApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			[bubble setNeedsLayout];
			rygApplyBubbleFallback(bubble, NO);
		}
		// A theme toggle doesn't re-set the text, so re-drive touched text views directly.
		for (UIView *tv in [rygLiveTextViews() allObjects]) rygHandleTextView(tv);
	}];
}