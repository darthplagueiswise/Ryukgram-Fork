#import "RYGGridFeedOverlayView.h"
#import "RYGGridFeedInfo.h"
#import "../../../Utils.h"

@interface RYGGridFeedChip : UIView
@property (nonatomic) CGFloat measuredWidth;
@property (nonatomic, weak) UIImageView *avatarView;
@end

@implementation RYGGridFeedChip
- (instancetype)initWithIcon:(UIImage *)icon avatar:(UIImage *)avatar texts:(NSArray<NSString *> *)texts pointSize:(CGFloat)pt maxWidth:(CGFloat)maxWidth {
	if (!(self = [super initWithFrame:CGRectZero])) return self;
	self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
	CGFloat h = pt + 8;
	self.layer.cornerRadius = h / 2;
	self.clipsToBounds = YES;

	CGFloat iconSize = pt + 1;
	CGFloat leftPad = 5, gap = 3, rightPad = 6, x = leftPad;

	if (avatar) {
		UIImageView *av = [[UIImageView alloc] initWithFrame:CGRectMake(x, (h - iconSize) / 2, iconSize, iconSize)];
		av.image = avatar;
		av.tintColor = [UIColor whiteColor];
		av.contentMode = UIViewContentModeScaleAspectFill;
		av.clipsToBounds = YES;
		av.layer.cornerRadius = iconSize / 2;
		[self addSubview:av];
		self.avatarView = av;
		x += iconSize + gap;
	} else if (icon) {
		UIImageView *iv = [[UIImageView alloc] initWithImage:icon];
		iv.tintColor = [UIColor whiteColor];
		iv.frame = CGRectMake(x, (h - iconSize) / 2, iconSize, iconSize);
		iv.contentMode = UIViewContentModeScaleAspectFit;
		[self addSubview:iv];
		x += iconSize + gap;
	}

	NSString *text = texts.firstObject;
	if (text.length) {
		UIFont *font = [UIFont systemFontOfSize:pt weight:UIFontWeightSemibold];
		CGFloat avail = maxWidth - x - rightPad;
		CGFloat width = 0;
		// Longest variant that fits wins; the ladder's last entry is the short fallback.
		for (NSString *candidate in texts) {
			width = ceil([candidate sizeWithAttributes:@{NSFontAttributeName: font}].width);
			text = candidate;
			if (width <= avail) break;
		}
		UILabel *label = [UILabel new];
		label.font = font;
		label.textColor = [UIColor whiteColor];
		label.text = text;
		label.lineBreakMode = NSLineBreakByTruncatingTail;
		CGFloat lw = MAX(0, MIN(width, avail));
		label.frame = CGRectMake(x, 0, lw, h);
		[self addSubview:label];
		x += lw + rightPad;
	} else {
		x += (rightPad - gap);
	}

	self.measuredWidth = x;
	self.frame = CGRectMake(0, 0, x, h);
	return self;
}
@end

@interface RYGGridFeedOverlayView ()
@property (nonatomic, strong) RYGGridFeedPost *post;
@property (nonatomic, strong) CAGradientLayer *bottomGradient;
@property (nonatomic, strong) CAGradientLayer *topGradient;
@property (nonatomic, strong) UIImageView *typeBadge;
@property (nonatomic, strong) UIImageView *followBadge;
@property (nonatomic, strong) NSMutableArray<RYGGridFeedChip *> *chips;
@property (nonatomic, weak) UIImageView *avatarIV;
@property (nonatomic, strong) UIImage *avatarPlaceholder;
@property (nonatomic, assign) CGFloat lastRebuildWidth;
@end

