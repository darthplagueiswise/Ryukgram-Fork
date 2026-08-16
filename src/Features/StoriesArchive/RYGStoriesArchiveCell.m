#import "RYGStoriesArchiveCell.h"
#import "../../Settings/RYGSymbol.h"

static NSCache *rygThumbCache(void) {
	static NSCache *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 200; });
	return cache;
}

static NSDateFormatter *rygDayMonthFmt(void) {
	static NSDateFormatter *f;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ f = [NSDateFormatter new]; f.dateFormat = @"d MMM"; });
	return f;
}

@interface RYGStoriesArchiveCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *videoBadge;
@property (nonatomic, strong) UIView *datePill;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIView *statPill;
@property (nonatomic, strong) UIImageView *eyeIcon;
@property (nonatomic, strong) UILabel *viewsLabel;
@property (nonatomic, strong) UIImageView *heartIcon;
@property (nonatomic, strong) UILabel *likesLabel;
@property (nonatomic, strong) UIView *checkBadge;
@property (nonatomic, copy) NSString *token;
@end

@implementation RYGStoriesArchiveCell

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	self.contentView.clipsToBounds = YES;
	self.contentView.layer.cornerRadius = 12;
	self.contentView.backgroundColor = [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.4];

	_imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
	_imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_imageView.contentMode = UIViewContentModeScaleAspectFill;
	_imageView.clipsToBounds = YES;
	[self.contentView addSubview:_imageView];

	_videoBadge = [[UIImageView alloc] init];
	_videoBadge.translatesAutoresizingMaskIntoConstraints = NO;
	_videoBadge.image = [RYGSymbol symbolWithIGName:@"ig_icon_reels_pano_prism_filled_24" fallback:@"play.fill" color:UIColor.whiteColor size:15].image;
	_videoBadge.tintColor = UIColor.whiteColor;
	_videoBadge.hidden = YES;
	_videoBadge.layer.shadowColor = UIColor.blackColor.CGColor;
	_videoBadge.layer.shadowOpacity = 0.5;
	_videoBadge.layer.shadowRadius = 3;
	_videoBadge.layer.shadowOffset = CGSizeZero;
	[self.contentView addSubview:_videoBadge];

	_datePill = [self pill];
	_dateLabel = [UILabel new];
	_dateLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
	_dateLabel.textColor = UIColor.whiteColor;
	_dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[_datePill addSubview:_dateLabel];
	[self.contentView addSubview:_datePill];

	_statPill = [self pill];
	_eyeIcon = [self statIcon:@"ig_icon_eye_filled_24" fallback:@"eye.fill" color:UIColor.whiteColor box:13];
	_viewsLabel = [self statLabel];
	_heartIcon = [self statIcon:@"ig_icon_heart_filled_24" fallback:@"heart.fill" color:UIColor.whiteColor box:11];
	_likesLabel = [self statLabel];
	UIStackView *statRow = [[UIStackView alloc] initWithArrangedSubviews:@[_eyeIcon, _viewsLabel, _heartIcon, _likesLabel]];
	statRow.axis = UILayoutConstraintAxisHorizontal;
	statRow.alignment = UIStackViewAlignmentCenter;
	statRow.spacing = 3;
	[statRow setCustomSpacing:7 afterView:_viewsLabel];
	statRow.translatesAutoresizingMaskIntoConstraints = NO;
	[_statPill addSubview:statRow];
	[self.contentView addSubview:_statPill];

	_checkBadge = [[UIView alloc] init];
	_checkBadge.translatesAutoresizingMaskIntoConstraints = NO;
	_checkBadge.backgroundColor = UIColor.systemBlueColor;
	_checkBadge.layer.cornerRadius = 11;
	_checkBadge.layer.borderWidth = 2;
	_checkBadge.layer.borderColor = UIColor.whiteColor.CGColor;
	_checkBadge.hidden = YES;
	UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]];
	check.tintColor = UIColor.whiteColor;
	check.translatesAutoresizingMaskIntoConstraints = NO;
	check.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold];
	[_checkBadge addSubview:check];
	[self.contentView addSubview:_checkBadge];

	[NSLayoutConstraint activateConstraints:@[
		[_videoBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:7],
		[_videoBadge.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:7],
		[_videoBadge.widthAnchor constraintEqualToConstant:16],
		[_videoBadge.heightAnchor constraintEqualToConstant:16],

		[_datePill.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
		[_datePill.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6],
		[_datePill.heightAnchor constraintEqualToConstant:18],
		[_dateLabel.leadingAnchor constraintEqualToAnchor:_datePill.leadingAnchor constant:7],
		[_dateLabel.trailingAnchor constraintEqualToAnchor:_datePill.trailingAnchor constant:-7],
		[_dateLabel.centerYAnchor constraintEqualToAnchor:_datePill.centerYAnchor],

		[_statPill.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:6],
		[_statPill.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
		[_statPill.heightAnchor constraintEqualToConstant:20],
		[statRow.leadingAnchor constraintEqualToAnchor:_statPill.leadingAnchor constant:7],
		[statRow.trailingAnchor constraintEqualToAnchor:_statPill.trailingAnchor constant:-8],
		[statRow.centerYAnchor constraintEqualToAnchor:_statPill.centerYAnchor],

		[_checkBadge.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
		[_checkBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6],
		[_checkBadge.widthAnchor constraintEqualToConstant:22],
		[_checkBadge.heightAnchor constraintEqualToConstant:22],
		[check.centerXAnchor constraintEqualToAnchor:_checkBadge.centerXAnchor],
		[check.centerYAnchor constraintEqualToAnchor:_checkBadge.centerYAnchor],
	]];
	return self;
}

- (UIView *)pill {
	UIView *v = [UIView new];
	v.translatesAutoresizingMaskIntoConstraints = NO;
	v.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.55];
	v.layer.cornerRadius = 9;
	return v;
}

- (UIImageView *)statIcon:(NSString *)ig fallback:(NSString *)fb color:(UIColor *)color box:(CGFloat)box {
	UIImageView *iv = [[UIImageView alloc] initWithImage:[RYGSymbol symbolWithIGName:ig fallback:fb color:color size:box - 1].image];
	iv.tintColor = color;
	iv.contentMode = UIViewContentModeScaleAspectFit;
	[iv.widthAnchor constraintEqualToConstant:box].active = YES;
	[iv.heightAnchor constraintEqualToConstant:box].active = YES;
	return iv;
}

- (UILabel *)statLabel {
	UILabel *l = [UILabel new];
	l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
	l.textColor = UIColor.whiteColor;
	return l;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	_imageView.image = nil;
	_token = nil;
	[self setChecked:NO];
}

- (void)setChecked:(BOOL)checked {
	_checkBadge.hidden = !checked;
	self.contentView.layer.borderWidth = checked ? 2.5 : 0;
	self.contentView.layer.borderColor = UIColor.systemBlueColor.CGColor;
	self.imageView.alpha = checked ? 0.78 : 1.0;
}

- (void)configureDate:(NSDate *)date {
	if (date) {
		self.dateLabel.text = [rygDayMonthFmt() stringFromDate:date].uppercaseString;
		self.datePill.hidden = NO;
	} else {
		self.datePill.hidden = YES;
	}
}

- (void)configureWithThumbnailPath:(NSString *)thumbPath
                           isVideo:(BOOL)isVideo
                       viewerCount:(NSInteger)viewerCount
                         likeCount:(NSInteger)likeCount {
	_videoBadge.hidden = !isVideo;

	BOOL hasLikes = likeCount > 0;
	_viewsLabel.text = [NSString stringWithFormat:@"%ld", (long)viewerCount];
	_heartIcon.hidden = !hasLikes;
	_likesLabel.hidden = !hasLikes;
	_likesLabel.text = hasLikes ? [NSString stringWithFormat:@"%ld", (long)likeCount] : @"";

	NSString *token = [thumbPath copy] ?: @"";
	_token = token;

	UIImage *cached = thumbPath ? [rygThumbCache() objectForKey:thumbPath] : nil;
	if (cached) { _imageView.image = cached; return; }
	if (!thumbPath) return;

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		UIImage *img = [UIImage imageWithContentsOfFile:thumbPath];
		if (!img) return;
		[rygThumbCache() setObject:img forKey:thumbPath];
		dispatch_async(dispatch_get_main_queue(), ^{
			if ([self.token isEqualToString:token]) self.imageView.image = img;
		});
	});
}

@end
