#import "SCIGalleryListCollectionCell.h"
#import "SCIGalleryFile.h"
#import "SCIAssetUtils.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"

// Fixed row height. With UICollectionViewCompositionalLayout's list section
// the cell self-sizes via auto-layout; we pin contentView height so the row
// has a stable size even though no flow-layout sizeForItemAtIndexPath fires.
static CGFloat const kSCIGalleryListRowHeight = 88.0;
static CGFloat const kSCIGalleryThumbSize = 56.0;
static CGFloat const kSCIGalleryThumbLeadingNormal = 8.0;
static CGFloat const kSCIGalleryThumbLeadingSelection = 40.0;

@interface SCIGalleryListCollectionCell ()

@property (nonatomic, strong) SCIGalleryFile *file;
@property (nonatomic, copy) NSString *reuseToken;

@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIImageView *rowTypeIcon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *technicalLabel;
@property (nonatomic, strong) UIView *pillBackground;
@property (nonatomic, strong) UILabel *pillLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *favoriteIcon;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) UIImageView *selectionIndicator;
@property (nonatomic, strong) NSLayoutConstraint *thumbnailLeadingConstraint;

@end

@implementation SCIGalleryListCollectionCell

#pragma mark - Init

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	self.clipsToBounds = YES;
	self.contentView.backgroundColor = UIColor.clearColor;

	[self setupViews];
	[self setupConstraints];

	return self;
}

#pragma mark - Setup

- (UIImageView *)imageViewWithTint:(UIColor *)tint {
	UIImageView *view = UIImageView.new;
	view.translatesAutoresizingMaskIntoConstraints = NO;
	view.contentMode = UIViewContentModeScaleAspectFit;
	view.tintColor = tint;
	return view;
}

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
	UILabel *label = UILabel.new;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.font = font;
	label.textColor = color;
	label.numberOfLines = 1;
	label.lineBreakMode = NSLineBreakByTruncatingTail;
	return label;
}

- (void)setupViews {
	self.thumbnailView = UIImageView.new;
	self.thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
	self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
	self.thumbnailView.clipsToBounds = YES;
	self.thumbnailView.layer.cornerRadius = 6.0;
	self.thumbnailView.backgroundColor = UIColor.secondarySystemBackgroundColor;
	[self.contentView addSubview:self.thumbnailView];

	self.rowTypeIcon = [self imageViewWithTint:UIColor.secondaryLabelColor];
	[self.contentView addSubview:self.rowTypeIcon];

	self.titleLabel = [self labelWithFont:[UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold] color:UIColor.labelColor];
	[self.contentView addSubview:self.titleLabel];

	self.technicalLabel = [self labelWithFont:[UIFont systemFontOfSize:12.0] color:UIColor.secondaryLabelColor];
	[self.contentView addSubview:self.technicalLabel];

	self.pillBackground = UIView.new;
	self.pillBackground.translatesAutoresizingMaskIntoConstraints = NO;
	self.pillBackground.backgroundColor = UIColor.tertiarySystemBackgroundColor;
	self.pillBackground.layer.cornerRadius = 5.0;
	self.pillBackground.clipsToBounds = YES;
	[self.contentView addSubview:self.pillBackground];

	self.pillLabel = [self labelWithFont:[UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold] color:UIColor.secondaryLabelColor];
	[self.pillBackground addSubview:self.pillLabel];

	self.dateLabel = [self labelWithFont:[UIFont systemFontOfSize:11.0] color:UIColor.tertiaryLabelColor];
	[self.contentView addSubview:self.dateLabel];

	self.favoriteIcon = [[UIImageView alloc] initWithImage:[SCIAssetUtils instagramIconNamed:@"heart_filled" pointSize:14.0]];
	self.favoriteIcon.translatesAutoresizingMaskIntoConstraints = NO;
	self.favoriteIcon.contentMode = UIViewContentModeScaleAspectFit;
	self.favoriteIcon.tintColor = [SCIUtils SCIColor_InstagramFavorite];
	self.favoriteIcon.hidden = YES;
	[self.contentView addSubview:self.favoriteIcon];

	self.selectionIndicator = [self imageViewWithTint:UIColor.secondaryLabelColor];
	self.selectionIndicator.hidden = YES;
	[self.contentView addSubview:self.selectionIndicator];

	self.moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.moreButton setImage:[SCIAssetUtils instagramIconNamed:@"more" pointSize:22.0] forState:UIControlStateNormal];
	self.moreButton.tintColor = UIColor.secondaryLabelColor;
	self.moreButton.accessibilityLabel = SCILocalized(@"More");
	self.moreButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
	self.moreButton.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
	[self.contentView addSubview:self.moreButton];
}

