#import "RYGProfileAnalyzerService.h"
#import "RYGProfileAnalyzerStorage.h"
#import "RYGProfileAnalyzerViewController.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../Utils.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Background/RYGBackgroundActivity.h"
#import "../../UI/Notification/RYGNotificationCenter.h"
#import "../../Localization/RYGLocalization.h"

const NSInteger RYGProfileAnalyzerMaxFollowerCount = 13000;

NSNotificationName const RYGProfileAnalyzerProgressDidChangeNotification   = @"RYGProfileAnalyzerProgressDidChangeNotification";
NSNotificationName const RYGProfileAnalyzerHeaderInfoDidChangeNotification = @"RYGProfileAnalyzerHeaderInfoDidChangeNotification";
NSNotificationName const RYGProfileAnalyzerDidFinishNotification           = @"RYGProfileAnalyzerDidFinishNotification";

#define RYG_PA_PAGE_DELAY_S 0.25   // rate-limit cushion between pages

static NSString *const kRYGPABGSource = @"profile_analyzer";

@interface RYGProfileAnalyzerService () {
@public
	NSInteger _expectedFollowers;
	NSInteger _expectedFollowing;
}
@property (nonatomic, copy) NSString *selfPK;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL isRunning;

@property (nonatomic, copy)   NSString *lastStatus;
@property (nonatomic, assign) double    lastFraction;
@property (nonatomic, copy, nullable) NSDictionary *lastHeaderInfo;

@property (nonatomic, strong, nullable) RYGNotificationHandle *pill;
@property (nonatomic, assign) NSInteger attachedCount;
@end

@implementation RYGProfileAnalyzerService

+ (instancetype)sharedService {
	static RYGProfileAnalyzerService *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [self new]; });
	return s;
}

// Owner class lets the notif center skip the tap when the VC is already up.
+ (void)load {
	[[RYGNotificationCenter shared] setDefaultTapProvider:^void (^(void))(void) {
		return ^{
			UIViewController *top = nil;
			for (UIScene *s in [[UIApplication sharedApplication] connectedScenes]) {
				if (![s isKindOfClass:[UIWindowScene class]]) continue;
				UIWindowScene *ws = (UIWindowScene *)s;
				for (UIWindow *w in ws.windows) {
					if (w.isKeyWindow) { top = w.rootViewController; break; }
				}
				if (top) break;
			}
			while (top.presentedViewController) top = top.presentedViewController;
			if (!top) return;
			[RYGPopupChrome presentVC:[RYGProfileAnalyzerViewController new] from:top];
		};
	} ownerVCClass:[RYGProfileAnalyzerViewController class]
	  forAction:RYG_NOTIF_ANALYZER_RUN];
}

- (instancetype)init {
	if ((self = [super init])) {
		_lastStatus = @"";
		_lastFraction = 0.0;
	}
	return self;
}

- (void)cancel { self.cancelled = YES; }

#pragma mark - Observer attach / detach

- (void)attachObserver {
	dispatch_block_t block = ^{
		self.attachedCount += 1;
		if (self.attachedCount == 1 && self.isRunning) {
			// Silent drop — no terminal flash since VC will repaint state.
			[self.pill dismiss];
			self.pill = nil;
		}
	};
	NSThread.isMainThread ? block() : dispatch_async(dispatch_get_main_queue(), block);
}

- (void)detachObserver {
	dispatch_block_t block = ^{
		if (self.attachedCount > 0) self.attachedCount -= 1;
		if (self.attachedCount == 0 && self.isRunning) [self ensurePill];
	};
	NSThread.isMainThread ? block() : dispatch_async(dispatch_get_main_queue(), block);
}

- (void)ensurePill {
	if (self.pill || self.attachedCount > 0 || !self.isRunning) return;
	__weak typeof(self) weakSelf = self;
	self.pill = RYGNotifyProgress(RYG_NOTIF_ANALYZER_RUN,
	                              RYGLocalized(@"Profile Analyzer"),
	                              ^{ [weakSelf cancel]; });
	[self.pill setProgress:(float)self.lastFraction];
	if (self.lastStatus.length) [self.pill setSubtitle:self.lastStatus];
}

