// View story mentions — direct @mentions + shared post/reel sticker users.

#import "../../Utils.h"
#import "../../SCIURLOpener.h"
#import "../../InstagramHeaders.h"
#import "../../SCIImageCache.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "StoryHelpers.h"
#import "StoryMenuItems.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern __weak UIViewController *sciActiveStoryViewerVC;

static char kPKCacheKey;
static char kMediaKey;
static char kAvatarURLKey;
static char kFollowUserKey;
static char kFollowPKKey;

#define kAvatarSize 52.0
#define kRowHeight  72.0

#define sciField(obj, key) [SCIUtils fieldCacheValue:(obj) forKey:(key)]

static id sciSend0(id obj, SEL sel) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static id sciSend1(id obj, SEL sel, id arg) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
	} @catch (__unused id e) {
		return nil;
	}
}

static NSString *sciString(id value) {
	if ([value isKindOfClass:NSString.class]) return [(NSString *)value length] ? value : nil;
	if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
	return nil;
}

static NSString *sciUserPK(id user) {
	return sciString(sciField(user, @"strong_id__") ?: sciField(user, @"pk") ?: sciSend0(user, @selector(pk)) ?: [SCIUtils pkFromIGUser:user]);
}

static NSDictionary *sciInfoFromUser(id user) {
	if (!user) return nil;

	NSString *pk = sciUserPK(user);
	NSString *username = sciString(sciField(user, @"username") ?: sciSend0(user, @selector(username)));
	NSString *fullName = sciString(sciField(user, @"full_name") ?: sciSend0(user, @selector(fullName)));
	NSString *pic = sciString(sciField(user, @"profile_pic_url") ?: sciSend0(user, @selector(profilePicURL)));

	if (!pk.length && !username.length) return nil;

	NSMutableDictionary *info = [@{ @"userObj": user } mutableCopy];

	if (pk.length) info[@"pk"] = pk;
	if (username.length) info[@"username"] = username;
	if (fullName.length) info[@"fullName"] = fullName;

	NSURL *url = pic.length ? [NSURL URLWithString:pic] : nil;
	if (url) info[@"picURL"] = url;

	return info.copy;
}

static NSDictionary *sciInfoFromMention(id mention) {
	if (!mention) return nil;

	id user = nil;

	@try {
		user = [mention valueForKey:@"user"];
	} @catch (__unused id e) {}

	return sciInfoFromUser(user ?: sciSend0(mention, @selector(user)));
}

static NSString *sciPKFromAPIUser(NSDictionary *user) {
	if (![user isKindOfClass:NSDictionary.class]) return nil;
	return sciString(user[@"pk"] ?: user[@"pk_id"] ?: user[@"id"]);
}

static NSDictionary *sciInfoFromAPIUser(NSDictionary *user) {
	NSString *pk = sciPKFromAPIUser(user);
	if (!pk.length) return nil;

	NSMutableDictionary *info = [@{ @"pk": pk } mutableCopy];

	NSString *username = user[@"username"];
	NSString *fullName = user[@"full_name"];
	NSString *pic = user[@"profile_pic_url"];

	info[@"username"] = username.length ? username : pk;
	if (fullName.length) info[@"fullName"] = fullName;

	NSURL *url = pic.length ? [NSURL URLWithString:pic] : nil;
	if (url) info[@"picURL"] = url;

	return info.copy;
}

static void sciStyleFollow(UIButton *btn, BOOL following) {
	[btn setTitle:following ? SCILocalized(@"Following") : SCILocalized(@"Follow") forState:UIControlStateNormal];
	btn.backgroundColor = following ? UIColor.tertiarySystemFillColor : UIColor.systemBlueColor;
	[btn setTitleColor:following ? UIColor.labelColor : UIColor.whiteColor forState:UIControlStateNormal];
}

// MARK: - Story media

static IGMedia *sciMediaFromItem(id item) {
	Class cls = NSClassFromString(@"IGMedia");
	return (cls && [item isKindOfClass:cls]) ? item : sciExtractMediaFromItem(item);
}

