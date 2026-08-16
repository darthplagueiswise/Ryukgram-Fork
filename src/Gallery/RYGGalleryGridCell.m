#import "RYGGalleryGridCell.h"
#import "RYGGalleryFile.h"
#import "RYGAssetUtils.h"
#import "../Utils.h"
#import "RYGGalleryShim.h"

static CGFloat const kRYGGalleryGridCornerRadius = 6.0;
static CGFloat const kRYGGalleryGridBadgeInset = 6.0;
static CGFloat const kRYGGalleryGridInfoHeight = 26.0;
static CGFloat const kRYGGalleryGridDateMinWidth = 108.0;

@interface RYGGalleryGridCell ()

@property (nonatomic, strong) RYGGalleryFile *file;
@property (nonatomic, copy) NSString *reuseToken;

@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIView *mediaBadge;
@property (nonatomic, strong) UIImageView *mediaBadgeIcon;
@property (nonatomic, strong) UIImageView *selectionBadge;

@property (nonatomic, strong) UIView *dateChip;
@property (nonatomic, strong) UILabel *dateLabel;

@property (nonatomic, strong) UIView *infoOverlay;
@property (nonatomic, strong) CAGradientLayer *infoGradient;
@property (nonatomic, strong) UIImageView *sourceIcon;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UIImageView *favoriteBadge;

@property (nonatomic, assign) BOOL hasDate;
@property (nonatomic, assign) BOOL selectionActive;

@end

@implementation RYGGalleryGridCell

#pragma mark - Init

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	self.contentView.clipsToBounds = YES;
	self.contentView.layer.cornerRadius = kRYGGalleryGridCornerRadius;
	self.contentView.backgroundColor = UIColor.secondarySystemBackgroundColor;

	[self setupThumbnail];
	[self setupInfoOverlay];
	[self setupBadges];
	[self setupDateChip];
	[self setupConstraints];

	return self;
}

#pragma mark - Setup

- (void)setupThumbnail {
	self.thumbnailView = UIImageView.new;
	self.thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
	self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
	self.thumbnailView.clipsToBounds = YES;
	[self.contentView addSubview:self.thumbnailView];
}

- (void)setupInfoOverlay {
	self.infoOverlay = UIView.new;
	self.infoOverlay.translatesAutoresizingMaskIntoConstraints = NO;
	self.infoOverlay.userInteractionEnabled = NO;
	self.infoOverlay.hidden = YES;
	[self.contentView addSubview:self.infoOverlay];

	self.infoGradient = CAGradientLayer.layer;
	self.infoGradient.colors = @[
		(id)UIColor.clearColor.CGColor,
		(id)[UIColor.blackColor colorWithAlphaComponent:0.65].CGColor,
	];
	self.infoGradient.startPoint = CGPointMake(0.5, 0.0);
	self.infoGradient.endPoint = CGPointMake(0.5, 1.0);
	[self.infoOverlay.layer addSublayer:self.infoGradient];

	self.sourceIcon = UIImageView.new;
	self.sourceIcon.translatesAutoresizingMaskIntoConstraints = NO;
	self.sourceIcon.contentMode = UIViewContentModeScaleAspectFit;
	self.sourceIcon.tintColor = UIColor.whiteColor;
	[self.infoOverlay addSubview:self.sourceIcon];

	self.infoLabel = UILabel.new;
	self.infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.infoLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightSemibold];
	self.infoLabel.textColor = UIColor.whiteColor;
	self.infoLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	self.infoLabel.adjustsFontSizeToFitWidth = YES;
	self.infoLabel.minimumScaleFactor = 0.85;
	self.infoLabel.shadowColor = [UIColor.blackColor colorWithAlphaComponent:0.5];
	self.infoLabel.shadowOffset = CGSizeMake(0.0, 0.5);
	[self.infoOverlay addSubview:self.infoLabel];

	self.favoriteBadge = UIImageView.new;
	self.favoriteBadge.translatesAutoresizingMaskIntoConstraints = NO;
	self.favoriteBadge.contentMode = UIViewContentModeScaleAspectFit;
	self.favoriteBadge.image = [RYGAssetUtils instagramIconNamed:@"heart_filled" pointSize:13.0];
	self.favoriteBadge.tintColor = [RYGUtils RYGColor_InstagramFavorite];
	self.favoriteBadge.hidden = YES;
	[self.infoOverlay addSubview:self.favoriteBadge];
}

