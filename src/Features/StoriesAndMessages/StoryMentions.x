// View story mentions — direct @mentions + shared post/reel sticker users.

#import "../../Utils.h"
#import "../../RYGProfileOpener.h"
#import "../../InstagramHeaders.h"
#import "../../RYGImageCache.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "StoryHelpers.h"
#import "StoryMenuItems.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern __weak UIViewController *rygActiveStoryViewerVC;

static char kPKCacheKey;
static char kMediaKey;
static char kAvatarURLKey;
static char kFollowUserKey;
static char kFollowPKKey;

#define kAvatarSize 52.0
#define kRowHeight  72.0

#define rygField(obj, key) [RYGUtils fieldCacheValue:(obj) forKey:(key)]

static id rygSend0(id obj, SEL sel) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static id rygSend1(id obj, SEL sel, id arg) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
	} @catch (__unused id e) {
		return nil;
	}
}

static NSString *rygString(id value) {
	if ([value isKindOfClass:NSString.class]) return [(NSString *)value length] ? value : nil;
	if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
	return nil;
}

static NSString *rygUserPK(id user) {
	return rygString(rygField(user, @"strong_id__") ?: rygField(user, @"pk") ?: rygSend0(user, @selector(pk)) ?: [RYGUtils pkFromIGUser:user]);
}

static NSDictionary *rygInfoFromUser(id user) {
	if (!user) return nil;

	NSString *pk = rygUserPK(user);
	NSString *username = rygString(rygField(user, @"username") ?: rygSend0(user, @selector(username)));
	NSString *fullName = rygString(rygField(user, @"full_name") ?: rygSend0(user, @selector(fullName)));
	NSString *pic = rygString(rygField(user, @"profile_pic_url") ?: rygSend0(user, @selector(profilePicURL)));

	if (!pk.length && !username.length) return nil;

	NSMutableDictionary *info = [@{ @"userObj": user } mutableCopy];

	if (pk.length) info[@"pk"] = pk;
	if (username.length) info[@"username"] = username;
	if (fullName.length) info[@"fullName"] = fullName;

	NSURL *url = pic.length ? [NSURL URLWithString:pic] : nil;
	if (url) info[@"picURL"] = url;

	return info.copy;
}

static NSDictionary *rygInfoFromMention(id mention) {
	if (!mention) return nil;

	id user = nil;

	@try {
		user = [mention valueForKey:@"user"];
	} @catch (__unused id e) {}

	return rygInfoFromUser(user ?: rygSend0(mention, @selector(user)));
}

static NSString *rygPKFromAPIUser(NSDictionary *user) {
	if (![user isKindOfClass:NSDictionary.class]) return nil;
	return rygString(user[@"pk"] ?: user[@"pk_id"] ?: user[@"id"]);
}