static IGMedia *sciMediaFromContext(id ctx) {
	id itemContext = sciSend0(ctx, @selector(storyItemContext));
	id item = sciSend0(itemContext, @selector(storyItem));
	return sciMediaFromItem(item);
}

static IGMedia *sciMediaFromStoryCell(UIView *view) {
	Class cls = NSClassFromString(@"IGStoryFullscreenCell");
	if (!cls) return nil;

	while (view && ![view isKindOfClass:cls]) {
		view = view.superview;
	}

	if (!view) return nil;

	id itemContext = sciSend0(view, @selector(currentStoryItemContext));
	IGMedia *media = sciMediaFromItem(sciSend0(itemContext, @selector(storyItem)));
	if (media) return media;

	media = sciMediaFromContext(sciSend0(view, @selector(currentSectionContext)));
	if (media) return media;

	return sciMediaFromContext(sciSend0(view, @selector(sectionContext)));
}

static IGMedia *sciCurrentStoryMedia(UIView *anchor) {
	IGMedia *media = anchor.window ? sciMediaFromStoryCell(anchor) : nil;
	if (media) return media;

	UIViewController *vc = anchor ? sciFindVC(anchor, @"IGStoryViewerViewController") : nil;
	vc = vc ?: sciActiveStoryViewerVC;
	if (!vc) return nil;

	media = sciMediaFromItem(sciSend0(vc, @selector(currentStoryItem)));
	if (media) return media;

	id section = sciSend0(vc, @selector(currentlyDisplayedSectionController));
	media = sciMediaFromItem(sciSend0(section, @selector(currentStoryItem)));
	if (media) return media;

	id vm = sciSend0(vc, @selector(currentViewModel));
	return sciMediaFromItem(sciSend1(vc, @selector(currentStoryItemForViewModel:), vm));
}

static NSString *sciMediaKey(IGMedia *media) {
	return sciString(sciSend0(media, @selector(pk)) ?: sciField(media, @"pk") ?: sciField(media, @"id"));
}

static NSString *sciStoryOwnerPK(IGMedia *media) {
	return sciUserPK(sciField(media, @"user") ?: sciSend0(media, @selector(user)));
}

// MARK: - Mentions + shared media

static NSArray *sciDirectMentions(IGMedia *media) {
	if (!media) return nil;

	id value = sciSend0(media, @selector(storyMentions)) ?: sciSend0(media, @selector(reelMentions));
	if ([value isKindOfClass:NSArray.class]) return value;

	value = sciField(media, @"story_mentions") ?: sciField(media, @"reel_mentions");
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSArray *sciStoryFeedMedia(IGMedia *media) {
	if (!media) return nil;

	id value = sciSend0(media, NSSelectorFromString(@"storyFeedMedia")) ?: sciField(media, @"story_feed_media");
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static void sciAddPK(NSMutableSet<NSString *> *set, NSString *pk, NSString *ownerPK) {
	if (!pk.length) return;
	if (ownerPK.length && [pk isEqualToString:ownerPK]) return;

	[set addObject:pk];
}

static void sciCollectAPIItemPKs(NSDictionary *item, NSString *ownerPK, NSMutableSet<NSString *> *out) {
	if (![item isKindOfClass:NSDictionary.class] || !out) return;

	sciAddPK(out, sciPKFromAPIUser(item[@"user"]), ownerPK);

	NSDictionary *userTags = item[@"usertags"];
	NSArray *tagged = [userTags isKindOfClass:NSDictionary.class] ? userTags[@"in"] : nil;

	for (NSDictionary *tag in tagged) {
		if ([tag isKindOfClass:NSDictionary.class]) {
			sciAddPK(out, sciPKFromAPIUser(tag[@"user"]), ownerPK);
		}
	}

	for (NSString *key in @[@"coauthor_producers", @"invited_coauthor_producers"]) {
		for (NSDictionary *user in item[key]) {
			if ([user isKindOfClass:NSDictionary.class]) {
				sciAddPK(out, sciPKFromAPIUser(user), ownerPK);
			}
		}
	}

	for (NSDictionary *child in item[@"carousel_media"]) {
		sciCollectAPIItemPKs(child, ownerPK, out);
	}
}

static NSMutableDictionary<NSString *, NSSet<NSString *> *> *sciSharedCache(void) {
	static NSMutableDictionary *cache;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		cache = NSMutableDictionary.dictionary;
	});

	return cache;
}