- (void)setupBadges {
	self.mediaBadge = UIView.new;
	self.mediaBadge.translatesAutoresizingMaskIntoConstraints = NO;
	self.mediaBadge.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.55];
	self.mediaBadge.layer.cornerRadius = 9.0;
	self.mediaBadge.layer.cornerCurve = kCACornerCurveContinuous;
	self.mediaBadge.hidden = YES;
	[self.contentView addSubview:self.mediaBadge];

	self.mediaBadgeIcon = UIImageView.new;
	self.mediaBadgeIcon.translatesAutoresizingMaskIntoConstraints = NO;
	self.mediaBadgeIcon.contentMode = UIViewContentModeScaleAspectFit;
	self.mediaBadgeIcon.tintColor = UIColor.whiteColor;
	[self.mediaBadge addSubview:self.mediaBadgeIcon];

	self.selectionBadge = UIImageView.new;
	self.selectionBadge.translatesAutoresizingMaskIntoConstraints = NO;
	self.selectionBadge.contentMode = UIViewContentModeScaleAspectFit;
	self.selectionBadge.tintColor = UIColor.whiteColor;
	self.selectionBadge.hidden = YES;
	self.selectionBadge.layer.shadowColor = UIColor.blackColor.CGColor;
	self.selectionBadge.layer.shadowOpacity = 0.35;
	self.selectionBadge.layer.shadowRadius = 2.0;
	self.selectionBadge.layer.shadowOffset = CGSizeMake(0.0, 1.0);
	[self.contentView addSubview:self.selectionBadge];
}

- (void)setupDateChip {
	self.dateChip = UIView.new;
	self.dateChip.translatesAutoresizingMaskIntoConstraints = NO;
	self.dateChip.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.55];
	self.dateChip.layer.cornerRadius = 8.0;
	self.dateChip.layer.cornerCurve = kCACornerCurveContinuous;
	self.dateChip.hidden = YES;
	[self.contentView addSubview:self.dateChip];

	self.dateLabel = UILabel.new;
	self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.dateLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightSemibold];
	self.dateLabel.textColor = UIColor.whiteColor;
	[self.dateChip addSubview:self.dateLabel];
}

