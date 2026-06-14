#import "SCIGalleryFolderCell.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"

@interface SCIFolderThumbCollage : UIView
@property (nonatomic, strong) NSMutableArray<UIImageView *> *tiles;
@property (nonatomic, strong) UIImageView *placeholder;
@property (nonatomic, strong) UIView *separatorH;
@property (nonatomic, strong) UIView *separatorV1;
@property (nonatomic, assign) NSInteger filledCount;
@end

@implementation SCIFolderThumbCollage

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.clipsToBounds = YES;
		self.layer.cornerCurve = kCACornerCurveContinuous;
		self.backgroundColor = [UIColor.systemGray5Color colorWithAlphaComponent:0.6];

		_tiles = [NSMutableArray array];
		for (NSInteger i = 0; i < 4; i++) {
			UIImageView *iv = [UIImageView new];
			iv.contentMode = UIViewContentModeScaleAspectFill;
			iv.clipsToBounds = YES;
			iv.backgroundColor = [UIColor.systemGray5Color colorWithAlphaComponent:0.4];
			[self addSubview:iv];
			[_tiles addObject:iv];
		}

		UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
		_placeholder = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"folder.fill" withConfiguration:cfg]];
		_placeholder.translatesAutoresizingMaskIntoConstraints = NO;
		_placeholder.tintColor = [UIColor tertiaryLabelColor];
		_placeholder.contentMode = UIViewContentModeCenter;
		[self addSubview:_placeholder];
		[NSLayoutConstraint activateConstraints:@[
			[_placeholder.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
			[_placeholder.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
		]];

		_separatorH = [UIView new];
		_separatorV1 = [UIView new];
		for (UIView *sep in @[_separatorH, _separatorV1]) {
			sep.backgroundColor = [SCIUIKit26BaseSurfaceColor() colorWithAlphaComponent:0.9];
			[self addSubview:sep];
		}
	}
	return self;
}

- (void)setPlaceholderSymbol:(NSString *)symbolName {
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
	_placeholder.image = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
}

- (void)setThumbnailPaths:(NSArray<NSString *> *)paths {
	NSInteger filled = 0;

	for (NSInteger i = 0; i < 4; i++) {
		UIImageView *tile = self.tiles[i];
		UIImage *img = nil;

		if (i < (NSInteger)paths.count) {
			NSString *p = paths[i];
			if (p.length) img = [UIImage imageWithContentsOfFile:p];
		}

		if (img) {
			tile.image = img;
			tile.hidden = NO;
			filled++;
		} else {
			tile.image = nil;
			tile.hidden = YES;
		}
	}

	self.filledCount = filled;
	self.placeholder.hidden = filled > 0;
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGFloat w = self.bounds.size.width;
	CGFloat h = self.bounds.size.height;
	CGFloat g = 1.0;

	self.separatorH.hidden = YES;
	self.separatorV1.hidden = YES;

	if (self.filledCount == 0) return;

	if (self.filledCount == 1) {
		self.tiles[0].frame = CGRectMake(0, 0, w, h);
		return;
	}

	if (self.filledCount == 2) {
		CGFloat halfW = floor((w - g) / 2.0);
		self.tiles[0].frame = CGRectMake(0, 0, halfW, h);
		self.tiles[1].frame = CGRectMake(halfW + g, 0, w - halfW - g, h);
		self.separatorV1.frame = CGRectMake(halfW, 0, g, h);
		self.separatorV1.hidden = NO;
		return;
	}

	if (self.filledCount == 3) {
		CGFloat halfW = floor((w - g) / 2.0);
		CGFloat halfH = floor((h - g) / 2.0);
		self.tiles[0].frame = CGRectMake(0, 0, halfW, h);
		self.tiles[1].frame = CGRectMake(halfW + g, 0, w - halfW - g, halfH);
		self.tiles[2].frame = CGRectMake(halfW + g, halfH + g, w - halfW - g, h - halfH - g);
		self.separatorV1.frame = CGRectMake(halfW, 0, g, h);
		self.separatorH.frame = CGRectMake(halfW + g, halfH, w - halfW - g, g);
		self.separatorV1.hidden = NO;
		self.separatorH.hidden = NO;
		return;
	}

	CGFloat halfW = floor((w - g) / 2.0);
	CGFloat halfH = floor((h - g) / 2.0);
	self.tiles[0].frame = CGRectMake(0, 0, halfW, halfH);
	self.tiles[1].frame = CGRectMake(halfW + g, 0, w - halfW - g, halfH);
	self.tiles[2].frame = CGRectMake(0, halfH + g, halfW, h - halfH - g);
	self.tiles[3].frame = CGRectMake(halfW + g, halfH + g, w - halfW - g, h - halfH - g);
	self.separatorV1.frame = CGRectMake(halfW, 0, g, h);
	self.separatorH.frame = CGRectMake(0, halfH, w, g);
	self.separatorV1.hidden = NO;
	self.separatorH.hidden = NO;
}