@implementation RYGGridFeedOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return self;
	self.userInteractionEnabled = NO;
	_chips = [NSMutableArray array];

	_topGradient = [CAGradientLayer layer];
	_topGradient.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.45].CGColor, (id)[UIColor clearColor].CGColor];
	[self.layer addSublayer:_topGradient];

	_bottomGradient = [CAGradientLayer layer];
	_bottomGradient.colors = @[(id)[UIColor clearColor].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.65].CGColor];
	[self.layer addSublayer:_bottomGradient];

	_typeBadge = [UIImageView new];
	_typeBadge.tintColor = [UIColor whiteColor];
	_typeBadge.contentMode = UIViewContentModeScaleAspectFit;
	[self addSubview:_typeBadge];

	_followBadge = [UIImageView new];
	_followBadge.tintColor = [UIColor whiteColor];
	_followBadge.contentMode = UIViewContentModeScaleAspectFit;
	_followBadge.hidden = YES;
	[self addSubview:_followBadge];
	return self;
}

- (void)configureWithPost:(RYGGridFeedPost *)post {
	self.post = post;
	[self rebuild];
}

- (void)setAvatarImage:(UIImage *)avatarImage {
	if (avatarImage == _avatarImage) return;
	_avatarImage = avatarImage;
	if (self.avatarIV) { self.avatarIV.image = avatarImage ?: self.avatarPlaceholder; return; }
	if (!avatarImage || ![RYGGridFeedInfo showAvatar]) return;
	[self rebuild];
}

- (CGFloat)chipPointSize {
	CGFloat w = self.bounds.size.width;
	if (w < 115) return 9;
	if (w < 150) return 10;
	if (w < 190) return 11;
	// Larger tiles (iPad, big cards) scale the chip up so stats stay legible.
	return MIN(16.0, 11.0 + (w - 190.0) / 45.0);
}

- (NSArray<NSString *> *)textsForElement:(NSString *)el shorten:(BOOL)shorten {
	if ([el isEqualToString:kRYGGridInfoDate]) return [RYGGridFeedInfo dateStringsForTimestamp:self.post.takenAt];
	NSString *text = nil;
	if ([el isEqualToString:kRYGGridInfoUsername]) text = self.post.username;
	else if ([el isEqualToString:kRYGGridInfoLikes]) text = self.post.countsHidden ? nil : [RYGUtils formatCount:self.post.likeCount shortened:shorten];
	else if ([el isEqualToString:kRYGGridInfoComments]) text = [RYGUtils formatCount:self.post.commentCount shortened:shorten];
	else if ([el isEqualToString:kRYGGridInfoViews]) text = (self.post.mediaType == RYGGridFeedMediaTypeVideo && self.post.viewCount > 0) ? [RYGUtils formatCount:self.post.viewCount shortened:shorten] : nil;
	else if ([el isEqualToString:kRYGGridInfoShares]) text = self.post.shareCount > 0 ? [RYGUtils formatCount:self.post.shareCount shortened:shorten] : nil;
	return text.length ? @[text] : nil;
}