#pragma mark - Run

- (void)start {
	if (self.isRunning) return;

	NSString *pk = [RYGUtils currentUserPK];
	if (!pk.length) {
		[self emitFinishWithSnapshot:nil
		                       error:[self errorWithCode:RYGProfileAnalyzerErrorNoSession
		                                         message:RYGLocalized(@"No active Instagram session found")]];
		return;
	}

	self.selfPK = pk;
	self.isRunning = YES;
	self.cancelled = NO;
	self.lastStatus = RYGLocalized(@"Starting…");
	self.lastFraction = 0.0;
	self.lastHeaderInfo = nil;
	_expectedFollowers = 0;
	_expectedFollowing = 0;

	[RYGBackgroundActivity setSource:kRYGPABGSource active:YES];
	[self ensurePill];

	[self emitProgressStatus:RYGLocalized(@"Fetching profile info…") fraction:0.02];
	[self fetchSelfInfoForPK:pk];
}

- (void)fetchSelfInfoForPK:(NSString *)pk {
	__weak typeof(self) weakSelf = self;
	[RYGInstagramAPI sendRequestWithMethod:@"GET"
	                                  path:[NSString stringWithFormat:@"users/%@/info/", pk]
	                                  body:nil
	                            completion:^(NSDictionary *resp, NSError *error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		if (strongSelf.cancelled) { [strongSelf emitCancelled]; return; }

		NSDictionary *user = [resp[@"user"] isKindOfClass:[NSDictionary class]] ? resp[@"user"] : nil;
		if (!user) {
			[strongSelf emitFinishWithSnapshot:nil
			                             error:[strongSelf errorWithCode:RYGProfileAnalyzerErrorNetwork
			                                                     message:RYGLocalized(@"Couldn't fetch profile information")]];
			return;
		}

		NSInteger followerCount = [user[@"follower_count"] integerValue];
		if (followerCount > RYGProfileAnalyzerMaxFollowerCount) {
			[strongSelf emitFinishWithSnapshot:nil
			                             error:[strongSelf errorWithCode:RYGProfileAnalyzerErrorTooManyFollowers
			                                                     message:RYGLocalized(@"Too many followers to analyze")]];
			return;
		}

		RYGProfileAnalyzerSnapshot *snap = [RYGProfileAnalyzerSnapshot new];
		snap.selfPK = pk;
		snap.selfUsername = user[@"username"];
		snap.selfFullName = user[@"full_name"];
		snap.selfProfilePicURL = user[@"profile_pic_url"];
		snap.followerCount = followerCount;
		snap.followingCount = [user[@"following_count"] integerValue];
		snap.mediaCount = [user[@"media_count"] integerValue];
		snap.scanDate = [NSDate date];

		strongSelf->_expectedFollowers = followerCount;
		strongSelf->_expectedFollowing = snap.followingCount;

		[strongSelf emitHeaderInfo:user];
		[strongSelf fetchFollowersForPK:pk snapshot:snap];
	}];
}

#pragma mark - Paginated fetchers

- (void)fetchFollowersForPK:(NSString *)pk snapshot:(RYGProfileAnalyzerSnapshot *)snap {
	NSMutableArray *acc = [NSMutableArray array];
	[self pagePath:[NSString stringWithFormat:@"friendships/%@/followers/", pk]
	           acc:acc
	         maxId:nil
	         total:snap.followerCount
	         stage:@"followers"
	    completion:^(NSArray *users, NSError *error) {
		if (error || self.cancelled) {
			[self emitFinishWithSnapshot:nil
			                       error:error ?: [self errorWithCode:RYGProfileAnalyzerErrorCancelled
			                                                  message:RYGLocalized(@"Cancelled")]];
			return;
		}
		snap.followers = users;
		[self fetchFollowingForPK:pk snapshot:snap];
	}];
}