@end

#pragma mark - SCIGalleryFolderCell

@interface SCIGalleryFolderCell ()

@property (nonatomic, assign) SCIGalleryFolderCellLayout currentLayout;
@property (nonatomic, strong) UIView *listSeparator;

// List-mode views
@property (nonatomic, strong) UIView *listContainer;
@property (nonatomic, strong) SCIFolderThumbCollage *listCollage;
@property (nonatomic, strong) UILabel *listTitle;
@property (nonatomic, strong) UILabel *listSubtitle;
@property (nonatomic, strong) UIImageView *listChevron;

// Grid-mode views
@property (nonatomic, strong) UIView *gridContainer;
@property (nonatomic, strong) SCIFolderThumbCollage *gridCollage;
@property (nonatomic, strong) UIView *gridOverlay;
@property (nonatomic, strong) UILabel *gridTitle;
@property (nonatomic, strong) UILabel *gridSubtitle;
@property (nonatomic, strong) CAGradientLayer *gridGradient;

@end

@implementation SCIGalleryFolderCell

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.contentView.clipsToBounds = YES;
		[self buildListViews];
		[self buildGridViews];
		_currentLayout = SCIGalleryFolderCellLayoutList;
		_gridContainer.hidden = YES;
	}
	return self;
}

- (void)buildListViews {
	_listContainer = [UIView new];
	_listContainer.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_listContainer];

	_listCollage = [SCIFolderThumbCollage new];
	_listCollage.translatesAutoresizingMaskIntoConstraints = NO;
	_listCollage.layer.cornerRadius = 10;
	[_listContainer addSubview:_listCollage];

	_listTitle = [UILabel new];
	_listTitle.translatesAutoresizingMaskIntoConstraints = NO;
	_listTitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	_listTitle.textColor = [UIColor labelColor];
	_listTitle.numberOfLines = 1;
	_listTitle.lineBreakMode = NSLineBreakByTruncatingMiddle;

	_listSubtitle = [UILabel new];
	_listSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
	_listSubtitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
	_listSubtitle.textColor = [UIColor secondaryLabelColor];

	UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_listTitle, _listSubtitle]];
	textStack.translatesAutoresizingMaskIntoConstraints = NO;
	textStack.axis = UILayoutConstraintAxisVertical;
	textStack.spacing = 2;
	[_listContainer addSubview:textStack];

	UIImageSymbolConfiguration *chevCfg = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold];
	_listChevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:chevCfg]];
	_listChevron.translatesAutoresizingMaskIntoConstraints = NO;
	_listChevron.tintColor = [UIColor tertiaryLabelColor];
	[_listContainer addSubview:_listChevron];

	_listSeparator = [UIView new];
	_listSeparator.translatesAutoresizingMaskIntoConstraints = NO;
	_listSeparator.backgroundColor = [UIColor separatorColor];
	[_listContainer addSubview:_listSeparator];

	[NSLayoutConstraint activateConstraints:@[
		[_listContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
		[_listContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
		[_listContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
		[_listContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

		[_listCollage.leadingAnchor constraintEqualToAnchor:_listContainer.leadingAnchor constant:16],
		[_listCollage.centerYAnchor constraintEqualToAnchor:_listContainer.centerYAnchor],
		[_listCollage.widthAnchor constraintEqualToConstant:56],
		[_listCollage.heightAnchor constraintEqualToConstant:56],

		[textStack.leadingAnchor constraintEqualToAnchor:_listCollage.trailingAnchor constant:12],
		[textStack.trailingAnchor constraintEqualToAnchor:_listChevron.leadingAnchor constant:-8],
		[textStack.centerYAnchor constraintEqualToAnchor:_listContainer.centerYAnchor],

		[_listChevron.trailingAnchor constraintEqualToAnchor:_listContainer.trailingAnchor constant:-14],
		[_listChevron.centerYAnchor constraintEqualToAnchor:_listContainer.centerYAnchor],
		[_listChevron.widthAnchor constraintEqualToConstant:12],
		[_listChevron.heightAnchor constraintEqualToConstant:14],

		[_listSeparator.leadingAnchor constraintEqualToAnchor:_listCollage.trailingAnchor constant:12],
		[_listSeparator.trailingAnchor constraintEqualToAnchor:_listContainer.trailingAnchor],
		[_listSeparator.bottomAnchor constraintEqualToAnchor:_listContainer.bottomAnchor],
		[_listSeparator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
	]];
}

- (void)buildGridViews {
	_gridContainer = [UIView new];
	_gridContainer.translatesAutoresizingMaskIntoConstraints = NO;
	_gridContainer.clipsToBounds = YES;
	[self.contentView addSubview:_gridContainer];

	_gridCollage = [SCIFolderThumbCollage new];
	_gridCollage.translatesAutoresizingMaskIntoConstraints = NO;
	[_gridContainer addSubview:_gridCollage];

	_gridOverlay = [UIView new];
	_gridOverlay.translatesAutoresizingMaskIntoConstraints = NO;
	_gridOverlay.userInteractionEnabled = NO;
	[_gridContainer addSubview:_gridOverlay];

	_gridGradient = [CAGradientLayer layer];
	_gridGradient.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor,
							 (id)[UIColor colorWithWhite:0 alpha:0.75].CGColor];
	_gridGradient.startPoint = CGPointMake(0.5, 0.4);
	_gridGradient.endPoint = CGPointMake(0.5, 1.0);
	[_gridOverlay.layer addSublayer:_gridGradient];

	_gridTitle = [UILabel new];
	_gridTitle.translatesAutoresizingMaskIntoConstraints = NO;
	_gridTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
	_gridTitle.textColor = [UIColor whiteColor];
	_gridTitle.numberOfLines = 1;
	_gridTitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
	_gridTitle.shadowColor = [UIColor colorWithWhite:0 alpha:0.4];
	_gridTitle.shadowOffset = CGSizeMake(0, 0.5);
	[_gridOverlay addSubview:_gridTitle];

	_gridSubtitle = [UILabel new];
	_gridSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
	_gridSubtitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
	_gridSubtitle.textColor = [UIColor colorWithWhite:1 alpha:0.85];
	[_gridOverlay addSubview:_gridSubtitle];

	UIImageSymbolConfiguration *badgeCfg = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold];
	UIImageView *badgeIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"folder.fill" withConfiguration:badgeCfg]];
	badgeIcon.translatesAutoresizingMaskIntoConstraints = NO;
	badgeIcon.tintColor = [UIColor whiteColor];

	UIView *badgeBG = [UIView new];
	badgeBG.translatesAutoresizingMaskIntoConstraints = NO;
	badgeBG.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
	badgeBG.layer.cornerRadius = 11;
	badgeBG.layer.cornerCurve = kCACornerCurveContinuous;
	[badgeBG addSubview:badgeIcon];
	[_gridOverlay addSubview:badgeBG];

	[NSLayoutConstraint activateConstraints:@[
		[_gridContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
		[_gridContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
		[_gridContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
		[_gridContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

		[_gridCollage.topAnchor constraintEqualToAnchor:_gridContainer.topAnchor],
		[_gridCollage.bottomAnchor constraintEqualToAnchor:_gridContainer.bottomAnchor],
		[_gridCollage.leadingAnchor constraintEqualToAnchor:_gridContainer.leadingAnchor],
		[_gridCollage.trailingAnchor constraintEqualToAnchor:_gridContainer.trailingAnchor],

		[_gridOverlay.topAnchor constraintEqualToAnchor:_gridContainer.topAnchor],
		[_gridOverlay.bottomAnchor constraintEqualToAnchor:_gridContainer.bottomAnchor],
		[_gridOverlay.leadingAnchor constraintEqualToAnchor:_gridContainer.leadingAnchor],
		[_gridOverlay.trailingAnchor constraintEqualToAnchor:_gridContainer.trailingAnchor],

		[_gridTitle.leadingAnchor constraintEqualToAnchor:_gridOverlay.leadingAnchor constant:8],
		[_gridTitle.trailingAnchor constraintEqualToAnchor:_gridOverlay.trailingAnchor constant:-8],

		[_gridSubtitle.leadingAnchor constraintEqualToAnchor:_gridTitle.leadingAnchor],
		[_gridSubtitle.trailingAnchor constraintEqualToAnchor:_gridTitle.trailingAnchor],
		[_gridSubtitle.bottomAnchor constraintEqualToAnchor:_gridOverlay.bottomAnchor constant:-6],

		[_gridTitle.bottomAnchor constraintEqualToAnchor:_gridSubtitle.topAnchor constant:-1],

		[badgeBG.topAnchor constraintEqualToAnchor:_gridOverlay.topAnchor constant:6],
		[badgeBG.leadingAnchor constraintEqualToAnchor:_gridOverlay.leadingAnchor constant:6],
		[badgeBG.widthAnchor constraintEqualToConstant:22],
		[badgeBG.heightAnchor constraintEqualToConstant:22],
		[badgeIcon.centerXAnchor constraintEqualToAnchor:badgeBG.centerXAnchor],
		[badgeIcon.centerYAnchor constraintEqualToAnchor:badgeBG.centerYAnchor],
	]];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	self.gridGradient.frame = self.gridOverlay.bounds;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.listTitle.text = nil;
	self.listSubtitle.text = nil;
	self.gridTitle.text = nil;
	self.gridSubtitle.text = nil;
	[self.listCollage setThumbnailPaths:@[]];
	[self.gridCollage setThumbnailPaths:@[]];
}

- (void)configureWithFolderName:(NSString *)name
					   subtitle:(NSString *)subtitle
				 thumbnailPaths:(NSArray<NSString *> *)thumbnailPaths
					 layoutMode:(SCIGalleryFolderCellLayout)layoutMode
				   isUserFolder:(BOOL)isUserFolder {

	BOOL isGrid = (layoutMode == SCIGalleryFolderCellLayoutGrid);

	self.currentLayout = layoutMode;
	self.listContainer.hidden = isGrid;
	self.gridContainer.hidden = !isGrid;

	NSString *placeholderSymbol = isUserFolder ? @"person.fill" : @"folder.fill";
	[self.listCollage setPlaceholderSymbol:placeholderSymbol];
	[self.gridCollage setPlaceholderSymbol:placeholderSymbol];

	if (isGrid) {
		[self.gridCollage setThumbnailPaths:thumbnailPaths ?: @[]];
		self.gridTitle.text = name;
		self.gridSubtitle.text = subtitle ?: @"";
	} else {
		[self.listCollage setThumbnailPaths:thumbnailPaths ?: @[]];
		self.listTitle.text = name;
		self.listSubtitle.text = subtitle ?: @"";
	}
}

@end
