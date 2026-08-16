// Legacy multi-finger download gestures (dw_legacy_gesture), off by default. The modern flow lives in ActionButton/.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../ActionButton/RYGMediaViewer.h"
#import "../../ActionButton/RYGMediaActions.h"
#import "../Profile/RYGProfileHelpers.h"
#import <objc/runtime.h>

static RYGDownloadDelegate *imageDownloadDelegate;
static RYGDownloadDelegate *videoDownloadDelegate;

static DownloadAction rygGetDownloadAction() {
    NSString *method = [RYGUtils getStringPref:@"dw_save_action"];
    if ([method isEqualToString:@"photos"]) return saveToPhotos;
    if ([method isEqualToString:@"gallery"] && [RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return saveToGallery;
    return share;
}

static void initDownloaders() {
    DownloadAction action = rygGetDownloadAction();
    DownloadAction imgAction;
    if (action == saveToPhotos || action == saveToGallery) imgAction = action;
    else imgAction = quickLook;
    BOOL showImgProgress = (action == saveToGallery);
    imageDownloadDelegate = [[RYGDownloadDelegate alloc] initWithAction:imgAction showProgress:showImgProgress];
    videoDownloadDelegate = [[RYGDownloadDelegate alloc] initWithAction:action showProgress:YES];
}

static BOOL rygLegacyGestureEnabled() {
    return [RYGUtils getBoolPref:@"dw_legacy_gesture"];
}

static void rygInstallDownloadGesture(UIView *view) {
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:view action:@selector(handleLongPress:)];
    lp.minimumPressDuration = [RYGUtils getDoublePref:@"dw_finger_duration"];
    lp.numberOfTouchesRequired = [RYGUtils getDoublePref:@"dw_finger_count"];
    [view addGestureRecognizer:lp];
}

static NSInteger rygCarouselPageIndexForView(UIView *view) {
    for (UIView *cur = view; cur; cur = cur.superview) {
        if ([cur isKindOfClass:UIScrollView.class]) {
            UIScrollView *sv = (UIScrollView *)cur;
            CGFloat w = sv.bounds.size.width;
            if (w > 100.0 && sv.contentSize.width > w * 1.5) {
                return (NSInteger)round(sv.contentOffset.x / w);
            }
        }
    }
    return -1;
}


/* * Feed (legacy gesture) * */

%hook IGFeedPhotoView
- (void)didMoveToSuperview {
    %orig;
    if (!rygLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    rygInstallDownloadGesture(self);
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender && sender.state != UIGestureRecognizerStateBegan) return;

    IGPhoto *photo;
    if ([self.delegate isKindOfClass:%c(IGFeedItemPhotoCell)]) {
        IGFeedItemPhotoCellConfiguration *_configuration = MSHookIvar<IGFeedItemPhotoCellConfiguration *>(self.delegate, "_configuration");
        if (!_configuration) return;
        photo = MSHookIvar<IGPhoto *>(_configuration, "_photo");
    } else if ([self.delegate isKindOfClass:(NSClassFromString(@"_TtC18IGFeedItemPageCell23IGFeedItemPagePhotoCell") ?: NSClassFromString(@"IGFeedItemPagePhotoCell"))]) {
        // Swift cell: pagePhotoPost is an ivar (id<IGPostItemProtocol>), not a method.
        id pagePost = MSHookIvar<id>(self.delegate, "pagePhotoPost");
        if ([pagePost respondsToSelector:@selector(photo)]) photo = [pagePost photo];
    }

    NSURL *photoUrl = [RYGUtils getPhotoUrl:photo];
    if (!photoUrl) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract photo URL")]; return; }

    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:photoUrl
                                 fileExtension:[[photoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end

%hook IGModernFeedVideoCell.IGModernFeedVideoCell
- (void)didMoveToSuperview {
    %orig;
    if (!rygLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    rygInstallDownloadGesture(self);
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender && sender.state != UIGestureRecognizerStateBegan) return;

    id media = [self mediaCellFeedItem];
    NSURL *videoUrl = [RYGUtils getVideoUrlForMedia:media];

    // Carousel page: mediaCellFeedItem returns the parent sidecar (no video_versions).
    if (!videoUrl && media && [RYGMediaActions isCarouselMedia:media]) {
        NSArray *children = [RYGMediaActions carouselChildrenForMedia:media];
        NSInteger idx = rygCarouselPageIndexForView(self);
        if (idx >= 0 && (NSUInteger)idx < children.count) {
            videoUrl = [RYGUtils getVideoUrlForMedia:children[idx]];
        }
        if (!videoUrl) {
            for (id child in children) {
                videoUrl = [RYGUtils getVideoUrlForMedia:child];
                if (videoUrl) break;
            }
        }
    }

    if (!videoUrl) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract video URL")]; return; }

    initDownloaders();
    [videoDownloadDelegate downloadFileWithURL:videoUrl
                                 fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end


/* * Stories (legacy gesture) * */

%hook IGStoryPhotoView
- (void)didMoveToSuperview {
    %orig;
    if (!rygLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    rygInstallDownloadGesture(self);
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSURL *photoUrl = [RYGUtils getPhotoUrlForMedia:[self item]];
    if (!photoUrl) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract photo URL")]; return; }

    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:photoUrl
                                 fileExtension:[[photoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end

%hook IGStoryModernVideoView
- (void)didMoveToSuperview {
    RYGProbeOnce(@"hook.mediadl.storyvideo", @"IGStoryModernVideoView fired");
    %orig;
    if (!rygLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    rygInstallDownloadGesture(self);
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSURL *videoUrl = [RYGUtils getVideoUrlForMedia:self.item];
    if (!videoUrl) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract video URL")]; return; }

    initDownloaders();
    [videoDownloadDelegate downloadFileWithURL:videoUrl
                                 fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end

%hook IGStoryVideoView

- (void)didMoveToSuperview {
	%orig;
	if (!rygLegacyGestureEnabled()) return;
	[self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    rygInstallDownloadGesture(self);
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
	if (sender.state != UIGestureRecognizerStateBegan) return;
	NSURL *videoUrl = nil;
	id item = nil;
	if ([self respondsToSelector:@selector(item)]) {
		item = [self item];
	}
	if (item) {
		videoUrl = [RYGUtils getVideoUrlForMedia:item];
	}
	if (!videoUrl) {
		id provider = nil;
		if ([self respondsToSelector:@selector(videoURLProvider)]) {
			provider = [self videoURLProvider];
		}
		if (provider) {
			videoUrl = [RYGUtils getVideoUrlForMedia:provider];
		}
	}
	if (!videoUrl) {
		id parentVC = [RYGUtils nearestViewControllerForView:self];
		if (!parentVC || ![parentVC isKindOfClass:%c(IGDirectVisualMessageViewerController)]) return;
		IGDirectVisualMessageViewerViewModeAwareDataSource *_dataSource = MSHookIvar<IGDirectVisualMessageViewerViewModeAwareDataSource *>(parentVC, "_dataSource");
		if (!_dataSource) return;
		IGDirectVisualMessage *_currentMessage = MSHookIvar<IGDirectVisualMessage *>(_dataSource, "_currentMessage");
		if (!_currentMessage) return;
		IGVideo *rawVideo = _currentMessage.rawVideo;
		if (!rawVideo) return;
		videoUrl = [RYGUtils getVideoUrl:rawVideo];
	}
	if (!videoUrl) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract video URL")];
		return;
	}
	initDownloaders();
	[videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:[[videoUrl lastPathComponent] pathExtension] hudLabel:nil];
}
%end


/* * Reels (legacy gesture) * */

%hook IGSundialViewerPhotoView
- (void)didMoveToSuperview {
    %orig;
    if (!rygLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    rygInstallDownloadGesture(self);
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        IGPhoto *_photo = MSHookIvar<IGPhoto *>(self, "_photo");
        if (!_photo) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not access reel photo")]; return; }

        NSURL *photoUrl = [RYGUtils getPhotoUrl:_photo];
        if (!photoUrl) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract photo URL")]; return; }

        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:photoUrl
                                     fileExtension:[[photoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    } @catch (NSException *exception) {
        NSLog(@"[RyukGram] Reel photo download error: %@", exception);
    }
}
%end

%hook IGSundialViewerVideoCell
- (void)didMoveToSuperview {
    %orig;
    if (!rygLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    rygInstallDownloadGesture(self);
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        // Runtime ivar scan: the exact name varies across IG releases.
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList([self class], &ivarCount);
        Class mediaClass = NSClassFromString(@"IGMedia");
        IGMedia *media = nil;
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char *name = ivar_getName(ivars[i]);
            if (!name) continue;
            NSString *lower = [[NSString stringWithUTF8String:name] lowercaseString];
            if ([lower containsString:@"video"] || [lower containsString:@"media"] || [lower containsString:@"item"]) {
                id val = object_getIvar(self, ivars[i]);
                if (val && mediaClass && [val isKindOfClass:mediaClass]) { media = val; break; }
            }
        }
        if (ivars) free(ivars);

        if (!media) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not access reel media")]; return; }

        NSURL *videoUrl = [RYGUtils getVideoUrlForMedia:media];

        // Reels carousel page: the ivar holds the parent sidecar (no video_versions).
        if (!videoUrl && [RYGMediaActions isCarouselMedia:media]) {
            NSArray *children = [RYGMediaActions carouselChildrenForMedia:media];
            NSInteger idx = rygCarouselPageIndexForView((UIView *)self);
            if (idx >= 0 && (NSUInteger)idx < children.count) {
                videoUrl = [RYGUtils getVideoUrlForMedia:children[idx]];
            }
            if (!videoUrl) {
                for (id child in children) {
                    videoUrl = [RYGUtils getVideoUrlForMedia:child];
                    if (videoUrl) break;
                }
            }
        }

        if (!videoUrl) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract video URL")]; return; }

        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    } @catch (NSException *exception) {
        NSLog(@"[RyukGram] Reel download error: %@", exception);
    }
}
%end


/* * Profile pictures * */

// Profile pic long press, routed through RYGProfileHelpers for the HD URL.
%hook IGProfilePhotoCoinFlipUI.IGProfilePhotoCoinFlipView

- (void)viewLongPressedWithGesture:(UILongPressGestureRecognizer *)gesture {
    if (![RYGUtils getBoolPref:@"zoom_profile_photo"]) {
        %orig;
        return;
    }
    if (gesture.state != UIGestureRecognizerStateBegan) {
        %orig;
        return;
    }

    UIView *source = gesture.view;
    id user = [RYGProfileHelpers userForView:source];
    if (user) {
        [RYGProfileHelpers viewPictureForUser:user];
        return;
    }

    %orig;
}

%end


static NSString *rygProfilePicViewUserPK(id view) {
    Ivar iv = class_getInstanceVariable([view class], "_userPk");
    if (!iv) return nil;
    id v = object_getIvar(view, iv);
    return [v isKindOfClass:NSString.class] && [v length] ? v : nil;
}

%hook IGProfilePictureImageView
- (void)didMoveToSuperview {
    %orig;
    if ([RYGUtils getBoolPref:@"save_profile"] || [RYGUtils getBoolPref:@"zoom_profile_photo"]) {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    id user = [RYGProfileHelpers userForView:self];

    if ([RYGUtils getBoolPref:@"zoom_profile_photo"]) {
        if (user) { [RYGProfileHelpers viewPictureForUser:user]; return; }
        // Off a profile page the view still carries the PK, so HD stays reachable.
        IGImageView *_imageView = MSHookIvar<IGImageView *>(self, "_imageView");
        IGImageSpecifier *spec = _imageView.imageSpecifier;
        NSURL *url = spec ? spec.url : nil;
        [RYGProfileHelpers viewPictureForPK:rygProfilePicViewUserPK(self) fallbackURL:url];
        return;
    }

    if (user) { [RYGProfileHelpers savePictureForUser:user]; return; }

    IGImageView *_imageView = MSHookIvar<IGImageView *>(self, "_imageView");
    IGImageSpecifier *imageSpecifier = _imageView.imageSpecifier;
    NSURL *imageUrl = imageSpecifier ? imageSpecifier.url : nil;
    [RYGProfileHelpers resolveHDPictureURLForPK:rygProfilePicViewUserPK(self) cached:imageUrl completion:^(NSURL *url) {
        NSURL *target = url ?: imageUrl;
        if (!target) return;
        NSString *ext = target.pathExtension.lowercaseString;
        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:target
                                     fileExtension:ext.length ? ext : @"jpg"
                                          hudLabel:RYGLocalized(@"Loading")];
    }];
}
%end
