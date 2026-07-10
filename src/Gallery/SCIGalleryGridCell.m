#import "SCIGalleryGridCell.h"
#import "SCIGalleryFile.h"
#import "SCIAssetUtils.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"

static CGFloat const kSCIGalleryGridCornerRadius = 6.0;
static CGFloat const kSCIGalleryGridBadgeInset = 6.0;
static CGFloat const kSCIGalleryGridInfoHeight = 26.0;

@interface SCIGalleryGridCell ()

@property (nonatomic, strong) SCIGalleryFile *file;
@property (nonatomic, copy) NSString *reuseToken;

@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIImageView *mediaBadge;
@property (nonatomic, strong) UIImageView *favoriteBadge;
@property (nonatomic, strong) UIImageView *selectionBadge;

@property (nonatomic, strong) UIView *infoOverlay;
@property (nonatomic, strong) CAGradientLayer *infoGradient;
@property (nonatomic, strong) UIImageView *sourceIcon;
@property (nonatomic, strong) UILabel *infoLabel;

@property (nonatomic, strong) NSLayoutConstraint *favoriteTrailingConstraint;

@end

@implementation SCIGalleryGridCell

#pragma mark - Init

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	self.contentView.clipsToBounds = YES;
	self.contentView.layer.cornerRadius = kSCIGalleryGridCornerRadius;
	self.contentView.backgroundColor = UIColor.secondarySystemBackgroundColor;

	[self setupThumbnail];
	[self setupInfoOverlay];
	[self setupBadges];
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
}

- (void)setupBadges {
	self.mediaBadge = [self badgeViewWithSize:14.0];
	self.favoriteBadge = [self badgeViewWithSize:16.0];
	self.selectionBadge = [self badgeViewWithSize:20.0];

	self.favoriteBadge.image = [UIImage systemImageNamed:@"heart.fill"];
	self.favoriteBadge.tintColor = [SCIUtils SCIColor_InstagramFavorite];

	[self.contentView addSubview:self.mediaBadge];
	[self.contentView addSubview:self.favoriteBadge];
	[self.contentView addSubview:self.selectionBadge];

	self.favoriteTrailingConstraint = [self.favoriteBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kSCIGalleryGridBadgeInset];
}

- (UIImageView *)badgeViewWithSize:(CGFloat)size {
	UIImageView *view = UIImageView.new;
	view.translatesAutoresizingMaskIntoConstraints = NO;
	view.contentMode = UIViewContentModeScaleAspectFit;
	view.tintColor = UIColor.whiteColor;
	view.hidden = YES;
	return view;
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
		[self.infoOverlay.heightAnchor constraintEqualToConstant:kSCIGalleryGridInfoHeight],

		[self.sourceIcon.leadingAnchor constraintEqualToAnchor:self.infoOverlay.leadingAnchor constant:5.0],
		[self.sourceIcon.bottomAnchor constraintEqualToAnchor:self.infoOverlay.bottomAnchor constant:-5.0],
		[self.sourceIcon.widthAnchor constraintEqualToConstant:10.0],
		[self.sourceIcon.heightAnchor constraintEqualToConstant:10.0],

		[self.infoLabel.leadingAnchor constraintEqualToAnchor:self.sourceIcon.trailingAnchor constant:3.0],
		[self.infoLabel.trailingAnchor constraintEqualToAnchor:self.infoOverlay.trailingAnchor constant:-5.0],
		[self.infoLabel.centerYAnchor constraintEqualToAnchor:self.sourceIcon.centerYAnchor],

		[self.mediaBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kSCIGalleryGridBadgeInset],
		[self.mediaBadge.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kSCIGalleryGridBadgeInset],
		[self.mediaBadge.widthAnchor constraintEqualToConstant:14.0],
		[self.mediaBadge.heightAnchor constraintEqualToConstant:14.0],

		[self.favoriteBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kSCIGalleryGridBadgeInset],
		[self.favoriteBadge.widthAnchor constraintEqualToConstant:16.0],
		[self.favoriteBadge.heightAnchor constraintEqualToConstant:16.0],
		self.favoriteTrailingConstraint,

		[self.selectionBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kSCIGalleryGridBadgeInset],
		[self.selectionBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kSCIGalleryGridBadgeInset],
		[self.selectionBadge.widthAnchor constraintEqualToConstant:20.0],
		[self.selectionBadge.heightAnchor constraintEqualToConstant:20.0],
	]];
}

#pragma mark - Layout / Reuse

- (void)layoutSubviews {
	[super layoutSubviews];
	self.infoGradient.frame = self.infoOverlay.bounds;
}