static NSDictionary *rygInfoFromAPIUser(NSDictionary *user) {
	NSString *pk = rygPKFromAPIUser(user);
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

static void rygStyleFollow(UIButton *btn, BOOL following) {
	[btn setTitle:following ? RYGLocalized(@"Following") : RYGLocalized(@"Follow") forState:UIControlStateNormal];
	btn.backgroundColor = following ? UIColor.tertiarySystemFillColor : UIColor.systemBlueColor;
	[btn setTitleColor:following ? UIColor.labelColor : UIColor.whiteColor forState:UIControlStateNormal];
}

// MARK: - Story media

static IGMedia *rygMediaFromItem(id item) {
	Class cls = NSClassFromString(@"IGMedia");
	return (cls && [item isKindOfClass:cls]) ? item : rygExtractMediaFromItem(item);
}

static IGMedia *rygMediaFromContext(id ctx) {
	id itemContext = rygSend0(ctx, @selector(storyItemContext));
	id item = rygSend0(itemContext, @selector(storyItem));
	return rygMediaFromItem(item);
}

static IGMedia *rygMediaFromStoryCell(UIView *view) {
	Class cls = NSClassFromString(@"IGStoryFullscreenCell");
	if (!cls) return nil;

	while (view && ![view isKindOfClass:cls]) {
		view = view.superview;
	}

	if (!view) return nil;

	id itemContext = rygSend0(view, @selector(currentStoryItemContext));
	IGMedia *media = rygMediaFromItem(rygSend0(itemContext, @selector(storyItem)));
	if (media) return media;

	media = rygMediaFromContext(rygSend0(view, @selector(currentSectionContext)));
	if (media) return media;

	return rygMediaFromContext(rygSend0(view, @selector(sectionContext)));
}

static IGMedia *rygCurrentStoryMedia(UIView *anchor) {
	IGMedia *media = anchor.window ? rygMediaFromStoryCell(anchor) : nil;
	if (media) return media;

	UIViewController *vc = anchor ? rygFindVC(anchor, @"IGStoryViewerViewController") : nil;
	vc = vc ?: rygActiveStoryViewerVC;
	if (!vc) return nil;

	media = rygMediaFromItem(rygSend0(vc, @selector(currentStoryItem)));
	if (media) return media;

	id section = rygSend0(vc, @selector(currentlyDisplayedSectionController));
	media = rygMediaFromItem(rygSend0(section, @selector(currentStoryItem)));
	if (media) return media;

	id vm = rygSend0(vc, @selector(currentViewModel));
	return rygMediaFromItem(rygSend1(vc, @selector(currentStoryItemForViewModel:), vm));
}

static NSString *rygMediaKey(IGMedia *media) {
	return rygString(rygSend0(media, @selector(pk)) ?: rygField(media, @"pk") ?: rygField(media, @"id"));
}

static NSString *rygStoryOwnerPK(IGMedia *media) {
	return rygUserPK(rygField(media, @"user") ?: rygSend0(media, @selector(user)));
}

// MARK: - Mentions + shared media

static NSArray *rygDirectMentions(IGMedia *media) {
	if (!media) return nil;

	id value = rygSend0(media, @selector(storyMentions)) ?: rygSend0(media, @selector(reelMentions));
	if ([value isKindOfClass:NSArray.class]) return value;

	value = rygField(media, @"story_mentions") ?: rygField(media, @"reel_mentions");
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSArray *rygStoryFeedMedia(IGMedia *media) {
	if (!media) return nil;

	id value = rygSend0(media, NSSelectorFromString(@"storyFeedMedia")) ?: rygField(media, @"story_feed_media");
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static void rygAddPK(NSMutableSet<NSString *> *set, NSString *pk, NSString *ownerPK) {
	if (!pk.length) return;
	if (ownerPK.length && [pk isEqualToString:ownerPK]) return;

	[set addObject:pk];
}

static void rygCollectAPIItemPKs(NSDictionary *item, NSString *ownerPK, NSMutableSet<NSString *> *out) {
	if (![item isKindOfClass:NSDictionary.class] || !out) return;

	rygAddPK(out, rygPKFromAPIUser(item[@"user"]), ownerPK);

	NSDictionary *userTags = item[@"usertags"];
	NSArray *tagged = [userTags isKindOfClass:NSDictionary.class] ? userTags[@"in"] : nil;

	for (NSDictionary *tag in tagged) {
		if ([tag isKindOfClass:NSDictionary.class]) {
			rygAddPK(out, rygPKFromAPIUser(tag[@"user"]), ownerPK);
		}
	}

	for (NSString *key in @[@"coauthor_producers", @"invited_coauthor_producers"]) {
		for (NSDictionary *user in item[key]) {
			if ([user isKindOfClass:NSDictionary.class]) {
				rygAddPK(out, rygPKFromAPIUser(user), ownerPK);
			}
		}
	}

	for (NSDictionary *child in item[@"carousel_media"]) {
		rygCollectAPIItemPKs(child, ownerPK, out);
	}
}

static NSMutableDictionary<NSString *, NSSet<NSString *> *> *rygSharedCache(void) {
	static NSMutableDictionary *cache;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		cache = NSMutableDictionary.dictionary;
	});

	return cache;
}

static NSMutableSet<NSString *> *rygSharedInFlight(void) {
	static NSMutableSet *set;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		set = NSMutableSet.set;
	});

	return set;
}