- (void)fetchFollowingForPK:(NSString *)pk snapshot:(RYGProfileAnalyzerSnapshot *)snap {
	NSMutableArray *acc = [NSMutableArray array];
	[self pagePath:[NSString stringWithFormat:@"friendships/%@/following/", pk]
	           acc:acc
	         maxId:nil
	         total:snap.followingCount
	         stage:@"following"
	    completion:^(NSArray *users, NSError *error) {
		if (error || self.cancelled) {
			[self emitFinishWithSnapshot:nil
			                       error:error ?: [self errorWithCode:RYGProfileAnalyzerErrorCancelled
			                                                  message:RYGLocalized(@"Cancelled")]];
			return;
		}
		snap.following = users;
		[self emitFinishWithSnapshot:snap error:nil];
	}];
}

- (void)pagePath:(NSString *)basePath
             acc:(NSMutableArray *)acc
           maxId:(NSString *)maxId
           total:(NSInteger)total
           stage:(NSString *)stage
      completion:(void(^)(NSArray *users, NSError *error))completion {
	if (self.cancelled) {
		completion(nil, [self errorWithCode:RYGProfileAnalyzerErrorCancelled message:RYGLocalized(@"Cancelled")]);
		return;
	}
	NSString *path = maxId.length ? [NSString stringWithFormat:@"%@?max_id=%@", basePath, maxId] : basePath;

	__weak typeof(self) weakSelf = self;
	[RYGInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		if (error) { completion(nil, [strongSelf errorWithCode:RYGProfileAnalyzerErrorNetwork message:error.localizedDescription]); return; }

		NSArray *users = resp[@"users"];
		if ([users isKindOfClass:[NSArray class]]) {
			for (id d in users) {
				if (![d isKindOfClass:[NSDictionary class]]) continue;
				RYGProfileAnalyzerUser *u = [RYGProfileAnalyzerUser userFromAPIDict:d];
				if (u) [acc addObject:u];
			}
		}
		// Weight each stage by its share of expected work; 3% reserved for user-info.
		NSInteger followerTarget = strongSelf->_expectedFollowers;
		NSInteger followingTarget = strongSelf->_expectedFollowing;
		double total0 = MAX(1, followerTarget + followingTarget);
		double stageWeight = ([stage isEqualToString:@"followers"] ? followerTarget : followingTarget) / total0;
		double stageOffset = ([stage isEqualToString:@"followers"] ? 0.0 : (double)followerTarget / total0);
		double stageLocal = total > 0 ? MIN(1.0, (double)acc.count / (double)total) : 0;
		double frac = 0.03 + (stageOffset + stageLocal * stageWeight) * 0.97;
		NSString *fmt = [stage isEqualToString:@"followers"]
			? RYGLocalized(@"Fetching followers (%lu/%ld)…")
			: RYGLocalized(@"Fetching following (%lu/%ld)…");
		NSString *label = [NSString stringWithFormat:fmt, (unsigned long)acc.count, (long)total];
		[strongSelf emitProgressStatus:label fraction:frac];

		id next = resp[@"next_max_id"];
		NSString *nextMax = [next isKindOfClass:[NSString class]] ? next : ([next respondsToSelector:@selector(stringValue)] ? [next stringValue] : nil);
		if (!nextMax.length || strongSelf.cancelled) {
			completion(acc, strongSelf.cancelled ? [strongSelf errorWithCode:RYGProfileAnalyzerErrorCancelled message:RYGLocalized(@"Cancelled")] : nil);
			return;
		}
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RYG_PA_PAGE_DELAY_S * NSEC_PER_SEC)),
		               dispatch_get_main_queue(), ^{
			[strongSelf pagePath:basePath acc:acc maxId:nextMax total:total stage:stage completion:completion];
		});
	}];
}

#pragma mark - Emit / finalize

- (NSError *)errorWithCode:(RYGProfileAnalyzerError)code message:(NSString *)msg {
	return [NSError errorWithDomain:@"RYGProfileAnalyzer" code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: msg ?: @"" }];
}