- (void)prepareForReuse {
	[super prepareForReuse];

	self.file = nil;
	self.reuseToken = nil;

	self.thumbnailView.image = nil;

	self.mediaBadge.hidden = YES;
	self.mediaBadge.image = nil;

	self.favoriteBadge.hidden = YES;
	self.favoriteTrailingConstraint.constant = -kSCIGalleryGridBadgeInset;

	self.selectionBadge.hidden = YES;
	self.selectionBadge.alpha = 0.0;
	self.selectionBadge.image = nil;

	self.infoOverlay.hidden = YES;
	self.sourceIcon.image = nil;
	self.infoLabel.text = nil;
}

#pragma mark - Configure

- (void)configureWithGalleryFile:(SCIGalleryFile *)file
				   selectionMode:(BOOL)selectionMode
						selected:(BOOL)selected {
	self.file = file;
	self.reuseToken = file.identifier ?: file.relativePath ?: file.thumbnailPath ?: NSUUID.UUID.UUIDString;

	[self updateThumbnailForFile:file token:self.reuseToken];
	[self updateMediaBadgeForFile:file];
	[self updateFavoriteBadgeForFile:file];
	[self updateInfoOverlayForFile:file];
	[self setSelectionMode:selectionMode selected:selected animated:NO];
}

- (void)updateThumbnailForFile:(SCIGalleryFile *)file token:(NSString *)token {
	UIImage *thumbnail = [SCIGalleryFile loadThumbnailForFile:file];
	if (thumbnail) {
		self.thumbnailView.image = thumbnail;
		return;
	}

	self.thumbnailView.image = nil;

	__weak typeof(self) weakSelf = self;
	[SCIGalleryFile generateThumbnailForFile:file completion:^(BOOL success) {
		if (!success) return;

		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self || ![self.reuseToken isEqualToString:token]) return;

			UIImage *image = [UIImage imageWithContentsOfFile:file.thumbnailPath];
			if (image) self.thumbnailView.image = image;
		});
	}];
}

- (void)updateMediaBadgeForFile:(SCIGalleryFile *)file {
	NSString *symbol = nil;

	switch (file.mediaType) {
		case SCIGalleryMediaTypeVideo:
			symbol = @"video.fill";
			break;

		case SCIGalleryMediaTypeAudio:
			symbol = @"waveform.circle.fill";
			break;

		case SCIGalleryMediaTypeGIF:
			symbol = @"sparkles";
			break;

		case SCIGalleryMediaTypeImage:
		default:
			break;
	}

	self.mediaBadge.image = symbol.length ? [UIImage systemImageNamed:symbol] : nil;
	self.mediaBadge.hidden = symbol.length == 0;
}

- (void)updateFavoriteBadgeForFile:(SCIGalleryFile *)file {
	self.favoriteBadge.hidden = !file.isFavorite;
}

- (void)updateInfoOverlayForFile:(SCIGalleryFile *)file {
	SCIGallerySource source = (SCIGallerySource)file.source;
	NSString *sourceText = source == SCIGallerySourceOther ? nil : [SCIGalleryFile shortLabelForSource:source];
	NSString *username = file.sourceUsername.length ? [@"@" stringByAppendingString:file.sourceUsername] : nil;

	if (!sourceText.length && !username.length) {
		self.infoOverlay.hidden = YES;
		return;
	}

	if (sourceText.length && username.length) {
		self.infoLabel.text = [NSString stringWithFormat:@"%@ · %@", sourceText, username];
	} else {
		self.infoLabel.text = sourceText ?: username;
	}

	self.sourceIcon.image = [UIImage systemImageNamed:[self systemSymbolForSource:source]];
	self.infoOverlay.hidden = NO;
}

#pragma mark - Selection

- (UIImage *)selectionBadgeImageSelected:(BOOL)selected {
	return [UIImage systemImageNamed:(selected ? @"checkmark.circle.fill" : @"circle")];
}

- (void)setSelectionMode:(BOOL)selectionMode selected:(BOOL)selected animated:(BOOL)animated {
	self.selectionBadge.image = selectionMode ? [self selectionBadgeImageSelected:selected] : nil;
	self.selectionBadge.hidden = !selectionMode && !animated;
	self.favoriteTrailingConstraint.constant = selectionMode ? -30.0 : -kSCIGalleryGridBadgeInset;

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

#pragma mark - Source

- (NSString *)systemSymbolForSource:(SCIGallerySource)source {
	switch (source) {
		case SCIGallerySourceFeed:		return @"rectangle.stack";
		case SCIGallerySourceStories:	return @"circle.dashed";
		case SCIGallerySourceReels:		return @"film";
		case SCIGallerySourceProfile:	return @"person.crop.circle";
		case SCIGallerySourceDMs:		return @"bubble.left.and.bubble.right";
		case SCIGallerySourceThumbnail:	return @"photo.on.rectangle.angled";
		case SCIGallerySourceNotes:		return @"note.text";
		case SCIGallerySourceComments:	return @"text.bubble";
		case SCIGallerySourceInstants:	return @"square.dashed";
		case SCIGallerySourceOther:
		default:						return @"photo";
	}
}

@end