- (void)rebuild {
	for (RYGGridFeedChip *c in self.chips) [c removeFromSuperview];
	[self.chips removeAllObjects];
	self.avatarIV = nil;
	if (!self.post) return;

	BOOL shorten = [RYGGridFeedInfo shortenedNumbers];
	CGFloat pt = [self chipPointSize];
	BOOL tiny = self.bounds.size.width < 96;
	CGFloat chipMaxW = self.bounds.size.width - 12;

	BOOL wantFollow = [RYGGridFeedInfo isElementEnabled:kRYGGridInfoFollowing] && self.post.isFollowing;
	self.followBadge.image = wantFollow ? [RYGGridFeedInfo iconForElement:kRYGGridInfoFollowing pointSize:13] : nil;
	self.followBadge.hidden = !wantFollow;

	for (NSString *el in [RYGGridFeedInfo orderedEnabledElementIDs]) {
		if ([el isEqualToString:kRYGGridInfoFollowing]) continue;
		NSArray<NSString *> *texts = [self textsForElement:el shorten:shorten];
		if (!texts.count) continue;
		if (tiny && ![el isEqualToString:kRYGGridInfoLikes]) continue;

		UIImage *icon = nil;
		UIImage *avatar = nil;
		BOOL isUser = [el isEqualToString:kRYGGridInfoUsername];
		if (isUser) {
			if ([RYGGridFeedInfo showAvatar]) {
				UIImage *ph = [RYGGridFeedInfo iconNamed:nil symbol:@"person.circle.fill" pointSize:pt];
				self.avatarPlaceholder = ph;
				avatar = self.avatarImage ?: ph;
			} else {
				icon = [RYGGridFeedInfo iconNamed:[RYGGridFeedInfo rowIconForElement:el] symbol:@"person.circle.fill" pointSize:pt];
			}
		} else {
			icon = [RYGGridFeedInfo iconForElement:el pointSize:pt];
		}

		RYGGridFeedChip *chip = [[RYGGridFeedChip alloc] initWithIcon:icon avatar:avatar texts:texts pointSize:pt maxWidth:chipMaxW];
		if (isUser && avatar) self.avatarIV = chip.avatarView;
		[self addSubview:chip];
		[self.chips addObject:chip];
	}

	NSString *ig = nil, *sf = nil;
	if ([RYGGridFeedInfo showTypeBadge]) {
		if (self.post.mediaType == RYGGridFeedMediaTypeCarousel) { ig = @"ig_icon_carousel_prism_filled_16"; sf = @"square.stack.fill"; }
		else if (self.post.mediaType == RYGGridFeedMediaTypeVideo) { ig = @"ig_icon_reels_prism_filled_16"; sf = @"play.fill"; }
	}
	self.typeBadge.image = ig ? [RYGGridFeedInfo iconNamed:ig symbol:sf pointSize:15] : nil;
	self.typeBadge.hidden = (self.typeBadge.image == nil);

	self.lastRebuildWidth = self.bounds.size.width;
	[self setNeedsLayout];
	[self layoutIfNeeded];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
	// Re-chip on width change so every card at a given size renders at the same font.
	if (self.post && W > 0 && fabs(W - self.lastRebuildWidth) > 0.5) { [self rebuild]; return; }
	self.topGradient.frame = CGRectMake(0, 0, W, 30);
	self.bottomGradient.frame = CGRectMake(0, H * 0.45, W, H * 0.55);

	CGFloat bs = 16, bp = 6;
	self.typeBadge.frame = CGRectMake(W - bs - bp, bp, bs, bs);
	self.followBadge.frame = CGRectMake(bp, bp, 14, 14);

	CGFloat pad = 6, rowGap = 3;
	CGFloat maxW = W - pad * 2;
	// Pack in reverse so full rows sit at the bottom and any partial row is on top.
	NSArray *packOrder = [[self.chips reverseObjectEnumerator] allObjects];
	NSMutableArray<NSMutableArray *> *packed = [NSMutableArray array];
	NSMutableArray *cur = [NSMutableArray array];
	CGFloat curW = 0, rowH = 0;
	for (RYGGridFeedChip *chip in packOrder) {
		CGFloat cw = chip.measuredWidth;
		rowH = chip.bounds.size.height;
		if (cur.count && curW + 4 + cw > maxW) { [packed addObject:cur]; cur = [NSMutableArray array]; curW = 0; }
		[cur addObject:chip];
		curW += (cur.count > 1 ? 4 : 0) + cw;
	}
	if (cur.count) [packed addObject:cur];
	NSMutableArray<NSMutableArray *> *rows = [NSMutableArray array];
	for (NSMutableArray *row in [packed reverseObjectEnumerator])
		[rows addObject:[[[row reverseObjectEnumerator] allObjects] mutableCopy]];

	CGFloat maxRows = MAX(1, floor((H * 0.6) / (rowH + rowGap)));
	while ((CGFloat)rows.count > maxRows) {
		for (RYGGridFeedChip *c in rows.lastObject) c.hidden = YES;
		[rows removeLastObject];
	}

	CGFloat totalH = rows.count * rowH + (rows.count - 1) * rowGap;
	CGFloat y = H - pad - totalH;
	for (NSMutableArray *row in rows) {
		CGFloat x = pad;
		for (RYGGridFeedChip *chip in row) {
			chip.hidden = NO;
			chip.frame = CGRectMake(x, y, chip.measuredWidth, rowH);
			x += chip.measuredWidth + 4;
		}
		y += rowH + rowGap;
	}
}

@end
