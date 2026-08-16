// Media zoom — long press on feed media to expand in full-screen viewer.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../ActionButton/RYGMediaActions.h"
#import "../../ActionButton/RYGMediaViewer.h"
#import <objc/runtime.h>
#import <objc/message.h>

// IGFeedItemPageVideoCell declared in InstagramHeaders.h

static const void *kZoomGestureKey = &kZoomGestureKey;

static BOOL rygZoomEnabled(void) {
    return [RYGUtils getBoolPref:@"feed_media_zoom"];
}

// Walk up to the feed's outer collection view (skip carousel inner CVs)
static UICollectionView *rygFeedCollectionView(UIView *view) {
    UIView *v = view;
    while (v) {
        if ([v isKindOfClass:[UICollectionView class]]) {
            NSString *cls = NSStringFromClass([v class]);
            if (![cls containsString:@"Carousel"] && ![cls containsString:@"Page"])
                return (UICollectionView *)v;
        }
        v = v.superview;
    }
    return nil;
}

static NSInteger rygFeedSectionForView(UIView *view, UICollectionView *cv) {
    UIView *v = view;
    while (v) {
        if ([v isKindOfClass:[UICollectionViewCell class]]) {
            NSIndexPath *ip = [cv indexPathForCell:(UICollectionViewCell *)v];
            if (ip) return ip.section;
        }
        v = v.superview;
    }
    return -1;
}

static IGMedia *rygZoomFeedMedia(UIView *view) {
    Class mediaClass = NSClassFromString(@"IGMedia");
    if (!mediaClass) return nil;

    UICollectionView *cv = rygFeedCollectionView(view);
    if (!cv) return nil;

    NSInteger section = rygFeedSectionForView(view, cv);
    if (section < 0) return nil;

    for (UICollectionViewCell *cell in cv.visibleCells) {
        NSIndexPath *path = [cv indexPathForCell:cell];
        if (!path || path.section != section) continue;

        NSString *cls = NSStringFromClass([cell class]);
        if (![cls containsString:@"Photo"] && ![cls containsString:@"Video"]
            && ![cls containsString:@"Media"] && ![cls containsString:@"Page"]) continue;

        unsigned int count = 0;
        Class c = object_getClass(cell);
        while (c && c != [UICollectionViewCell class]) {
            Ivar *ivars = class_copyIvarList(c, &count);
            for (unsigned int i = 0; i < count; i++) {
                const char *type = ivar_getTypeEncoding(ivars[i]);
                if (!type || type[0] != '@') continue;
                @try {
                    id val = object_getIvar(cell, ivars[i]);
                    if (val && [val isKindOfClass:mediaClass]) { free(ivars); return (IGMedia *)val; }
                } @catch (__unused id e) {}
            }
            if (ivars) free(ivars);
            c = class_getSuperclass(c);
        }

        if ([cell respondsToSelector:@selector(mediaCellFeedItem)]) {
            id m = ((id(*)(id,SEL))objc_msgSend)(cell, @selector(mediaCellFeedItem));
            if (m && [m isKindOfClass:mediaClass]) return (IGMedia *)m;
        }
    }
    return nil;
}

static NSInteger rygZoomPageIndex(UIView *view) {
    UICollectionView *cv = rygFeedCollectionView(view);
    if (!cv) return 0;

    NSInteger section = rygFeedSectionForView(view, cv);
    if (section < 0) return 0;

    for (UICollectionViewCell *cell in cv.visibleCells) {
        NSIndexPath *path = [cv indexPathForCell:cell];
        if (!path || path.section != section) continue;
        if (![NSStringFromClass([cell class]) containsString:@"Page"]) continue;

        NSMutableArray *queue = [NSMutableArray arrayWithObject:cell];
        int scanned = 0;
        while (queue.count && scanned < 100) {
            UIView *cur = queue.firstObject; [queue removeObjectAtIndex:0]; scanned++;
            if ([cur isKindOfClass:[UIScrollView class]] && cur != cv) {
                UIScrollView *sv = (UIScrollView *)cur;
                CGFloat pageW = sv.bounds.size.width;
                if (pageW > 100 && sv.contentSize.width > pageW * 1.5)
                    return (NSInteger)round(sv.contentOffset.x / pageW);
            }
            for (UIView *s in cur.subviews) [queue addObject:s];
        }
    }
    return 0;
}