- (void)setupConstraints {
	UILayoutGuide *margin = self.contentView.layoutMarginsGuide;

	self.thumbnailLeadingConstraint = [self.thumbnailView.leadingAnchor constraintEqualToAnchor:margin.leadingAnchor constant:kSCIGalleryThumbLeadingNormal];

	NSLayoutConstraint *height = [self.contentView.heightAnchor constraintEqualToConstant:kSCIGalleryListRowHeight];
	height.priority = UILayoutPriorityRequired - 1;

	[NSLayoutConstraint activateConstraints:@[
		height,

		[self.selectionIndicator.leadingAnchor constraintEqualToAnchor:margin.leadingAnchor constant:8.0],
		[self.selectionIndicator.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[self.selectionIndicator.widthAnchor constraintEqualToConstant:20.0],
		[self.selectionIndicator.heightAnchor constraintEqualToConstant:20.0],

		self.thumbnailLeadingConstraint,
		[self.thumbnailView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[self.thumbnailView.widthAnchor constraintEqualToConstant:kSCIGalleryThumbSize],
		[self.thumbnailView.heightAnchor constraintEqualToConstant:kSCIGalleryThumbSize],

		[self.moreButton.trailingAnchor constraintEqualToAnchor:margin.trailingAnchor constant:-2.0],
		[self.moreButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[self.moreButton.widthAnchor constraintEqualToConstant:40.0],
		[self.moreButton.heightAnchor constraintEqualToConstant:40.0],

		[self.titleLabel.leadingAnchor constraintEqualToAnchor:self.thumbnailView.trailingAnchor constant:12.0],
		[self.titleLabel.topAnchor constraintEqualToAnchor:self.thumbnailView.topAnchor constant:-1.0],
		[self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.favoriteIcon.leadingAnchor constant:-4.0],

		[self.rowTypeIcon.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
		[self.rowTypeIcon.centerYAnchor constraintEqualToAnchor:self.technicalLabel.centerYAnchor],
		[self.rowTypeIcon.widthAnchor constraintEqualToConstant:14.0],
		[self.rowTypeIcon.heightAnchor constraintEqualToConstant:14.0],

		[self.technicalLabel.leadingAnchor constraintEqualToAnchor:self.rowTypeIcon.trailingAnchor constant:4.0],
		[self.technicalLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:3.0],
		[self.technicalLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.moreButton.leadingAnchor constant:-8.0],

		[self.pillBackground.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
		[self.pillBackground.topAnchor constraintEqualToAnchor:self.technicalLabel.bottomAnchor constant:4.0],

		[self.pillLabel.leadingAnchor constraintEqualToAnchor:self.pillBackground.leadingAnchor constant:8.0],
		[self.pillLabel.trailingAnchor constraintEqualToAnchor:self.pillBackground.trailingAnchor constant:-8.0],
		[self.pillLabel.topAnchor constraintEqualToAnchor:self.pillBackground.topAnchor constant:3.0],
		[self.pillLabel.bottomAnchor constraintEqualToAnchor:self.pillBackground.bottomAnchor constant:-3.0],

		[self.dateLabel.leadingAnchor constraintEqualToAnchor:self.pillBackground.trailingAnchor constant:8.0],
		[self.dateLabel.centerYAnchor constraintEqualToAnchor:self.pillBackground.centerYAnchor],
		[self.dateLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.moreButton.leadingAnchor constant:-8.0],

		[self.favoriteIcon.trailingAnchor constraintEqualToAnchor:self.moreButton.leadingAnchor constant:-6.0],
		[self.favoriteIcon.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
		[self.favoriteIcon.widthAnchor constraintEqualToConstant:14.0],
		[self.favoriteIcon.heightAnchor constraintEqualToConstant:14.0],
	]];
}

#pragma mark - Reuse

- (void)prepareForReuse {
	[super prepareForReuse];

	self.file = nil;
	self.reuseToken = nil;
	self.onLeftSwipe = nil;

	self.thumbnailView.image = nil;
	self.rowTypeIcon.image = nil;
	self.titleLabel.text = nil;
	self.technicalLabel.text = nil;
	self.pillLabel.text = nil;
	self.dateLabel.text = nil;

	self.favoriteIcon.hidden = YES;

	self.moreButton.menu = nil;
	self.moreButton.showsMenuAsPrimaryAction = NO;
	self.moreButton.hidden = NO;
	self.moreButton.alpha = 1.0;

	self.selectionIndicator.hidden = YES;
	self.selectionIndicator.alpha = 0.0;
	self.selectionIndicator.image = nil;

	self.thumbnailLeadingConstraint.constant = kSCIGalleryThumbLeadingNormal;
}

#pragma mark - Configure

- (void)configureWithGalleryFile:(SCIGalleryFile *)file
				   selectionMode:(BOOL)selectionMode
						selected:(BOOL)selected {
	self.file = file;
	self.reuseToken = file.identifier ?: file.relativePath ?: file.thumbnailPath ?: NSUUID.UUID.UUIDString;

	self.titleLabel.text = file.listPrimaryTitle;
	self.technicalLabel.text = file.listTechnicalLine;
	self.pillLabel.text = file.shortSourceLabel;
	self.dateLabel.text = file.listDownloadDateString;
	self.rowTypeIcon.image = [self iconForMediaType:file.mediaType];
	self.favoriteIcon.hidden = !file.isFavorite;

	[self updateThumbnailForFile:file token:self.reuseToken];
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
	[SCIGalleryFile generateThumbnailForFile:file completion:^(BOOL ok) {
		if (!ok) return;

		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self || ![self.reuseToken isEqualToString:token]) return;

			UIImage *image = [SCIGalleryFile loadThumbnailForFile:file];
			if (image) self.thumbnailView.image = image;
		});
	}];
}

- (UIImage *)iconForMediaType:(SCIGalleryMediaType)type {
	switch (type) {
		case SCIGalleryMediaTypeVideo:
			return [SCIAssetUtils instagramIconNamed:@"video_filled" pointSize:12.0];

		case SCIGalleryMediaTypeAudio:
			return [UIImage systemImageNamed:@"waveform"
						   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightSemibold]];

		case SCIGalleryMediaTypeGIF:
			return [UIImage systemImageNamed:@"sparkles"
						   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightSemibold]];

		case SCIGalleryMediaTypeImage:
		default:
			return [SCIAssetUtils instagramIconNamed:@"photo_filled" pointSize:12.0];
	}
}

#pragma mark - Selection

- (UIImage *)selectionIndicatorImageSelected:(BOOL)selected {
	return [SCIAssetUtils instagramIconNamed:(selected ? @"circle_check_filled" : @"circle") pointSize:20.0];
}

- (void)setSelectionMode:(BOOL)selectionMode selected:(BOOL)selected animated:(BOOL)animated {
	self.selectionIndicator.image = selectionMode ? [self selectionIndicatorImageSelected:selected] : nil;
	self.selectionIndicator.hidden = !selectionMode && !animated;
	self.moreButton.hidden = selectionMode && !animated;
	self.thumbnailLeadingConstraint.constant = selectionMode ? kSCIGalleryThumbLeadingSelection : kSCIGalleryThumbLeadingNormal;

	void (^changes)(void) = ^{
		self.selectionIndicator.alpha = selectionMode ? 1.0 : 0.0;
		self.moreButton.alpha = selectionMode ? 0.0 : 1.0;
		[self.contentView layoutIfNeeded];
	};

	void (^completion)(BOOL) = ^(BOOL finished) {
		(void)finished;
		self.selectionIndicator.hidden = !selectionMode;
		self.moreButton.hidden = selectionMode;
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

#pragma mark - Menu

- (void)setMoreActionsMenu:(UIMenu *)menu {
	self.moreButton.menu = menu;
	self.moreButton.showsMenuAsPrimaryAction = menu != nil;
}

@end