- (void)emitProgressStatus:(NSString *)status fraction:(double)fraction {
	dispatch_block_t block = ^{
		self.lastStatus = status ?: @"";
		self.lastFraction = MAX(0.0, MIN(1.0, fraction));
		[self.pill setProgress:(float)self.lastFraction];
		[self.pill setSubtitle:status];
		NSDictionary *info = @{ @"status": self.lastStatus, @"fraction": @(self.lastFraction) };
		[[NSNotificationCenter defaultCenter] postNotificationName:RYGProfileAnalyzerProgressDidChangeNotification
		                                                    object:self
		                                                  userInfo:info];
	};
	NSThread.isMainThread ? block() : dispatch_async(dispatch_get_main_queue(), block);
}

- (void)emitHeaderInfo:(NSDictionary *)user {
	if (![user isKindOfClass:[NSDictionary class]]) return;
	NSDictionary *snapshot = [user copy];
	dispatch_block_t block = ^{
		self.lastHeaderInfo = snapshot;
		[[NSNotificationCenter defaultCenter] postNotificationName:RYGProfileAnalyzerHeaderInfoDidChangeNotification
		                                                    object:self
		                                                  userInfo:@{ @"user": snapshot }];
	};
	NSThread.isMainThread ? block() : dispatch_async(dispatch_get_main_queue(), block);
}

- (void)emitCancelled {
	[self emitFinishWithSnapshot:nil
	                       error:[self errorWithCode:RYGProfileAnalyzerErrorCancelled
	                                         message:RYGLocalized(@"Cancelled")]];
}

// Persist (success only) → terminal pill / done-toast → flip flags → broadcast.
- (void)emitFinishWithSnapshot:(RYGProfileAnalyzerSnapshot *)snap error:(NSError *)error {
	dispatch_block_t block = ^{
		NSString *pk = self.selfPK;
		if (snap && !error && pk.length) {
			[RYGProfileAnalyzerStorage saveSnapshot:snap forUserPK:pk];
			if ([RYGUtils getBoolPref:@"profile_analyzer_record_snapshots"]) {
				NSInteger cap = (NSInteger)[RYGUtils getDoublePref:@"profile_analyzer_snapshot_cap"];
				[RYGProfileAnalyzerStorage appendSnapshotToHistory:snap forUserPK:pk capacity:cap];
			}
			[RYGProfileAnalyzerStorage saveHeaderInfo:@{
				@"username":         snap.selfUsername     ?: @"",
				@"full_name":        snap.selfFullName     ?: @"",
				@"profile_pic_url":  snap.selfProfilePicURL ?: @"",
				@"follower_count":   @(snap.followerCount),
				@"following_count":  @(snap.followingCount),
				@"media_count":      @(snap.mediaCount),
			} forUserPK:pk];
		}

		// Pill carries its own terminal; without one, VC owns error alerts
		// and only success needs a standalone toast.
		if (self.pill) {
			if (snap && !error) {
				NSString *sub = [NSString stringWithFormat:RYGLocalized(@"%lu followers · %lu following"),
				                 (unsigned long)snap.followers.count, (unsigned long)snap.following.count];
				[self.pill success:RYGLocalized(@"Analysis complete") subtitle:sub];
			} else if (error.code == RYGProfileAnalyzerErrorCancelled) {
				[self.pill cancelled:RYGLocalized(@"Cancelled")];
			} else {
				[self.pill error:RYGLocalized(@"Analysis failed") subtitle:error.localizedDescription];
			}
			self.pill = nil;
		} else if (snap && !error) {
			RYGNotifySuccess(RYG_NOTIF_ANALYZER_DONE,
			                 RYGLocalized(@"Analysis complete"),
			                 [NSString stringWithFormat:RYGLocalized(@"%lu followers · %lu following"),
			                  (unsigned long)snap.followers.count, (unsigned long)snap.following.count]);
		}

		[RYGBackgroundActivity setSource:kRYGPABGSource active:NO];

		self.isRunning = NO;
		self.cancelled = NO;

		NSMutableDictionary *info = [NSMutableDictionary dictionary];
		if (snap)  info[@"snapshot"] = snap;
		if (error) info[@"error"]    = error;
		[[NSNotificationCenter defaultCenter] postNotificationName:RYGProfileAnalyzerDidFinishNotification
		                                                    object:self
		                                                  userInfo:info];
	};
	NSThread.isMainThread ? block() : dispatch_async(dispatch_get_main_queue(), block);
}

@end