static void rygZoomFired(UILongPressGestureRecognizer *g) {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (!rygZoomEnabled()) return;

    UIView *view = g.view;
    IGMedia *media = rygZoomFeedMedia(view);
    if (!media) return;

    NSString *caption = [RYGMediaActions captionForMedia:media];

    if ([RYGMediaActions isCarouselMedia:media]) {
        NSArray *children = [RYGMediaActions carouselChildrenForMedia:media];
        NSMutableArray *items = [NSMutableArray array];
        for (id child in children) {
            NSURL *v = [RYGUtils getVideoUrlForMedia:(IGMedia *)child];
            NSURL *p = [RYGUtils getPhotoUrlForMedia:(IGMedia *)child];
            if (!v && !p) p = [RYGMediaActions bestURLForMedia:child];
            if (v || p) [items addObject:[RYGMediaViewerItem itemWithVideoURL:v photoURL:p caption:caption]];
        }
        if (items.count) {
            NSInteger idx = rygZoomPageIndex(view);
            if (idx < 0 || idx >= (NSInteger)items.count) idx = 0;
            [RYGMediaViewer showItems:items startIndex:idx];
            return;
        }
    }

    NSURL *videoUrl = [RYGUtils getVideoUrlForMedia:media];
    NSURL *photoUrl = [RYGUtils getPhotoUrlForMedia:media];
    if (!videoUrl && !photoUrl) photoUrl = [RYGMediaActions bestURLForMedia:media];
    if (!videoUrl && !photoUrl) return;

    [RYGMediaViewer showWithVideoURL:videoUrl photoURL:photoUrl caption:caption];
}

// MARK: - Gesture setup

@interface _RYGZoomTarget : NSObject @end
@implementation _RYGZoomTarget
- (void)fired:(UILongPressGestureRecognizer *)g { rygZoomFired(g); }
@end

static void rygAddZoomGesture(UIView *view) {
    if (objc_getAssociatedObject(view, kZoomGestureKey)) return;

    _RYGZoomTarget *target = [_RYGZoomTarget new];
    objc_setAssociatedObject(view, kZoomGestureKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
        initWithTarget:target action:@selector(fired:)];
    gesture.minimumPressDuration = 0.5;
    [view addGestureRecognizer:gesture];
}

// MARK: - Hooks

%hook IGFeedPhotoView
- (void)didMoveToSuperview {
    %orig;
    if (self.superview) rygAddZoomGesture(self);
}
%end

%hook IGModernFeedVideoCell.IGModernFeedVideoCell
- (void)didMoveToSuperview {
    %orig;
    if (((UIView *)self).superview) rygAddZoomGesture((UIView *)self);
}
%end

%hook IGFeedItemPagePhotoCell
- (void)didMoveToSuperview {
    %orig;
    if (((UIView *)self).superview) rygAddZoomGesture((UIView *)self);
}
%end

%hook IGFeedItemPageVideoCell
- (void)didMoveToSuperview {
    RYGProbeOnce(@"hook.mediazoom.videocell", @"IGFeedItemPageVideoCell fired");
    %orig;
    if (self.superview) rygAddZoomGesture((UIView *)self);
}
%end

%ctor {
    %init(IGFeedItemPagePhotoCell = NSClassFromString(@"_TtC18IGFeedItemPageCell23IGFeedItemPagePhotoCell") ?: NSClassFromString(@"IGFeedItemPagePhotoCell"));
}