- (void)setupConstraints {
	[NSLayoutConstraint activateConstraints:@[
		[self.thumbnailView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
		[self.thumbnailView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
		[self.thumbnailView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
		[self.thumbnailView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

		[self.infoOverlay.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
		[self.infoOverlay.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
		[self.infoOverlay.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
		[self.infoOverlay.heightAnchor constraintEqualToConstant:kRYGGalleryGridInfoHeight],

		[self.sourceIcon.leadingAnchor constraintEqualToAnchor:self.infoOverlay.leadingAnchor constant:5.0],
		[self.sourceIcon.bottomAnchor constraintEqualToAnchor:self.infoOverlay.bottomAnchor constant:-5.0],
		[self.sourceIcon.widthAnchor constraintEqualToConstant:11.0],
		[self.sourceIcon.heightAnchor constraintEqualToConstant:11.0],

		[self.infoLabel.leadingAnchor constraintEqualToAnchor:self.sourceIcon.trailingAnchor constant:3.0],
		[self.infoLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.favoriteBadge.leadingAnchor constant:-4.0],
		[self.infoLabel.centerYAnchor constraintEqualToAnchor:self.sourceIcon.centerYAnchor],

		[self.favoriteBadge.trailingAnchor constraintEqualToAnchor:self.infoOverlay.trailingAnchor constant:-5.0],
		[self.favoriteBadge.centerYAnchor constraintEqualToAnchor:self.sourceIcon.centerYAnchor],
		[self.favoriteBadge.widthAnchor constraintEqualToConstant:13.0],
		[self.favoriteBadge.heightAnchor constraintEqualToConstant:13.0],

		[self.mediaBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kRYGGalleryGridBadgeInset],
		[self.mediaBadge.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kRYGGalleryGridBadgeInset],
		[self.mediaBadge.widthAnchor constraintEqualToConstant:18.0],
		[self.mediaBadge.heightAnchor constraintEqualToConstant:18.0],

		[self.mediaBadgeIcon.centerXAnchor constraintEqualToAnchor:self.mediaBadge.centerXAnchor],
		[self.mediaBadgeIcon.centerYAnchor constraintEqualToAnchor:self.mediaBadge.centerYAnchor],
		[self.mediaBadgeIcon.widthAnchor constraintEqualToConstant:11.0],
		[self.mediaBadgeIcon.heightAnchor constraintEqualToConstant:11.0],

		[self.dateChip.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kRYGGalleryGridBadgeInset],
		[self.dateChip.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kRYGGalleryGridBadgeInset],
		[self.dateChip.heightAnchor constraintEqualToConstant:16.0],

		[self.dateLabel.leadingAnchor constraintEqualToAnchor:self.dateChip.leadingAnchor constant:5.0],
		[self.dateLabel.trailingAnchor constraintEqualToAnchor:self.dateChip.trailingAnchor constant:-5.0],
		[self.dateLabel.centerYAnchor constraintEqualToAnchor:self.dateChip.centerYAnchor],

		[self.selectionBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kRYGGalleryGridBadgeInset],
		[self.selectionBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kRYGGalleryGridBadgeInset],
		[self.selectionBadge.widthAnchor constraintEqualToConstant:20.0],
		[self.selectionBadge.heightAnchor constraintEqualToConstant:20.0],
	]];
}

#pragma mark - Layout / Reuse

- (void)layoutSubviews {
	[super layoutSubviews];
	self.infoGradient.frame = self.infoOverlay.bounds;
	[self updateDateChipVisibility];
}

- (void)updateDateChipVisibility {
	BOOL fits = self.contentView.bounds.size.width >= kRYGGalleryGridDateMinWidth;
	self.dateChip.hidden = !(self.hasDate && fits && !self.selectionActive);
}

- (void)prepareForReuse {
	[super prepareForReuse];

	self.file = nil;
	self.reuseToken = nil;
	self.hasDate = NO;
	self.selectionActive = NO;

	self.thumbnailView.image = nil;

	self.mediaBadge.hidden = YES;
	self.mediaBadgeIcon.image = nil;

	self.dateChip.hidden = YES;
	self.dateLabel.text = nil;

	self.selectionBadge.hidden = YES;
	self.selectionBadge.alpha = 0.0;
	self.selectionBadge.image = nil;

	self.infoOverlay.hidden = YES;
	self.sourceIcon.image = nil;
	self.infoLabel.text = nil;
	self.favoriteBadge.hidden = YES;
}

#pragma mark - Configure

- (void)configureWithGalleryFile:(RYGGalleryFile *)file
				   selectionMode:(BOOL)selectionMode
						selected:(BOOL)selected {
	self.file = file;
	self.reuseToken = file.identifier ?: file.relativePath ?: file.thumbnailPath ?: NSUUID.UUID.UUIDString;

	[self updateThumbnailForFile:file token:self.reuseToken];
	[self updateMediaBadgeForFile:file];
	[self updateDateChipForFile:file];
	[self updateInfoOverlayForFile:file];
	[self setSelectionMode:selectionMode selected:selected animated:NO];
}

- (void)updateThumbnailForFile:(RYGGalleryFile *)file token:(NSString *)token {
	UIImage *thumbnail = [RYGGalleryFile loadThumbnailForFile:file];
	if (thumbnail) {
		self.thumbnailView.image = thumbnail;
		return;
	}

	self.thumbnailView.image = nil;

	__weak typeof(self) weakSelf = self;
	[RYGGalleryFile generateThumbnailForFile:file completion:^(BOOL success) {
		if (!success) return;

		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self || ![self.reuseToken isEqualToString:token]) return;

			UIImage *image = [UIImage imageWithContentsOfFile:file.thumbnailPath];
			if (image) self.thumbnailView.image = image;
		});
	}];
}

- (void)updateMediaBadgeForFile:(RYGGalleryFile *)file {
	NSString *icon = nil;

	switch (file.mediaType) {
		case RYGGalleryMediaTypeVideo:	icon = @"video"; break;
		case RYGGalleryMediaTypeAudio:	icon = @"audio"; break;
		case RYGGalleryMediaTypeGIF:	icon = @"gif";   break;
		case RYGGalleryMediaTypeImage:
		default:						break;
	}

	self.mediaBadgeIcon.image = icon.length ? [RYGAssetUtils instagramIconNamed:icon pointSize:11.0] : nil;
	self.mediaBadge.hidden = icon.length == 0;
}

- (void)updateDateChipForFile:(RYGGalleryFile *)file {
	NSString *text = [self chipDateStringForDate:file.dateAdded];
	self.hasDate = text.length > 0;
	self.dateLabel.text = text;
	[self updateDateChipVisibility];
}

- (NSString *)chipDateStringForDate:(NSDate *)date {
	if (!date) return nil;

	static NSDateFormatter *sameYear;
	static NSDateFormatter *otherYear;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sameYear = [NSDateFormatter new];
		sameYear.dateFormat = @"MMM d";
		otherYear = [NSDateFormatter new];
		otherYear.dateFormat = @"MMM d, yyyy";
	});

	NSCalendar *cal = NSCalendar.currentCalendar;
	NSInteger nowYear = [cal component:NSCalendarUnitYear fromDate:NSDate.date];
	NSInteger dateYear = [cal component:NSCalendarUnitYear fromDate:date];
	return [(dateYear == nowYear ? sameYear : otherYear) stringFromDate:date];
}

- (void)updateInfoOverlayForFile:(RYGGalleryFile *)file {
	RYGGallerySource source = (RYGGallerySource)file.source;
	NSString *sourceText = source == RYGGallerySourceOther ? nil : [RYGGalleryFile shortLabelForSource:source];
	NSString *username = file.sourceUsername.length ? [@"@" stringByAppendingString:file.sourceUsername] : nil;

	BOOL hasText = sourceText.length || username.length;
	self.favoriteBadge.hidden = !file.isFavorite;

	if (!hasText && !file.isFavorite) {
		self.infoOverlay.hidden = YES;
		return;
	}

	if (sourceText.length && username.length) {
		self.infoLabel.text = [NSString stringWithFormat:@"%@ · %@", sourceText, username];
	} else {
		self.infoLabel.text = sourceText ?: username;
	}

	self.sourceIcon.image = hasText
		? [RYGAssetUtils instagramIconNamed:[RYGGalleryFile symbolNameForSource:source] pointSize:11.0]
		: nil;
	self.sourceIcon.hidden = !hasText;
	self.infoOverlay.hidden = NO;
}

#pragma mark - Selection

- (UIImage *)selectionBadgeImageSelected:(BOOL)selected {
	return [RYGAssetUtils selectionCheckmarkSelected:selected pointSize:20.0];
}

- (void)setSelectionMode:(BOOL)selectionMode selected:(BOOL)selected animated:(BOOL)animated {
	self.selectionActive = selectionMode;
	self.selectionBadge.image = selectionMode ? [self selectionBadgeImageSelected:selected] : nil;
	self.selectionBadge.hidden = !selectionMode && !animated;
	[self updateDateChipVisibility];

	void (^changes)(void) = ^{
		self.selectionBadge.alpha = selectionMode ? 1.0 : 0.0;
		[self.contentView layoutIfNeeded];
	};

	void (^completion)(BOOL) = ^(BOOL finished) {
		(void)finished;
		self.selectionBadge.hidden = !selectionMode;
	};

	if (!animated) {
		changes();
		completion(YES);
		return;
	}

	[UIView animateWithDuration:0.20
						  delay:0.0
						options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
					 animations:changes
					 completion:completion];
}

@end