static void rygClearVisibleMentionCaches(void) {
	UIView *root = rygActiveStoryViewerVC.view;
	if (!root) return;

	Class cls = NSClassFromString(@"IGStoryFullscreenOverlayView") ?: NSClassFromString(@"IGStoryFullscreenOverlayMetalLayerView");
	if (!cls) return;

	SEL refresh = NSSelectorFromString(@"rygRefreshStoryMentionsButton");
	SEL kick = NSSelectorFromString(@"rygKickMentionsRetryChain");

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

static void rygFetchSharedTags(NSString *mediaId, NSString *ownerPK) {
	if (!mediaId.length || !ownerPK.length) return;

	NSMutableSet *inFlight = rygSharedInFlight();
	NSMutableDictionary *cache = rygSharedCache();

	@synchronized(inFlight) {
		if (cache[mediaId] || [inFlight containsObject:mediaId]) return;
		[inFlight addObject:mediaId];
	}

	[RYGInstagramAPI fetchMediaInfoForMediaId:mediaId completion:^(NSDictionary *response, NSError *error) {
		NSMutableSet *set = NSMutableSet.set;
		NSArray *items = response[@"items"];

		if ([items isKindOfClass:NSArray.class] && items.count) {
			rygCollectAPIItemPKs(items.firstObject, ownerPK, set);
		}

		@synchronized(inFlight) {
			[inFlight removeObject:mediaId];
			if (response || !error) cache[mediaId] = set.copy;
		}

		if (set.count) {
			dispatch_async(dispatch_get_main_queue(), ^{
				rygClearVisibleMentionCaches();
			});
		}
	}];
}

static NSArray<NSString *> *rygSharedMediaIDs(IGMedia *media) {
	NSMutableArray *ids = NSMutableArray.array;

	for (id item in rygStoryFeedMedia(media)) {
		NSString *mediaId = rygString(rygSend0(item, NSSelectorFromString(@"mediaId")));

		if (mediaId.length && ![ids containsObject:mediaId]) {
			[ids addObject:mediaId];
		}
	}

	return ids.count ? ids.copy : nil;
}

static void rygCollectSharedPKs(IGMedia *media, NSMutableSet<NSString *> *out) {
	if (!media || !out) return;

	NSString *ownerPK = rygStoryOwnerPK(media);
	if (!ownerPK.length) return;

	for (id item in rygStoryFeedMedia(media)) {
		NSString *owner = rygString(rygSend0(item, NSSelectorFromString(@"mediaOwnerId")));
		NSString *mediaId = rygString(rygSend0(item, NSSelectorFromString(@"mediaId")));

		if (!owner.length) {
			NSString *compound = rygString(rygSend0(item, NSSelectorFromString(@"mediaCompoundStr")));
			NSRange r = [compound rangeOfString:@"_" options:NSBackwardsSearch];

			if (r.location != NSNotFound && r.location + 1 < compound.length) {
				owner = [compound substringFromIndex:r.location + 1];
			}
		}

		rygAddPK(out, owner, ownerPK);

		NSSet *cached = mediaId.length ? rygSharedCache()[mediaId] : nil;

		if ([cached isKindOfClass:NSSet.class]) {
			[out unionSet:cached];
		} else {
			rygFetchSharedTags(mediaId, ownerPK);
		}
	}
}

static NSSet<NSString *> *rygMentionPKSetForMedia(IGMedia *media) {
	if (!media) return NSSet.set;

	NSMutableSet *set = NSMutableSet.set;

	for (id mention in rygDirectMentions(media)) {
		NSDictionary *info = rygInfoFromMention(mention);
		NSString *pk = info[@"pk"] ?: rygUserPK(info[@"userObj"]);

		if (pk.length) {
			[set addObject:pk];
		}
	}

	rygCollectSharedPKs(media, set);

	return set.copy;
}

static NSSet<NSString *> *rygStoryMentionPKSet(UIView *anchor) {
	if (!anchor || !anchor.window) return NSSet.set;

	@try {
		IGMedia *media = rygCurrentStoryMedia(anchor);
		NSString *key = rygMediaKey(media);
		NSString *oldKey = objc_getAssociatedObject(anchor, &kMediaKey);
		NSSet *cached = objc_getAssociatedObject(anchor, &kPKCacheKey);

		if (key.length && cached && [oldKey isEqualToString:key]) {
			return cached;
		}

		NSSet *set = rygMentionPKSetForMedia(media);

		if (key.length) {
			objc_setAssociatedObject(anchor, &kMediaKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
			objc_setAssociatedObject(anchor, &kPKCacheKey, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}

		return set;
	} @catch (__unused id e) {
		return NSSet.set;
	}
}

NSInteger rygStoryMentionsCount(UIView *anchor) {
	return rygStoryMentionPKSet(anchor).count;
}

BOOL rygStoryHasMentionsOrShares(UIView *anchor) {
	return rygStoryMentionPKSet(anchor).count > 0;
}

// MARK: - Sheet

@interface RYGStoryMentionsVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
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

@implementation RYGStoryMentionsVC

- (void)viewDidLoad {
	[super viewDidLoad];

	@try {
		id session = [RYGUtils activeUserSession];
		self.currentUsername = rygString(rygSend0(rygSend0(session, @selector(user)), @selector(username)));
	} @catch (__unused id e) {}

	self.currentUserPK = [RYGUtils currentUserPK];
	self.seenPKs = NSMutableSet.set;
	self.friendshipStatuses = NSMutableDictionary.dictionary;

	for (NSDictionary *info in self.userInfos) {
		NSString *pk = info[@"pk"] ?: rygUserPK(info[@"userObj"]);

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
	title.text = RYGLocalized(@"Mentions");
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
	emptyLabel.text = RYGLocalized(@"No mentions in this story");
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
	NSString *pk = info[@"pk"] ?: rygUserPK(info[@"userObj"]);

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

	NSDictionary *owner = rygInfoFromAPIUser(item[@"user"]);
	if (owner) [out addObject:owner];

	NSDictionary *userTags = item[@"usertags"];
	NSArray *tagged = [userTags isKindOfClass:NSDictionary.class] ? userTags[@"in"] : nil;

	for (NSDictionary *tag in tagged) {
		NSDictionary *info = [tag isKindOfClass:NSDictionary.class] ? rygInfoFromAPIUser(tag[@"user"]) : nil;

		if (info) {
			[out addObject:info];
		}
	}

	for (NSString *key in @[@"coauthor_producers", @"invited_coauthor_producers"]) {
		for (NSDictionary *user in item[key]) {
			NSDictionary *info = rygInfoFromAPIUser(user);

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
		NSString *pk = info[@"pk"] ?: rygUserPK(info[@"userObj"]);

		if (pk.length) {
			[pks addObject:pk];
		}
	}

	if (!pks.count) return;

	__weak typeof(self) weakSelf = self;

	[RYGInstagramAPI fetchFriendshipStatusesForPKs:pks completion:^(NSDictionary *statuses, NSError *error) {
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

		[RYGInstagramAPI fetchMediaInfoForMediaId:mediaId completion:^(NSDictionary *response, NSError *error) {
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

	if ([rygActiveStoryViewerVC respondsToSelector:@selector(tryResumePlayback)]) {
		((void (*)(id, SEL))objc_msgSend)(rygActiveStoryViewerVC, @selector(tryResumePlayback));
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

	NSString *username = info[@"username"] ?: RYGLocalized(@"Unknown user");
	NSString *fullName = info[@"fullName"];
	NSString *pk = info[@"pk"] ?: rygUserPK(info[@"userObj"]);
	NSURL *picURL = info[@"picURL"];

	name.text = username;
	sub.text = fullName ?: @"";
	sub.hidden = !fullName.length;

	avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
	avatar.tintColor = UIColor.tertiaryLabelColor;

	if (picURL) {
		NSString *expected = picURL.absoluteString;
		objc_setAssociatedObject(avatar, &kAvatarURLKey, expected, OBJC_ASSOCIATION_COPY_NONATOMIC);

		[RYGImageCache loadImageFromURL:picURL completion:^(UIImage *image) {
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
	rygStyleFollow(follow, following);

	objc_setAssociatedObject(follow, &kFollowUserKey, info[@"userObj"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(follow, &kFollowPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);

	[follow addTarget:self action:@selector(followTapped:) forControlEvents:UIControlEventTouchUpInside];

	return cell;
}

- (void)followTapped:(UIButton *)sender {
	NSString *pk = rygUserPK(objc_getAssociatedObject(sender, &kFollowUserKey)) ?: objc_getAssociatedObject(sender, &kFollowPKKey);
	if (!pk.length) return;

	BOOL following = [[sender titleForState:UIControlStateNormal] isEqualToString:RYGLocalized(@"Following")];

	void (^run)(void) = ^{
		UIActivityIndicatorView *spin = [sender viewWithTag:105];
		NSString *oldTitle = [sender titleForState:UIControlStateNormal];

		[sender setTitle:@"" forState:UIControlStateNormal];
		sender.userInteractionEnabled = NO;
		[spin startAnimating];

		__weak typeof(self) weakSelf = self;

		RYGAPICompletion done = ^(NSDictionary *response, NSError *error) {
			__strong typeof(weakSelf) self = weakSelf;

			[spin stopAnimating];
			sender.userInteractionEnabled = YES;

			if (!response || ![response[@"status"] isEqualToString:@"ok"]) {
				[sender setTitle:oldTitle forState:UIControlStateNormal];
				return;
			}

			BOOL newFollowing = !following;
			rygStyleFollow(sender, newFollowing);

			NSMutableDictionary *status = [self.friendshipStatuses[pk] mutableCopy] ?: NSMutableDictionary.dictionary;
			status[@"following"] = @(newFollowing);
			self.friendshipStatuses[pk] = status.copy;
		};

		if (following) {
			[RYGInstagramAPI unfollowUserPK:pk completion:done];
		} else {
			[RYGInstagramAPI followUserPK:pk completion:done];
		}
	};

	if (!following && [RYGUtils getBoolPref:@"follow_confirm"]) {
		[RYGUtils showConfirmation:run title:RYGLocalized(@"Confirm follow")];
	} else if (following && [RYGUtils getBoolPref:@"unfollow_confirm"]) {
		[RYGUtils showConfirmation:run title:RYGLocalized(@"Confirm unfollow")];
	} else {
		run();
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *info = self.userInfos[indexPath.row];
	NSString *username = info[@"username"];
	NSString *pk = info[@"pk"];
	if (username.length || pk.length) {
		[RYGProfileOpener openProfileForPK:pk username:username from:self];
	}
}

@end

// MARK: - Entry points

void rygShowStoryMentions(UIViewController *presenter, UIView *anchor) {
	if (![RYGUtils getBoolPref:@"view_story_mentions"] || !presenter) return;

	IGMedia *media = rygCurrentStoryMedia(anchor);
	NSMutableArray *infos = NSMutableArray.array;
	NSMutableSet *seen = NSMutableSet.set;

	for (id mention in rygDirectMentions(media)) {
		NSDictionary *info = rygInfoFromMention(mention);
		NSString *pk = info[@"pk"] ?: rygUserPK(info[@"userObj"]);

		if (!pk.length || [seen containsObject:pk]) continue;

		[seen addObject:pk];
		[infos addObject:info];
	}

	RYGStoryMentionsVC *vc = [[RYGStoryMentionsVC alloc] init];
	vc.userInfos = infos.copy;
	vc.sharedMediaIDs = rygSharedMediaIDs(media);
	vc.storyAuthorPK = rygStoryOwnerPK(media);
	vc.modalPresentationStyle = UIModalPresentationPageSheet;

	UISheetPresentationController *sheet = vc.sheetPresentationController;
	sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
	sheet.prefersGrabberVisible = YES;
	sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;

	[presenter presentViewController:vc animated:YES completion:nil];
}

RYGStoryMenuEntry *rygStoryMentionsMenuEntry(void) {
	UIViewController *vc = rygActiveStoryViewerVC;
	if (!vc || ![RYGUtils getBoolPref:@"view_story_mentions"]) return nil;
	if (!rygStoryHasMentionsOrShares(vc.view)) return nil;

	__weak UIViewController *weakVC = vc;
	return [RYGStoryMenuEntry entryWithTitle:RYGLocalized(@"View mentions") symbol:@"at" handler:^{
		UIViewController *v = weakVC;
		if (v) rygShowStoryMentions(v, v.view);
	}];
}