static NSMutableSet<NSString *> *sciSharedInFlight(void) {
	static NSMutableSet *set;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		set = NSMutableSet.set;
	});

	return set;
}

static void sciClearVisibleMentionCaches(void) {
	UIView *root = sciActiveStoryViewerVC.view;
	if (!root) return;

	Class cls = NSClassFromString(@"IGStoryFullscreenOverlayView") ?: NSClassFromString(@"IGStoryFullscreenOverlayMetalLayerView");
	if (!cls) return;

	SEL refresh = NSSelectorFromString(@"sciRefreshStoryMentionsButton");
	SEL kick = NSSelectorFromString(@"sciKickMentionsRetryChain");

	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];

	while (stack.count) {
		UIView *view = stack.lastObject;
		[stack removeLastObject];

		if ([view isKindOfClass:cls]) {
			objc_setAssociatedObject(view, &kMediaKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
			objc_setAssociatedObject(view, &kPKCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

			if ([view respondsToSelector:refresh]) {
				((void (*)(id, SEL))objc_msgSend)(view, refresh);
			}

			if ([view respondsToSelector:kick]) {
				((void (*)(id, SEL))objc_msgSend)(view, kick);
			}
		}

		[stack addObjectsFromArray:view.subviews];
	}
}

static void sciFetchSharedTags(NSString *mediaId, NSString *ownerPK) {
	if (!mediaId.length || !ownerPK.length) return;

	NSMutableSet *inFlight = sciSharedInFlight();
	NSMutableDictionary *cache = sciSharedCache();

	@synchronized(inFlight) {
		if (cache[mediaId] || [inFlight containsObject:mediaId]) return;
		[inFlight addObject:mediaId];
	}

	[SCIInstagramAPI fetchMediaInfoForMediaId:mediaId completion:^(NSDictionary *response, NSError *error) {
		NSMutableSet *set = NSMutableSet.set;
		NSArray *items = response[@"items"];

		if ([items isKindOfClass:NSArray.class] && items.count) {
			sciCollectAPIItemPKs(items.firstObject, ownerPK, set);
		}

		@synchronized(inFlight) {
			[inFlight removeObject:mediaId];
			if (response || !error) cache[mediaId] = set.copy;
		}

		if (set.count) {
			dispatch_async(dispatch_get_main_queue(), ^{
				sciClearVisibleMentionCaches();
			});
		}
	}];
}

static NSArray<NSString *> *sciSharedMediaIDs(IGMedia *media) {
	NSMutableArray *ids = NSMutableArray.array;

	for (id item in sciStoryFeedMedia(media)) {
		NSString *mediaId = sciString(sciSend0(item, NSSelectorFromString(@"mediaId")));

		if (mediaId.length && ![ids containsObject:mediaId]) {
			[ids addObject:mediaId];
		}
	}

	return ids.count ? ids.copy : nil;
}

static void sciCollectSharedPKs(IGMedia *media, NSMutableSet<NSString *> *out) {
	if (!media || !out) return;

	NSString *ownerPK = sciStoryOwnerPK(media);
	if (!ownerPK.length) return;

	for (id item in sciStoryFeedMedia(media)) {
		NSString *owner = sciString(sciSend0(item, NSSelectorFromString(@"mediaOwnerId")));
		NSString *mediaId = sciString(sciSend0(item, NSSelectorFromString(@"mediaId")));

		if (!owner.length) {
			NSString *compound = sciString(sciSend0(item, NSSelectorFromString(@"mediaCompoundStr")));
			NSRange r = [compound rangeOfString:@"_" options:NSBackwardsSearch];

			if (r.location != NSNotFound && r.location + 1 < compound.length) {
				owner = [compound substringFromIndex:r.location + 1];
			}
		}

		sciAddPK(out, owner, ownerPK);

		NSSet *cached = mediaId.length ? sciSharedCache()[mediaId] : nil;

		if ([cached isKindOfClass:NSSet.class]) {
			[out unionSet:cached];
		} else {
			sciFetchSharedTags(mediaId, ownerPK);
		}
	}
}

static NSSet<NSString *> *sciMentionPKSetForMedia(IGMedia *media) {
	if (!media) return NSSet.set;

	NSMutableSet *set = NSMutableSet.set;

	for (id mention in sciDirectMentions(media)) {
		NSDictionary *info = sciInfoFromMention(mention);
		NSString *pk = info[@"pk"] ?: sciUserPK(info[@"userObj"]);

		if (pk.length) {
			[set addObject:pk];
		}
	}

	sciCollectSharedPKs(media, set);

	return set.copy;
}

static NSSet<NSString *> *sciStoryMentionPKSet(UIView *anchor) {
	if (!anchor || !anchor.window) return NSSet.set;

	@try {
		IGMedia *media = sciCurrentStoryMedia(anchor);
		NSString *key = sciMediaKey(media);
		NSString *oldKey = objc_getAssociatedObject(anchor, &kMediaKey);
		NSSet *cached = objc_getAssociatedObject(anchor, &kPKCacheKey);

		if (key.length && cached && [oldKey isEqualToString:key]) {
			return cached;
		}

		NSSet *set = sciMentionPKSetForMedia(media);

		if (key.length) {
			objc_setAssociatedObject(anchor, &kMediaKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
			objc_setAssociatedObject(anchor, &kPKCacheKey, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}

		return set;
	} @catch (__unused id e) {
		return NSSet.set;
	}
}

NSInteger sciStoryMentionsCount(UIView *anchor) {
	return sciStoryMentionPKSet(anchor).count;
}

BOOL sciStoryHasMentionsOrShares(UIView *anchor) {
	return sciStoryMentionPKSet(anchor).count > 0;
}

// MARK: - Sheet

@interface SCIStoryMentionsVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSArray<NSDictionary *> *userInfos;
@property (nonatomic, copy) NSArray<NSString *> *sharedMediaIDs;
@property (nonatomic, copy) NSString *storyAuthorPK;
@property (nonatomic, copy) NSString *currentUsername;
@property (nonatomic, copy) NSString *currentUserPK;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *friendshipStatuses;
@property (nonatomic, strong) NSMutableSet<NSString *> *seenPKs;
@property (nonatomic, strong) UIActivityIndicatorView *loader;
@property (nonatomic, strong) UIStackView *emptyStack;
@property (nonatomic, assign) NSInteger inFlightFetches;
@end

@implementation SCIStoryMentionsVC

- (void)viewDidLoad {
	[super viewDidLoad];

	@try {
		id session = [SCIUtils activeUserSession];
		self.currentUsername = sciString(sciSend0(sciSend0(session, @selector(user)), @selector(username)));
	} @catch (__unused id e) {}

	self.currentUserPK = [SCIUtils currentUserPK];
	self.seenPKs = NSMutableSet.set;
	self.friendshipStatuses = NSMutableDictionary.dictionary;

	for (NSDictionary *info in self.userInfos) {
		NSString *pk = info[@"pk"] ?: sciUserPK(info[@"userObj"]);

		if (pk.length) {
			[self.seenPKs addObject:pk];
		}
	}

	UIColor *bg = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
		return tc.userInterfaceStyle == UIUserInterfaceStyleDark
			? [UIColor colorWithWhite:0.09 alpha:1.0]
			: [UIColor colorWithWhite:0.98 alpha:1.0];
	}];

	self.view.backgroundColor = bg;

	UILabel *title = [[UILabel alloc] init];
	title.text = SCILocalized(@"Mentions");
	title.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
	title.textColor = UIColor.labelColor;
	title.textAlignment = NSTextAlignmentCenter;
	title.translatesAutoresizingMaskIntoConstraints = NO;

	UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
	[close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
	close.tintColor = UIColor.secondaryLabelColor;
	close.translatesAutoresizingMaskIntoConstraints = NO;
	[close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];

	UIView *sep = [[UIView alloc] init];
	sep.backgroundColor = UIColor.separatorColor;
	sep.translatesAutoresizingMaskIntoConstraints = NO;

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = kRowHeight;
	self.tableView.backgroundColor = bg;
	self.tableView.separatorColor = UIColor.separatorColor;
	self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 82.0, 0.0, 0.0);
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;

	UIImageView *emptyIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"at" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:36.0 weight:UIImageSymbolWeightLight]]];
	emptyIcon.tintColor = UIColor.tertiaryLabelColor;

	UILabel *emptyLabel = [[UILabel alloc] init];
	emptyLabel.text = SCILocalized(@"No mentions in this story");
	emptyLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
	emptyLabel.textColor = UIColor.secondaryLabelColor;

	self.emptyStack = [[UIStackView alloc] initWithArrangedSubviews:@[emptyIcon, emptyLabel]];
	self.emptyStack.axis = UILayoutConstraintAxisVertical;
	self.emptyStack.spacing = 12.0;
	self.emptyStack.alignment = UIStackViewAlignmentCenter;
	self.emptyStack.hidden = YES;
	self.emptyStack.translatesAutoresizingMaskIntoConstraints = NO;

	self.loader = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.loader.color = UIColor.secondaryLabelColor;
	self.loader.hidesWhenStopped = YES;
	self.loader.translatesAutoresizingMaskIntoConstraints = NO;

	[self.view addSubview:title];
	[self.view addSubview:close];
	[self.view addSubview:sep];
	[self.view addSubview:self.tableView];
	[self.view addSubview:self.emptyStack];
	[self.view addSubview:self.loader];

	[NSLayoutConstraint activateConstraints:@[
		[title.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:22.0],
		[title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
		[close.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
		[close.widthAnchor constraintEqualToConstant:30.0],
		[close.heightAnchor constraintEqualToConstant:30.0],

		[sep.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14.0],
		[sep.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[sep.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[sep.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],

		[self.tableView.topAnchor constraintEqualToAnchor:sep.bottomAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.emptyStack.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
		[self.emptyStack.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],

		[self.loader.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
		[self.loader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
	]];

	[self fetchSharedPostUsers];
	[self fetchFriendshipStatuses:self.userInfos];
	[self refreshState];
}

- (void)refreshState {
	BOOL pending = self.inFlightFetches > 0;

	if (pending) {
		[self.loader startAnimating];
	} else {
		[self.loader stopAnimating];
	}

	self.emptyStack.hidden = self.userInfos.count > 0 || pending;
}

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)appendInfo:(NSDictionary *)info {
	NSString *pk = info[@"pk"] ?: sciUserPK(info[@"userObj"]);

	if (!pk.length || [self.seenPKs containsObject:pk]) return NO;
	if ([pk isEqualToString:self.currentUserPK] || [pk isEqualToString:self.storyAuthorPK]) return NO;

	[self.seenPKs addObject:pk];

	NSMutableArray *all = self.userInfos.mutableCopy ?: NSMutableArray.array;
	[all addObject:info];
	self.userInfos = all.copy;

	[self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:all.count - 1 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];

	return YES;
}

- (void)collectInfosFromAPIItem:(NSDictionary *)item into:(NSMutableArray *)out {
	if (![item isKindOfClass:NSDictionary.class] || !out) return;

	NSDictionary *owner = sciInfoFromAPIUser(item[@"user"]);
	if (owner) [out addObject:owner];

	NSDictionary *userTags = item[@"usertags"];
	NSArray *tagged = [userTags isKindOfClass:NSDictionary.class] ? userTags[@"in"] : nil;

	for (NSDictionary *tag in tagged) {
		NSDictionary *info = [tag isKindOfClass:NSDictionary.class] ? sciInfoFromAPIUser(tag[@"user"]) : nil;

		if (info) {
			[out addObject:info];
		}
	}

	for (NSString *key in @[@"coauthor_producers", @"invited_coauthor_producers"]) {
		for (NSDictionary *user in item[key]) {
			NSDictionary *info = sciInfoFromAPIUser(user);

			if (info) {
				[out addObject:info];
			}
		}
	}

	for (NSDictionary *child in item[@"carousel_media"]) {
		[self collectInfosFromAPIItem:child into:out];
	}
}

- (void)fetchFriendshipStatuses:(NSArray<NSDictionary *> *)infos {
	NSMutableArray *pks = NSMutableArray.array;

	for (NSDictionary *info in infos) {
		NSString *pk = info[@"pk"] ?: sciUserPK(info[@"userObj"]);

		if (pk.length) {
			[pks addObject:pk];
		}
	}

	if (!pks.count) return;

	__weak typeof(self) weakSelf = self;

	[SCIInstagramAPI fetchFriendshipStatusesForPKs:pks completion:^(NSDictionary *statuses, NSError *error) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !statuses.count) return;

		[self.friendshipStatuses addEntriesFromDictionary:statuses];
		[self.tableView reloadData];
	}];
}

- (void)fetchSharedPostUsers {
	for (NSString *mediaId in self.sharedMediaIDs) {
		if (!mediaId.length) continue;

		self.inFlightFetches++;
		__weak typeof(self) weakSelf = self;

		[SCIInstagramAPI fetchMediaInfoForMediaId:mediaId completion:^(NSDictionary *response, NSError *error) {
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;

			self.inFlightFetches--;

			NSMutableArray *collected = NSMutableArray.array;
			NSMutableArray *newInfos = NSMutableArray.array;
			NSArray *items = response[@"items"];

			if ([items isKindOfClass:NSArray.class] && items.count) {
				[self collectInfosFromAPIItem:items.firstObject into:collected];
			}

			for (NSDictionary *info in collected) {
				if ([self appendInfo:info]) {
					[newInfos addObject:info];
				}
			}

			[self refreshState];
			[self fetchFriendshipStatuses:newInfos];
		}];
	}

	[self refreshState];
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];

	if ([sciActiveStoryViewerVC respondsToSelector:@selector(tryResumePlayback)]) {
		((void (*)(id, SEL))objc_msgSend)(sciActiveStoryViewerVC, @selector(tryResumePlayback));
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.userInfos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuseID = @"mention";
	static NSInteger avTag = 101, nameTag = 102, subTag = 103, followTag = 104, spinTag = 105;

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];

	UIImageView *avatar = nil;
	UILabel *name = nil;
	UILabel *sub = nil;
	UIButton *follow = nil;
	UIActivityIndicatorView *spin = nil;

	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];
		cell.backgroundColor = UIColor.clearColor;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		avatar = [[UIImageView alloc] init];
		avatar.tag = avTag;
		avatar.layer.cornerRadius = kAvatarSize / 2.0;
		avatar.clipsToBounds = YES;
		avatar.contentMode = UIViewContentModeScaleAspectFill;
		avatar.backgroundColor = UIColor.secondarySystemBackgroundColor;
		avatar.translatesAutoresizingMaskIntoConstraints = NO;

		name = [[UILabel alloc] init];
		name.tag = nameTag;
		name.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
		name.textColor = UIColor.labelColor;

		sub = [[UILabel alloc] init];
		sub.tag = subTag;
		sub.font = [UIFont systemFontOfSize:14.0];
		sub.textColor = UIColor.secondaryLabelColor;

		UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[name, sub]];
		text.axis = UILayoutConstraintAxisVertical;
		text.spacing = 2.0;
		text.translatesAutoresizingMaskIntoConstraints = NO;

		follow = [UIButton buttonWithType:UIButtonTypeSystem];
		follow.tag = followTag;
		follow.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
		follow.layer.cornerRadius = 8.0;
		follow.clipsToBounds = YES;
		follow.translatesAutoresizingMaskIntoConstraints = NO;

		spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
		spin.tag = spinTag;
		spin.color = UIColor.whiteColor;
		spin.hidesWhenStopped = YES;
		spin.translatesAutoresizingMaskIntoConstraints = NO;

		[cell.contentView addSubview:avatar];
		[cell.contentView addSubview:text];
		[cell.contentView addSubview:follow];
		[follow addSubview:spin];

		[NSLayoutConstraint activateConstraints:@[
			[avatar.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
			[avatar.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
			[avatar.widthAnchor constraintEqualToConstant:kAvatarSize],
			[avatar.heightAnchor constraintEqualToConstant:kAvatarSize],

			[text.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:14.0],
			[text.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
			[text.trailingAnchor constraintLessThanOrEqualToAnchor:follow.leadingAnchor constant:-10.0],

			[follow.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
			[follow.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
			[follow.widthAnchor constraintGreaterThanOrEqualToConstant:90.0],
			[follow.heightAnchor constraintEqualToConstant:32.0],

			[spin.centerXAnchor constraintEqualToAnchor:follow.centerXAnchor],
			[spin.centerYAnchor constraintEqualToAnchor:follow.centerYAnchor],
		]];
	} else {
		avatar = [cell.contentView viewWithTag:avTag];
		name = [cell.contentView viewWithTag:nameTag];
		sub = [cell.contentView viewWithTag:subTag];
		follow = [cell.contentView viewWithTag:followTag];
		spin = [follow viewWithTag:spinTag];
	}

	NSDictionary *info = self.userInfos[indexPath.row];

	NSString *username = info[@"username"] ?: SCILocalized(@"Unknown user");
	NSString *fullName = info[@"fullName"];
	NSString *pk = info[@"pk"] ?: sciUserPK(info[@"userObj"]);
	NSURL *picURL = info[@"picURL"];

	name.text = username;
	sub.text = fullName ?: @"";
	sub.hidden = !fullName.length;

	avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
	avatar.tintColor = UIColor.tertiaryLabelColor;

	if (picURL) {
		NSString *expected = picURL.absoluteString;
		objc_setAssociatedObject(avatar, &kAvatarURLKey, expected, OBJC_ASSOCIATION_COPY_NONATOMIC);

		[SCIImageCache loadImageFromURL:picURL completion:^(UIImage *image) {
			if (!image) return;

			dispatch_async(dispatch_get_main_queue(), ^{
				if (![objc_getAssociatedObject(avatar, &kAvatarURLKey) isEqualToString:expected]) return;

				avatar.image = image;
				avatar.tintColor = nil;
			});
		}];
	}

	[follow removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
	[spin stopAnimating];

	BOOL isMe = self.currentUserPK.length ? [pk isEqualToString:self.currentUserPK] : [username isEqualToString:self.currentUsername];

	follow.hidden = isMe;
	if (isMe) return cell;

	BOOL following = [self.friendshipStatuses[pk][@"following"] boolValue];
	sciStyleFollow(follow, following);

	objc_setAssociatedObject(follow, &kFollowUserKey, info[@"userObj"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(follow, &kFollowPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);

	[follow addTarget:self action:@selector(followTapped:) forControlEvents:UIControlEventTouchUpInside];

	return cell;
}

- (void)followTapped:(UIButton *)sender {
	NSString *pk = sciUserPK(objc_getAssociatedObject(sender, &kFollowUserKey)) ?: objc_getAssociatedObject(sender, &kFollowPKKey);
	if (!pk.length) return;

	BOOL following = [[sender titleForState:UIControlStateNormal] isEqualToString:SCILocalized(@"Following")];

	void (^run)(void) = ^{
		UIActivityIndicatorView *spin = [sender viewWithTag:105];
		NSString *oldTitle = [sender titleForState:UIControlStateNormal];

		[sender setTitle:@"" forState:UIControlStateNormal];
		sender.userInteractionEnabled = NO;
		[spin startAnimating];

		__weak typeof(self) weakSelf = self;

		SCIAPICompletion done = ^(NSDictionary *response, NSError *error) {
			__strong typeof(weakSelf) self = weakSelf;

			[spin stopAnimating];
			sender.userInteractionEnabled = YES;

			if (!response || ![response[@"status"] isEqualToString:@"ok"]) {
				[sender setTitle:oldTitle forState:UIControlStateNormal];
				return;
			}

			BOOL newFollowing = !following;
			sciStyleFollow(sender, newFollowing);

			NSMutableDictionary *status = [self.friendshipStatuses[pk] mutableCopy] ?: NSMutableDictionary.dictionary;
			status[@"following"] = @(newFollowing);
			self.friendshipStatuses[pk] = status.copy;
		};

		if (following) {
			[SCIInstagramAPI unfollowUserPK:pk completion:done];
		} else {
			[SCIInstagramAPI followUserPK:pk completion:done];
		}
	};

	if (!following && [SCIUtils getBoolPref:@"follow_confirm"]) {
		[SCIUtils showConfirmation:run title:SCILocalized(@"Confirm follow")];
	} else if (following && [SCIUtils getBoolPref:@"unfollow_confirm"]) {
		[SCIUtils showConfirmation:run title:SCILocalized(@"Confirm unfollow")];
	} else {
		run();
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *username = self.userInfos[indexPath.row][@"username"];

	if (username.length) {
		[SCIURLOpener dismiss:self thenOpenInstagramProfileForUsername:username];
	}
}

@end

// MARK: - Entry points

void sciShowStoryMentions(UIViewController *presenter, UIView *anchor) {
	if (![SCIUtils getBoolPref:@"view_story_mentions"] || !presenter) return;

	IGMedia *media = sciCurrentStoryMedia(anchor);
	NSMutableArray *infos = NSMutableArray.array;
	NSMutableSet *seen = NSMutableSet.set;

	for (id mention in sciDirectMentions(media)) {
		NSDictionary *info = sciInfoFromMention(mention);
		NSString *pk = info[@"pk"] ?: sciUserPK(info[@"userObj"]);

		if (!pk.length || [seen containsObject:pk]) continue;

		[seen addObject:pk];
		[infos addObject:info];
	}

	SCIStoryMentionsVC *vc = [[SCIStoryMentionsVC alloc] init];
	vc.userInfos = infos.copy;
	vc.sharedMediaIDs = sciSharedMediaIDs(media);
	vc.storyAuthorPK = sciStoryOwnerPK(media);
	vc.modalPresentationStyle = UIModalPresentationPageSheet;

	UISheetPresentationController *sheet = vc.sheetPresentationController;
	sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
	sheet.prefersGrabberVisible = YES;
	sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;

	[presenter presentViewController:vc animated:YES completion:nil];
}

SCIStoryMenuEntry *sciStoryMentionsMenuEntry(void) {
	UIViewController *vc = sciActiveStoryViewerVC;
	if (!vc || ![SCIUtils getBoolPref:@"view_story_mentions"]) return nil;
	if (!sciStoryHasMentionsOrShares(vc.view)) return nil;

	__weak UIViewController *weakVC = vc;
	return [SCIStoryMenuEntry entryWithTitle:SCILocalized(@"View mentions") symbol:@"at" handler:^{
		UIViewController *v = weakVC;
		if (v) sciShowStoryMentions(v, v.view);
	}];
}
