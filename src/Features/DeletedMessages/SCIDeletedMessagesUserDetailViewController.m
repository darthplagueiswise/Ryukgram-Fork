#import "SCIDeletedMessagesUserDetailViewController.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../UI/SCIIcon.h"
#import "SCIDeletedMessagesStorage.h"
#import "SCIDeletedMessagesFilter.h"
#import "SCIDeletedMessagesCapture.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Utils.h"
#import "../../SCIURLOpener.h"
#import "../../UI/SCIScrollToTopButton.h"
#import "../../SCIImageCache.h"
#import "../../PhotoAlbum.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Localization/SCILocalization.h"
#import "SCIDeletedMessagesDate.h"
#import "../Theme/SCITheme.h"
#import <AVFoundation/AVFoundation.h>

// Lit tone so received bubbles stay visible on OLED black; sub-0.9 alpha dodges the recolor.
static UIColor *SCIDMReceivedBubbleColor(void) {
	if ([SCITheme shouldRecolor]) return [UIColor colorWithWhite:0.17 alpha:0.88];
	return UIColor.secondarySystemBackgroundColor;
}

#pragma mark - Adaptive message cell

static const CGFloat kSCIDMBubbleMaxWidth		= 260.0;
static const CGFloat kSCIDMMediaSize			= 220.0;
static const CGFloat kSCIDMVoiceWidth			= 245.0;
static const CGFloat kSCIDMVoiceWidthPlaying	= 295.0;
static const CGFloat kSCIDMBubbleCorner			= 18.0;

@interface SCIDMMessageCell : UITableViewCell

@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIView *bubbleContent;
@property (nonatomic, strong) NSLayoutConstraint *bubbleMaxWidth;
@property (nonatomic, strong) NSLayoutConstraint *bubbleLeading;

@property (nonatomic, strong) UIView *senderRow;
@property (nonatomic, strong) UIImageView *senderAvatar;
@property (nonatomic, strong) UILabel *senderLabel;
@property (nonatomic, strong) NSLayoutConstraint *senderRowHeight;
@property (nonatomic, copy) NSString *senderAvatarURL;

@property (nonatomic, copy) void (^onBubbleTap)(void);
@property (nonatomic, copy) void (^onVoicePlayTap)(void);
@property (nonatomic, copy) void (^onVoiceSeekTo)(double seconds);
@property (nonatomic, copy) void (^onCellTap)(void);

@property (nonatomic, copy) NSString *messageId;
@property (nonatomic) BOOL isVoicePlaying;
@property (nonatomic) BOOL voiceDragging;
@property (nonatomic) double voiceDuration;
@property (nonatomic, weak) UISlider *voiceSlider;
@property (nonatomic, weak) UILabel *voiceDurationLabel;
@property (nonatomic, weak) UIButton *voicePlayButton;
@property (nonatomic, strong) NSLayoutConstraint *voiceDurationLabelWidth;
@property (nonatomic) CGFloat voiceDurationIdleWidth;
@property (nonatomic) CGFloat voiceDurationPlayingWidth;

@property (nonatomic, strong) UIImageView *checkbox;
- (void)applySelectionMode:(BOOL)on selected:(BOOL)selected selectable:(BOOL)selectable;
- (void)applyMessage:(SCIDeletedMessage *)m ownerPK:(NSString *)ownerPK playing:(BOOL)playing;
- (void)applySenderHeaderVisible:(BOOL)visible message:(SCIDeletedMessage *)m;
- (void)setVoiceProgressSeconds:(double)seconds;

+ (NSString *)shareTypeLabelForURL:(NSString *)urlString fallbackKind:(SCIDeletedMessageKind)kind;
+ (BOOL)shareLabelIsNonUserCard:(NSString *)label;

@end

@implementation SCIDMMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
	if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.contentView.layoutMargins = UIEdgeInsetsMake(4, 16, 4, 16);

		_bubble = [UIView new];
		_bubble.translatesAutoresizingMaskIntoConstraints = NO;
		_bubble.layer.cornerRadius = kSCIDMBubbleCorner;
		_bubble.layer.cornerCurve = kCACornerCurveContinuous;
		_bubble.layer.masksToBounds = YES;
		_bubble.userInteractionEnabled = YES;
		[self.contentView addSubview:_bubble];

		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bubbleTapped)];
		[_bubble addGestureRecognizer:tap];

		UITapGestureRecognizer *cellTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(contentTapped)];
		cellTap.cancelsTouchesInView = NO;
		[self.contentView addGestureRecognizer:cellTap];

		_checkbox = [UIImageView new];
		_checkbox.translatesAutoresizingMaskIntoConstraints = NO;
		_checkbox.contentMode = UIViewContentModeCenter;
		_checkbox.tintColor = UIColor.tertiaryLabelColor;
		_checkbox.alpha = 0;
		_checkbox.image = [UIImage systemImageNamed:@"circle"];
		[self.contentView addSubview:_checkbox];

		_metaLabel = [UILabel new];
		_metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
		_metaLabel.font = [UIFont systemFontOfSize:11];
		_metaLabel.textColor = UIColor.tertiaryLabelColor;
		[self.contentView addSubview:_metaLabel];

		// Group-only sender row; collapses to 6pt when hidden (acts as bubble top padding).
		_senderRow = [UIView new];
		_senderRow.translatesAutoresizingMaskIntoConstraints = NO;
		_senderRow.hidden = YES;
		[self.contentView addSubview:_senderRow];

		_senderAvatar = [UIImageView new];
		_senderAvatar.translatesAutoresizingMaskIntoConstraints = NO;
		_senderAvatar.contentMode = UIViewContentModeScaleAspectFill;
		_senderAvatar.layer.cornerRadius = 9;
		_senderAvatar.layer.masksToBounds = YES;
		_senderAvatar.tintColor = UIColor.systemGray3Color;
		[_senderRow addSubview:_senderAvatar];

		_senderLabel = [UILabel new];
		_senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
		_senderLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
		_senderLabel.textColor = UIColor.secondaryLabelColor;
		[_senderRow addSubview:_senderLabel];

		UILayoutGuide *m = self.contentView.layoutMarginsGuide;
		_bubbleMaxWidth = [_bubble.widthAnchor constraintLessThanOrEqualToConstant:kSCIDMBubbleMaxWidth];
		_bubbleLeading = [_bubble.leadingAnchor constraintEqualToAnchor:m.leadingAnchor];
		_senderRowHeight = [_senderRow.heightAnchor constraintEqualToConstant:6];

		// Sub-required so the avatar yields to the 6pt collapse without log spam.
		NSLayoutConstraint *avatarBottom = [_senderAvatar.bottomAnchor constraintEqualToAnchor:_senderRow.bottomAnchor constant:-1];
		NSLayoutConstraint *avatarH = [_senderAvatar.heightAnchor constraintEqualToConstant:18];
		avatarBottom.priority = UILayoutPriorityDefaultHigh;
		avatarH.priority = UILayoutPriorityDefaultHigh;

		[NSLayoutConstraint activateConstraints:@[
			_senderRowHeight,
			[_senderRow.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[_senderRow.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:2],
			[_senderRow.trailingAnchor constraintLessThanOrEqualToAnchor:m.trailingAnchor],

			[_senderAvatar.leadingAnchor constraintEqualToAnchor:_senderRow.leadingAnchor],
			avatarBottom,
			[_senderAvatar.widthAnchor constraintEqualToConstant:18],
			avatarH,

			[_senderLabel.leadingAnchor constraintEqualToAnchor:_senderAvatar.trailingAnchor constant:5],
			[_senderLabel.centerYAnchor constraintEqualToAnchor:_senderAvatar.centerYAnchor],
			[_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_senderRow.trailingAnchor],

			_bubbleLeading,
			[_bubble.topAnchor constraintEqualToAnchor:_senderRow.bottomAnchor],
			[_bubble.trailingAnchor constraintLessThanOrEqualToAnchor:m.trailingAnchor constant:-32],
			_bubbleMaxWidth,

			[_metaLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:6],
			[_metaLabel.topAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:4],
			[_metaLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],

			[_checkbox.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
			[_checkbox.centerYAnchor constraintEqualToAnchor:_bubble.centerYAnchor],
			[_checkbox.widthAnchor constraintEqualToConstant:24],
			[_checkbox.heightAnchor constraintEqualToConstant:24],
		]];
	}
	return self;
}

- (void)applySenderHeaderVisible:(BOOL)visible message:(SCIDeletedMessage *)m {
	self.senderRow.hidden = !visible;
	self.senderRowHeight.constant = visible ? 24 : 6;
	if (!visible) return;

	NSString *who = m.senderUsername.length ? [@"@" stringByAppendingString:m.senderUsername]
										   : (m.senderFullName.length ? m.senderFullName : SCILocalized(@"Unknown user"));
	self.senderLabel.text = who;

	self.senderAvatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
	self.senderAvatar.tintColor = UIColor.systemGray3Color;
	self.senderAvatarURL = m.senderProfilePicURL;
	if (!m.senderProfilePicURL.length) return;

	NSURL *url = [NSURL URLWithString:m.senderProfilePicURL];
	if (!url) return;
	__weak typeof(self) ws = self;
	[SCIImageCache loadImageFromURL:url completion:^(UIImage *img) {
		if (!img || ![ws.senderAvatarURL isEqualToString:m.senderProfilePicURL]) return;
		ws.senderAvatar.image = img;
	}];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self resetBubble];
	self.senderRow.hidden = YES;
	self.senderRowHeight.constant = 6;
	self.senderLabel.text = nil;
	self.senderAvatar.image = nil;
	self.senderAvatarURL = nil;
	self.metaLabel.text = nil;
	self.metaLabel.attributedText = nil;
	self.onBubbleTap = nil;
	self.onVoicePlayTap = nil;
	self.onVoiceSeekTo = nil;
	self.onCellTap = nil;
	self.isVoicePlaying = NO;
	self.voiceDragging = NO;
	self.messageId = nil;
}

- (void)resetBubble {
	[self.bubbleContent removeFromSuperview];
	self.bubbleContent = nil;
	self.bubble.backgroundColor = UIColor.clearColor;
	self.bubbleMaxWidth.constant = kSCIDMBubbleMaxWidth;
	self.voiceDurationLabelWidth = nil;
	self.voiceSlider = nil;
	self.voiceDurationLabel = nil;
	self.voicePlayButton = nil;
}

- (void)bubbleTapped {
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
	if (self.onCellTap) { self.onCellTap(); return; }
	if (self.onBubbleTap) self.onBubbleTap();
}

- (void)contentTapped {
	if (!self.onCellTap) return;
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
	self.onCellTap();
}

#pragma mark - Helpers

- (void)pinView:(UIView *)v toView:(UIView *)target {
	[NSLayoutConstraint activateConstraints:@[
		[v.topAnchor constraintEqualToAnchor:target.topAnchor],
		[v.bottomAnchor constraintEqualToAnchor:target.bottomAnchor],
		[v.leadingAnchor constraintEqualToAnchor:target.leadingAnchor],
		[v.trailingAnchor constraintEqualToAnchor:target.trailingAnchor],
	]];
}

- (UIImageView *)glyphViewWithSymbol:(NSString *)symbol pointSize:(CGFloat)pointSize weight:(UIImageSymbolWeight)weight {
	UIImageView *glyph = [UIImageView new];
	glyph.translatesAutoresizingMaskIntoConstraints = NO;
	glyph.tintColor = UIColor.tertiaryLabelColor;
	glyph.image = [UIImage systemImageNamed:symbol withConfiguration:
		[UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight]];
	return glyph;
}

- (void)addCenteredGlyph:(NSString *)symbol toView:(UIView *)view pointSize:(CGFloat)pointSize {
	UIImageView *glyph = [self glyphViewWithSymbol:symbol pointSize:pointSize weight:UIImageSymbolWeightLight];
	[view addSubview:glyph];
	[NSLayoutConstraint activateConstraints:@[
		[glyph.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
		[glyph.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
	]];
}

- (void)loadImageView:(UIImageView *)iv local:(NSString *)rel url:(NSString *)url ownerPK:(NSString *)ownerPK {
	NSString *path = [SCIDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:ownerPK];
	UIImage *img = path.length ? [UIImage imageWithContentsOfFile:path] : nil;
	if (img) {
		iv.image = img;
		return;
	}
	if (!url.length) return;

	__weak UIImageView *weakIV = iv;
	[SCIImageCache loadImageFromURL:[NSURL URLWithString:url] completion:^(UIImage *image) {
		if (image) weakIV.image = image;
	}];
}

#pragma mark - Apply

- (void)applyMessage:(SCIDeletedMessage *)m ownerPK:(NSString *)ownerPK playing:(BOOL)playing {
	[self resetBubble];
	self.messageId = m.messageId;
	self.isVoicePlaying = playing;

	NSString *kindName = SCIDeletedMessageKindLocalizedName(m.kind);
	NSString *time = [SCIDeletedMessagesDate stringForDate:(m.deletedAt ?: m.capturedAt ?: m.sentAt)];
	NSString *baseMeta = (kindName.length && time.length) ? [NSString stringWithFormat:@"%@ · %@", kindName, time] : (time.length ? time : kindName);

	if (m.editCount > 0) {
		NSMutableAttributedString *out = [NSMutableAttributedString new];
		UIImage *pencil = [UIImage systemImageNamed:@"pencil.line"];
		if (pencil) {
			NSTextAttachment *att = [NSTextAttachment new];
			att.image = [pencil imageWithTintColor:UIColor.secondaryLabelColor renderingMode:UIImageRenderingModeAlwaysOriginal];
			att.bounds = CGRectMake(0, -1.5, 11, 11);
			[out appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
		}
		[out appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" %@", SCILocalized(@"Edited")]
																	 attributes:@{NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
																				  NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]}]];
		if (baseMeta.length) {
			[out appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"  ·  %@", baseMeta]
																		 attributes:@{NSForegroundColorAttributeName: UIColor.tertiaryLabelColor}]];
		}
		self.metaLabel.attributedText = out;
	} else {
		self.metaLabel.text = baseMeta;
	}

	if (m.kind == SCIDeletedMessageKindReactionRemoved) [self installReactionBubble:m];
	else if (m.kind == SCIDeletedMessageKindText && m.text.length) [self installTextBubble:m.text];
	else if (m.kind == SCIDeletedMessageKindVoice) [self installVoiceBubble:m];
	else if (m.kind == SCIDeletedMessageKindPhoto || m.kind == SCIDeletedMessageKindVideo || m.kind == SCIDeletedMessageKindGif) [self installMediaBubble:m ownerPK:ownerPK];
	else if (m.kind == SCIDeletedMessageKindSticker) [self installStickerBubble:m ownerPK:ownerPK];
	else if (m.kind == SCIDeletedMessageKindShare || m.kind == SCIDeletedMessageKindLink || m.kind == SCIDeletedMessageKindAudioShare) [self installShareBubble:m ownerPK:ownerPK];
	else [self installPlaceholderBubble:m];
}

#pragma mark - Variants

- (void)installTextBubble:(NSString *)text {
	self.bubble.backgroundColor = SCIDMReceivedBubbleColor();

	UILabel *l = [UILabel new];
	l.translatesAutoresizingMaskIntoConstraints = NO;
	l.font = [UIFont systemFontOfSize:15.5];
	l.textColor = UIColor.labelColor;
	l.numberOfLines = 0;
	l.text = text;
	[self.bubble addSubview:l];
	self.bubbleContent = l;

	[NSLayoutConstraint activateConstraints:@[
		[l.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:9],
		[l.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-9],
		[l.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:14],
		[l.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-14],
	]];
}

- (void)installMediaBubble:(SCIDeletedMessage *)m ownerPK:(NSString *)ownerPK {
	self.bubbleMaxWidth.constant = kSCIDMMediaSize;

	UIImageView *iv = [UIImageView new];
	iv.translatesAutoresizingMaskIntoConstraints = NO;
	iv.contentMode = UIViewContentModeScaleAspectFill;
	iv.layer.cornerRadius = kSCIDMBubbleCorner;
	iv.layer.masksToBounds = YES;
	iv.backgroundColor = UIColor.secondarySystemBackgroundColor;
	[self.bubble addSubview:iv];
	self.bubbleContent = iv;

	[self pinView:iv toView:self.bubble];
	[NSLayoutConstraint activateConstraints:@[
		[iv.widthAnchor constraintEqualToConstant:kSCIDMMediaSize],
		[iv.heightAnchor constraintEqualToConstant:kSCIDMMediaSize],
	]];

	NSString *rel = m.thumbnailPath ?: m.mediaPath;
	NSString *url = m.thumbnailURL ?: m.mediaURL;
	NSString *note = SCIDeletedMessageMediaStatusNote(m);

	BOOL hasPreview = rel.length > 0;
	BOOL canOpen = hasPreview || (url.length && !note);

	if (hasPreview) {
		[self loadImageView:iv local:rel url:nil ownerPK:ownerPK];
	} else if (note) {
		// No local preview and we know why — state it instead of trying a dead URL.
		[self addMediaStatusGlyph:m toView:iv];
	} else if (url.length) {
		[self loadImageView:iv local:nil url:url ownerPK:ownerPK];
	} else {
		[self addCenteredGlyph:SCIDeletedMessageKindSymbol(m.kind) toView:iv pointSize:48];
	}

	if (m.isEphemeral) [self addEphemeralBadgeToView:iv];

	if (m.kind == SCIDeletedMessageKindVideo && canOpen) {
		UIImageView *play = [self glyphViewWithSymbol:@"play.circle.fill" pointSize:48 weight:UIImageSymbolWeightSemibold];
		play.tintColor = UIColor.whiteColor;
		play.layer.shadowOpacity = 0.4;
		play.layer.shadowOffset = CGSizeMake(0, 1);
		play.layer.shadowRadius = 4;
		[iv addSubview:play];
		[NSLayoutConstraint activateConstraints:@[
			[play.centerXAnchor constraintEqualToAnchor:iv.centerXAnchor],
			[play.centerYAnchor constraintEqualToAnchor:iv.centerYAnchor],
		]];
	}
}

- (void)addMediaStatusGlyph:(SCIDeletedMessage *)m toView:(UIView *)view {
	NSString *symbol = m.isEphemeral ? @"eye.slash" : @"exclamationmark.triangle";
	if (m.mediaStatus == SCIDeletedMessageMediaStatusPending) symbol = @"arrow.down.circle";

	UIImageView *glyph = [self glyphViewWithSymbol:symbol pointSize:34 weight:UIImageSymbolWeightLight];

	UILabel *caption = [UILabel new];
	caption.translatesAutoresizingMaskIntoConstraints = NO;
	caption.text = SCIDeletedMessageMediaStatusNote(m);
	caption.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
	caption.textColor = UIColor.tertiaryLabelColor;
	caption.textAlignment = NSTextAlignmentCenter;
	caption.numberOfLines = 0;

	[view addSubview:glyph];
	[view addSubview:caption];
	[NSLayoutConstraint activateConstraints:@[
		[glyph.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
		[glyph.centerYAnchor constraintEqualToAnchor:view.centerYAnchor constant:-16],
		[caption.topAnchor constraintEqualToAnchor:glyph.bottomAnchor constant:8],
		[caption.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12],
		[caption.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12],
	]];
}

- (void)addEphemeralBadgeToView:(UIView *)view {
	UIImageView *badge = [self glyphViewWithSymbol:@"timer" pointSize:11 weight:UIImageSymbolWeightBold];
	badge.tintColor = UIColor.whiteColor;
	badge.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.45];
	badge.contentMode = UIViewContentModeCenter;
	badge.layer.cornerRadius = 11;
	badge.layer.masksToBounds = YES;
	[view addSubview:badge];
	[NSLayoutConstraint activateConstraints:@[
		[badge.topAnchor constraintEqualToAnchor:view.topAnchor constant:6],
		[badge.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:6],
		[badge.widthAnchor constraintEqualToConstant:22],
		[badge.heightAnchor constraintEqualToConstant:22],
	]];
}

- (void)installStickerBubble:(SCIDeletedMessage *)m ownerPK:(NSString *)ownerPK {
	self.bubbleMaxWidth.constant = 110;

	UIImageView *iv = [UIImageView new];
	iv.translatesAutoresizingMaskIntoConstraints = NO;
	iv.contentMode = UIViewContentModeScaleAspectFit;
	[self.bubble addSubview:iv];
	self.bubbleContent = iv;

	[self pinView:iv toView:self.bubble];
	[NSLayoutConstraint activateConstraints:@[
		[iv.widthAnchor constraintEqualToConstant:104],
		[iv.heightAnchor constraintEqualToConstant:104],
	]];

	NSString *rel = m.thumbnailPath ?: m.mediaPath;
	NSString *url = m.thumbnailURL ?: m.mediaURL;
	[self loadImageView:iv local:rel url:url ownerPK:ownerPK];

	if (!rel.length && !url.length) {
		iv.image = [UIImage systemImageNamed:@"face.smiling.fill" withConfiguration:
			[UIImageSymbolConfiguration configurationWithPointSize:40 weight:UIImageSymbolWeightLight]];
		iv.tintColor = UIColor.systemTealColor;
	}
}

- (void)installVoiceBubble:(SCIDeletedMessage *)m {
	self.bubbleMaxWidth.constant = self.isVoicePlaying ? kSCIDMVoiceWidthPlaying : kSCIDMVoiceWidth;
	UIColor *primary = [SCIUtils SCIColor_Primary] ?: UIColor.systemBlueColor;
	self.bubble.backgroundColor = [primary colorWithAlphaComponent:0.18];
	self.voiceDuration = m.durationSeconds;

	UIView *row = [UIView new];
	row.translatesAutoresizingMaskIntoConstraints = NO;
	[self.bubble addSubview:row];
	self.bubbleContent = row;

	UIButton *playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
	playBtn.translatesAutoresizingMaskIntoConstraints = NO;
	playBtn.tintColor = primary;
	[playBtn setImage:[UIImage systemImageNamed:(self.isVoicePlaying ? @"pause.circle.fill" : @"play.circle.fill")
							  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold]]
			 forState:UIControlStateNormal];
	[playBtn addTarget:self action:@selector(playButtonTapped) forControlEvents:UIControlEventTouchUpInside];
	[row addSubview:playBtn];
	self.voicePlayButton = playBtn;

	UIView *seekerStack = [UIView new];
	seekerStack.translatesAutoresizingMaskIntoConstraints = NO;
	[row addSubview:seekerStack];

	UIStackView *bars = [UIStackView new];
	bars.translatesAutoresizingMaskIntoConstraints = NO;
	bars.axis = UILayoutConstraintAxisHorizontal;
	bars.alignment = UIStackViewAlignmentCenter;
	bars.distribution = UIStackViewDistributionFillEqually;
	bars.spacing = 2;
	bars.userInteractionEnabled = NO;
	[seekerStack addSubview:bars];

	UISlider *slider = [UISlider new];
	slider.translatesAutoresizingMaskIntoConstraints = NO;
	slider.minimumValue = 0;
	slider.maximumValue = MAX(0.1, m.durationSeconds);
	slider.value = 0;
	UIImage *clearTrack = [SCIDMMessageCell clearTrackImage];
	[slider setMinimumTrackImage:clearTrack forState:UIControlStateNormal];
	[slider setMaximumTrackImage:clearTrack forState:UIControlStateNormal];
	[slider setThumbImage:[SCIDMMessageCell sliderThumbImageForColor:primary] forState:UIControlStateNormal];
	[slider addTarget:self action:@selector(sliderTouchBegan:) forControlEvents:UIControlEventTouchDown];
	[slider addTarget:self action:@selector(sliderTouchEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
	[slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
	[seekerStack addSubview:slider];
	self.voiceSlider = slider;

	UILabel *dur = [UILabel new];
	dur.translatesAutoresizingMaskIntoConstraints = NO;
	dur.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
	dur.textColor = primary;
	dur.numberOfLines = 1;
	dur.textAlignment = NSTextAlignmentRight;
	dur.lineBreakMode = NSLineBreakByClipping;

	NSString *idleText = [SCIDMMessageCell formatDuration:m.durationSeconds];
	NSString *playingText = [NSString stringWithFormat:@"%@ / %@", [SCIDMMessageCell formatDuration:0], idleText];
	dur.text = self.isVoicePlaying ? playingText : idleText;

	NSDictionary *attrs = @{NSFontAttributeName: dur.font};
	self.voiceDurationIdleWidth = ceil([idleText sizeWithAttributes:attrs].width) + 2;
	self.voiceDurationPlayingWidth = ceil([playingText sizeWithAttributes:attrs].width) + 2;
	[dur setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[dur setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[row addSubview:dur];
	self.voiceDurationLabel = dur;

	[NSLayoutConstraint activateConstraints:@[
		[row.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:8],
		[row.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-8],
		[row.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:10],
		[row.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-12],
		[row.heightAnchor constraintEqualToConstant:38],

		[playBtn.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
		[playBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
		[playBtn.widthAnchor constraintEqualToConstant:34],
		[playBtn.heightAnchor constraintEqualToConstant:34],

		[seekerStack.leadingAnchor constraintEqualToAnchor:playBtn.trailingAnchor constant:6],
		[seekerStack.trailingAnchor constraintEqualToAnchor:dur.leadingAnchor constant:-6],
		[seekerStack.topAnchor constraintEqualToAnchor:row.topAnchor],
		[seekerStack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],

		[bars.leadingAnchor constraintEqualToAnchor:seekerStack.leadingAnchor],
		[bars.trailingAnchor constraintEqualToAnchor:seekerStack.trailingAnchor],
		[bars.topAnchor constraintEqualToAnchor:seekerStack.topAnchor constant:8],
		[bars.bottomAnchor constraintEqualToAnchor:seekerStack.bottomAnchor constant:-8],

		[slider.leadingAnchor constraintEqualToAnchor:seekerStack.leadingAnchor],
		[slider.trailingAnchor constraintEqualToAnchor:seekerStack.trailingAnchor],
		[slider.centerYAnchor constraintEqualToAnchor:seekerStack.centerYAnchor],

		[dur.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
		[dur.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
	]];

	self.voiceDurationLabelWidth = [dur.widthAnchor constraintEqualToConstant:(self.isVoicePlaying ? self.voiceDurationPlayingWidth : self.voiceDurationIdleWidth)];
	self.voiceDurationLabelWidth.active = YES;

	NSArray<NSNumber *> *samples = m.waveform.count ? [SCIDMMessageCell resampleWaveform:m.waveform to:42] : nil;
	NSInteger count = samples.count ?: 32;
	UIColor *waveColor = [primary colorWithAlphaComponent:0.55];

	for (NSInteger i = 0; i < count; i++) {
		UIView *bar = [UIView new];
		bar.translatesAutoresizingMaskIntoConstraints = NO;
		bar.backgroundColor = waveColor;
		bar.layer.cornerRadius = 1;
		CGFloat amp = samples ? MIN(1.0, MAX(0.08, samples[i].doubleValue)) : (0.25 + 0.7 * ((i % 7) / 7.0));
		[bars addArrangedSubview:bar];
		[bar.heightAnchor constraintEqualToAnchor:bars.heightAnchor multiplier:amp].active = YES;
		[bar.widthAnchor constraintEqualToConstant:2.5].active = YES;
	}
}

+ (UIImage *)clearTrackImage {
	static UIImage *img;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1)];
		img = [[r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
			[UIColor.clearColor setFill];
			UIRectFill(CGRectMake(0, 0, 1, 1));
		}] resizableImageWithCapInsets:UIEdgeInsetsZero];
	});
	return img;
}

+ (UIImage *)sliderThumbImageForColor:(UIColor *)color {
	static NSCache *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [NSCache new]; });

	NSString *key = color.description ?: @"default";
	UIImage *cached = [cache objectForKey:key];
	if (cached) return cached;

	CGSize size = CGSizeMake(12, 12);
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
	UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		[color setFill];
		[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size.width, size.height)] fill];
	}];
	[cache setObject:img forKey:key];
	return img;
}

- (void)playButtonTapped {
	if (self.onVoicePlayTap) self.onVoicePlayTap();
}

#pragma mark - Voice slider

- (void)sliderTouchBegan:(UISlider *)s { self.voiceDragging = YES; }

- (void)sliderTouchEnded:(UISlider *)s {
	self.voiceDragging = NO;
	if (self.onVoiceSeekTo) self.onVoiceSeekTo((double)s.value);
}

- (void)sliderChanged:(UISlider *)s {
	self.voiceDurationLabel.text = [NSString stringWithFormat:@"%@ / %@",
		[SCIDMMessageCell formatDuration:s.value],
		[SCIDMMessageCell formatDuration:self.voiceDuration]];
}

- (void)setVoiceProgressSeconds:(double)seconds {
	if (self.voiceDragging || !self.voiceSlider) return;
	self.voiceSlider.value = (float)MIN(self.voiceDuration, MAX(0, seconds));
	self.voiceDurationLabel.text = [NSString stringWithFormat:@"%@ / %@",
		[SCIDMMessageCell formatDuration:MAX(0, seconds)],
		[SCIDMMessageCell formatDuration:self.voiceDuration]];
}

- (void)applySelectionMode:(BOOL)on selected:(BOOL)selected selectable:(BOOL)selectable {
	self.checkbox.alpha = on ? 1.0 : 0.0;
	self.bubbleLeading.constant = on ? 32.0 : 0.0;
	self.bubble.alpha = (on && !selectable) ? 0.45 : 1.0;

	if (!selectable) {
		self.checkbox.image = [UIImage systemImageNamed:@"minus.circle"];
		self.checkbox.tintColor = UIColor.tertiaryLabelColor;
	} else if (selected) {
		self.checkbox.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
		self.checkbox.tintColor = [SCIUtils SCIColor_Primary] ?: UIColor.systemBlueColor;
	} else {
		self.checkbox.image = [UIImage systemImageNamed:@"circle"];
		self.checkbox.tintColor = UIColor.tertiaryLabelColor;
	}
}

- (void)setVoicePlayingFlag:(BOOL)playing {
	self.isVoicePlaying = playing;
	[self.voicePlayButton setImage:[UIImage systemImageNamed:(playing ? @"pause.circle.fill" : @"play.circle.fill")
										   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold]]
						   forState:UIControlStateNormal];

	self.bubbleMaxWidth.constant = playing ? kSCIDMVoiceWidthPlaying : kSCIDMVoiceWidth;
	self.voiceDurationLabelWidth.constant = playing ? self.voiceDurationPlayingWidth : self.voiceDurationIdleWidth;
	if (!playing) self.voiceDurationLabel.text = [SCIDMMessageCell formatDuration:self.voiceDuration];

	[UIView animateWithDuration:0.18 animations:^{
		[self.contentView layoutIfNeeded];
	}];
}

+ (NSString *)shareTypeLabelForURL:(NSString *)urlString fallbackKind:(SCIDeletedMessageKind)kind {
	if (kind == SCIDeletedMessageKindAudioShare) return SCILocalized(@"Audio");
	if (kind == SCIDeletedMessageKindLink && urlString.length) {
		NSString *host = [NSURL URLWithString:urlString].host.lowercaseString ?: @"";
		if (![host containsString:@"instagram.com"]) return SCILocalized(@"Link");
	}

	NSString *lowerURL = urlString.lowercaseString ?: @"";
	NSString *path = [NSURL URLWithString:urlString].path.lowercaseString ?: @"";

	if ([lowerURL containsString:@"live_location"] || ([lowerURL containsString:@"latitude="] && [lowerURL containsString:@"longitude="])) return SCILocalized(@"Live location");
	if ([path containsString:@"reels_audio_page"] || [path containsString:@"/audio_page"] || [path containsString:@"/audio/"]) return SCILocalized(@"Audio");
	if ([path containsString:@"/reel"]) return SCILocalized(@"Reel");
	if ([path containsString:@"/tv/"]) return SCILocalized(@"IGTV");
	if ([path containsString:@"/stories/"]) return SCILocalized(@"Story");
	if ([path containsString:@"/explore/locations/"]) return SCILocalized(@"Location");
	if ([path containsString:@"/explore/tags/"]) return SCILocalized(@"Hashtag");
	if ([path containsString:@"/p/"]) return SCILocalized(@"Post");
	if (kind == SCIDeletedMessageKindLink) return SCILocalized(@"Link");
	return SCILocalized(@"Post");
}

+ (BOOL)shareLabelIsNonUserCard:(NSString *)label {
	return [label isEqualToString:SCILocalized(@"Audio")]
		|| [label isEqualToString:SCILocalized(@"Location")]
		|| [label isEqualToString:SCILocalized(@"Live location")]
		|| [label isEqualToString:SCILocalized(@"Hashtag")];
}

- (void)installShareBubble:(SCIDeletedMessage *)m ownerPK:(NSString *)ownerPK {
	self.bubble.backgroundColor = SCIDMReceivedBubbleColor();
	self.bubbleMaxWidth.constant = kSCIDMMediaSize;

	UIStackView *col = [UIStackView new];
	col.translatesAutoresizingMaskIntoConstraints = NO;
	col.axis = UILayoutConstraintAxisVertical;
	col.spacing = 0;
	col.alignment = UIStackViewAlignmentFill;
	[self.bubble addSubview:col];
	self.bubbleContent = col;
	[self pinView:col toView:self.bubble];

	UIImageView *thumb = [UIImageView new];
	thumb.translatesAutoresizingMaskIntoConstraints = NO;
	thumb.contentMode = UIViewContentModeScaleAspectFill;
	thumb.layer.masksToBounds = YES;
	thumb.backgroundColor = UIColor.tertiarySystemFillColor;
	[col addArrangedSubview:thumb];
	[thumb.heightAnchor constraintEqualToConstant:kSCIDMMediaSize].active = YES;

	[self loadImageView:thumb local:m.thumbnailPath url:m.thumbnailURL ownerPK:ownerPK];
	if (!m.thumbnailPath.length && !m.thumbnailURL.length) [self addCenteredGlyph:SCIDeletedMessageKindSymbol(m.kind) toView:thumb pointSize:42];

	UIStackView *footer = [UIStackView new];
	footer.axis = UILayoutConstraintAxisVertical;
	footer.spacing = 2;
	footer.layoutMarginsRelativeArrangement = YES;
	footer.layoutMargins = UIEdgeInsetsMake(10, 12, 10, 12);
	[col addArrangedSubview:footer];

	NSString *typeLabel = [SCIDMMessageCell shareTypeLabelForURL:m.mediaURL fallbackKind:m.kind];
	NSString *body = m.text.length ? m.text : (m.previewText.length ? m.previewText : @"");
	NSArray<NSString *> *bodyLines = body.length ? [body componentsSeparatedByString:@"\n"] : @[];

	UILabel *titleL = [UILabel new];
	titleL.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	titleL.textColor = UIColor.labelColor;
	titleL.numberOfLines = 2;
	titleL.lineBreakMode = NSLineBreakByTruncatingTail;
	[footer addArrangedSubview:titleL];

	UILabel *hint = [UILabel new];
	hint.font = [UIFont systemFontOfSize:12];
	hint.textColor = UIColor.secondaryLabelColor;
	hint.numberOfLines = 1;
	hint.lineBreakMode = NSLineBreakByTruncatingTail;
	[footer addArrangedSubview:hint];

	BOOL isNonUserCard = [SCIDMMessageCell shareLabelIsNonUserCard:typeLabel];
	BOOL isLiveLocation = [typeLabel isEqualToString:SCILocalized(@"Live location")];

	if (m.kind == SCIDeletedMessageKindLink || isNonUserCard) {
		NSString *headline = bodyLines.firstObject ?: typeLabel;
		NSString *sub = nil;
		titleL.text = headline;

		if (m.kind == SCIDeletedMessageKindLink) {
			NSString *host = [NSURL URLWithString:m.mediaURL].host;
			sub = host.length ? host : (bodyLines.count > 1 ? bodyLines[1] : nil);
		} else {
			sub = bodyLines.count > 1 ? bodyLines[1] : nil;
		}

		if (!m.mediaURL.length) hint.text = SCILocalized(@"Content unavailable");
		else if (m.kind == SCIDeletedMessageKindAudioShare) hint.text = sub.length ? [NSString stringWithFormat:SCILocalized(@"Tap to play · %@"), sub] : SCILocalized(@"Tap to play");
		else if (isLiveLocation) hint.text = SCILocalized(@"Tap to open in Maps");
		else hint.text = sub.length ? [NSString stringWithFormat:@"%@ · %@", typeLabel, sub] : typeLabel;
	} else {
		NSString *who = bodyLines.firstObject ?: @"";
		titleL.numberOfLines = 1;
		titleL.text = who.length ? [NSString stringWithFormat:@"%@ · @%@", typeLabel, who] : typeLabel;
		hint.text = m.mediaURL.length ? SCILocalized(@"Tap to open in Instagram") : SCILocalized(@"Content unavailable");
	}
}

- (void)installReactionBubble:(SCIDeletedMessage *)m {
	self.bubble.backgroundColor = SCIDMReceivedBubbleColor();

	UIStackView *row = [UIStackView new];
	row.translatesAutoresizingMaskIntoConstraints = NO;
	row.axis = UILayoutConstraintAxisHorizontal;
	row.spacing = 10;
	row.alignment = UIStackViewAlignmentCenter;
	[self.bubble addSubview:row];
	self.bubbleContent = row;

	UILabel *emoji = [UILabel new];
	emoji.font = [UIFont systemFontOfSize:26];
	emoji.text = m.reactionEmoji.length ? m.reactionEmoji : @"♡";
	[emoji setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[row addArrangedSubview:emoji];

	UIStackView *col = [UIStackView new];
	col.axis = UILayoutConstraintAxisVertical;
	col.spacing = 1;
	[row addArrangedSubview:col];

	UILabel *title = [UILabel new];
	title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	title.textColor = UIColor.labelColor;
	title.text = SCILocalized(@"Removed a reaction");
	[col addArrangedSubview:title];

	NSString *ctx = m.text.length ? m.text : SCILocalized(@"a message");
	UILabel *sub = [UILabel new];
	sub.font = [UIFont systemFontOfSize:12.5];
	sub.textColor = UIColor.secondaryLabelColor;
	sub.numberOfLines = 2;
	sub.lineBreakMode = NSLineBreakByTruncatingTail;
	sub.text = m.reactionTargetUsername.length
		? [NSString stringWithFormat:SCILocalized(@"on @%@: %@"), m.reactionTargetUsername, ctx]
		: [NSString stringWithFormat:SCILocalized(@"on: %@"), ctx];
	[col addArrangedSubview:sub];

	[NSLayoutConstraint activateConstraints:@[
		[row.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:9],
		[row.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-9],
		[row.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:13],
		[row.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-13],
	]];
}

- (void)installPlaceholderBubble:(SCIDeletedMessage *)m {
	self.bubble.backgroundColor = SCIDMReceivedBubbleColor();

	UIStackView *row = [UIStackView new];
	row.translatesAutoresizingMaskIntoConstraints = NO;
	row.axis = UILayoutConstraintAxisHorizontal;
	row.spacing = 8;
	row.alignment = UIStackViewAlignmentCenter;
	[self.bubble addSubview:row];
	self.bubbleContent = row;

	UIImageView *icon = [self glyphViewWithSymbol:SCIDeletedMessageKindSymbol(m.kind) pointSize:14 weight:UIImageSymbolWeightSemibold];
	icon.tintColor = UIColor.secondaryLabelColor;
	[row addArrangedSubview:icon];

	UILabel *l = [UILabel new];
	l.font = [UIFont systemFontOfSize:14];
	l.textColor = UIColor.secondaryLabelColor;
	l.text = m.text.length ? m.text : SCIDeletedMessageKindLocalizedName(m.kind);
	[row addArrangedSubview:l];

	[NSLayoutConstraint activateConstraints:@[
		[row.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:8],
		[row.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-8],
		[row.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:12],
		[row.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-12],
	]];
}

#pragma mark - Format helpers

+ (NSString *)formatDuration:(double)seconds {
	if (seconds <= 0) return @"0:00";
	NSInteger s = (NSInteger)round(seconds);
	return [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
}

+ (NSArray<NSNumber *> *)resampleWaveform:(NSArray<NSNumber *> *)src to:(NSInteger)bars {
	if (!src.count || bars <= 0) return @[];
	if ((NSInteger)src.count == bars) return src;

	NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:bars];
	double step = (double)src.count / (double)bars;

	if ((NSInteger)src.count > bars) {
		for (NSInteger i = 0; i < bars; i++) {
			NSInteger lo = (NSInteger)floor(i * step);
			NSInteger hi = MIN((NSInteger)src.count, MAX(lo + 1, (NSInteger)floor((i + 1) * step)));
			double sum = 0;
			for (NSInteger j = lo; j < hi; j++) sum += src[j].doubleValue;
			[out addObject:@(sum / MAX(1, hi - lo))];
		}
	} else {
		for (NSInteger i = 0; i < bars; i++) {
			NSInteger idx = MIN((NSInteger)src.count - 1, (NSInteger)floor(i * step));
			[out addObject:src[idx]];
		}
	}
	return out;
}

@end

#pragma mark - Edit-history modal

@interface SCIDMEditHistoryViewController : UITableViewController
- (instancetype)initWithMessage:(SCIDeletedMessage *)m;
@end

@implementation SCIDMEditHistoryViewController {
	NSArray<NSDictionary *> *_entries;
}

- (instancetype)initWithMessage:(SCIDeletedMessage *)m {
	if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
		self.title = SCILocalized(@"Edit history");

		NSDateFormatter *df = [NSDateFormatter new];
		df.dateStyle = NSDateFormatterMediumStyle;
		df.timeStyle = NSDateFormatterShortStyle;

		NSMutableArray *list = [NSMutableArray array];
		NSString *original = m.originalText.length ? m.originalText : m.text;
		if (original.length) {
			[list addObject:@{@"title": SCILocalized(@"Original"),
							   @"text": original,
							   @"when": m.sentAt ? [df stringFromDate:m.sentAt] : @""}];
		}

		NSUInteger idx = 1;
		for (NSDictionary *e in m.edits) {
			NSString *txt = [e[@"text"] isKindOfClass:NSString.class] ? e[@"text"] : @"";
			NSNumber *at = [e[@"at"] isKindOfClass:NSNumber.class] ? e[@"at"] : nil;
			[list addObject:@{@"title": [NSString stringWithFormat:SCILocalized(@"Edit %lu"), (unsigned long)idx],
							   @"text": txt,
							   @"when": at ? [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:at.doubleValue]] : @""}];
			idx++;
		}
		_entries = list;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];
	self.tableView.backgroundColor = [SCIPopupChrome backgroundColor];
	self.tableView.estimatedRowHeight = 80;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedSectionHeaderHeight = 32;
	[self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)_entries.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	NSDictionary *e = _entries[s];
	NSString *t = e[@"title"];
	NSString *w = e[@"when"];
	return w.length ? [NSString stringWithFormat:@"%@ · %@", t, w] : t;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"row" forIndexPath:ip];
	c.textLabel.numberOfLines = 0;
	c.textLabel.font = [UIFont systemFontOfSize:15.5];
	c.textLabel.text = _entries[ip.section][@"text"];
	c.selectionStyle = UITableViewCellSelectionStyleNone;
	return c;
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)pt {
	NSString *txt = _entries[ip.section][@"text"];
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *_) {
		UIAction *copy = [UIAction actionWithTitle:SCILocalized(@"Copy")
											  image:[UIImage systemImageNamed:@"doc.on.doc"]
										 identifier:nil
											handler:^(__kindof UIAction *_) {
			UIPasteboard.generalPasteboard.string = txt;
			SCINotifySuccess(SCI_NOTIF_COPY_URL, SCILocalized(@"Copied"), nil);
		}];
		return [UIMenu menuWithTitle:@"" children:@[copy]];
	}];
}

@end

#pragma mark - VC

@interface SCIDeletedMessagesUserDetailViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, copy) NSString *senderPk;
@property (nonatomic, copy) NSString *threadId;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, strong) SCIDeletedMessageGroup *group;
@property (nonatomic, strong) NSArray<SCIDeletedMessage *> *visibleMessages;
@property (nonatomic, strong) SCIDeletedMessagesFilter *filter;

@property (nonatomic, strong) UIView *bannerView;
@property (nonatomic, strong) UIImageView *bannerAvatar;
@property (nonatomic, strong) UILabel *bannerNameLabel;
@property (nonatomic, strong) UILabel *bannerSubLabel;
@property (nonatomic, strong) UIButton *bannerOpenButton;
@property (nonatomic, strong) UIBarButtonItem *filterButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchCtl;

@property (nonatomic, strong) AVPlayer *audioPlayer;
@property (nonatomic, strong) id audioTimeObserver;
@property (nonatomic, copy) NSString *playingMessageId;
@property (nonatomic) double audioDuration;
@property (nonatomic) BOOL audioIsPlaying;

@property (nonatomic) BOOL inSelectionMode;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedSids;
@property (nonatomic, strong) UIBarButtonItem *selectionSaveItem;
@property (nonatomic, strong) UIBarButtonItem *selectionShareItem;
@property (nonatomic, strong) UIBarButtonItem *selectionDeleteItem;
@property (nonatomic, strong) SCIScrollToTopButton *scrollToTopButton;
@end

@implementation SCIDeletedMessagesUserDetailViewController

- (instancetype)initWithGroup:(SCIDeletedMessageGroup *)group ownerPK:(NSString *)ownerPK {
	if ((self = [super init])) {
		_group = group;
		_senderPk = group.senderPk.copy;
		_threadId = group.threadId.copy;
		_ownerPK = ownerPK.copy;
		_filter = [SCIDeletedMessagesFilter new];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];
	self.title = self.group.senderUsername.length ? [@"@" stringByAppendingString:self.group.senderUsername] : SCILocalized(@"Deleted messages");

	[self installSearchController];
	[self installTable];
	self.tableView.tableHeaderView = [self buildBannerHeader];

	self.scrollToTopButton = [SCIScrollToTopButton new];
	[self.scrollToTopButton attachToScrollView:self.tableView inView:self.view bottomInset:24];

	UIBarButtonItem *menu = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[self buildMenu]];
	UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] menu:[self buildFilterMenu]];
	self.filterButton = filter;
	[self refreshFilterButton];
	self.navigationItem.rightBarButtonItems = @[menu, filter];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(storeChanged:) name:SCIDeletedMessagesDidChangeNotification object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(retryRecoverableMedia) name:UIApplicationDidBecomeActiveNotification object:nil];
	[self refreshHeader];
	[self reload];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self retryRecoverableMedia];
}

// Re-attempt blob-less records (failed / stuck Pending). Fires on open + foreground.
- (void)retryRecoverableMedia {
	if (!self.isViewLoaded || !self.view.window) return;
	NSString *ownerPK = self.ownerPK;
	if (!ownerPK.length) return;

	for (SCIDeletedMessage *m in self.group.messages) {
		BOOL stuck = m.mediaStatus == SCIDeletedMessageMediaStatusPending ||
					 m.mediaStatus == SCIDeletedMessageMediaStatusFailed;
		if (!stuck) continue;
		if (!m.mediaCandidates.count && !m.mediaURL.length && !m.mediaPk.length) continue;
		if ([self localFileURLForMessage:m]) continue;
		sciDMRetryMediaDownload(m.messageId, ownerPK);
	}
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[self stopVoicePlayback];
}

#pragma mark - Small helpers

- (NSURL *)localFileURLForMessage:(SCIDeletedMessage *)m {
	NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.mediaPath ownerPK:self.ownerPK];
	return (abs.length && [NSFileManager.defaultManager fileExistsAtPath:abs]) ? [NSURL fileURLWithPath:abs] : nil;
}

- (SCIDMMessageCell *)visibleCellForMessageId:(NSString *)mid {
	if (!mid.length) return nil;
	for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
		SCIDMMessageCell *cell = [self.tableView cellForRowAtIndexPath:ip];
		if ([cell isKindOfClass:SCIDMMessageCell.class] && [cell.messageId isEqualToString:mid]) return cell;
	}
	return nil;
}

- (void)selectedFileURLs:(NSMutableArray<NSURL *> *)urls metas:(NSMutableArray<SCIGallerySaveMetadata *> *)metas {
	for (SCIDeletedMessage *m in self.visibleMessages) {
		if (![self.selectedSids containsObject:m.messageId]) continue;
		NSURL *url = [self localFileURLForMessage:m];
		if (!url) continue;
		[urls addObject:url];
		[metas addObject:[self gallerySaveMetadataForMessage:m]];
	}
}

- (void)presentShareSheetWithURLs:(NSArray<NSURL *> *)urls fromView:(UIView *)anchor exitOnComplete:(BOOL)exitOnComplete {
	if (!urls.count) return;
	[SCIPhotoAlbum armWatcherIfEnabled];

	UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
	if (av.popoverPresentationController) {
		UIView *source = anchor ?: self.view;
		av.popoverPresentationController.sourceView = source;
		av.popoverPresentationController.sourceRect = source.bounds;
	}

	if (exitOnComplete) {
		__weak typeof(self) ws = self;
		av.completionWithItemsHandler = ^(UIActivityType _Nullable type, BOOL completed, NSArray *_Nullable items, NSError *_Nullable error) {
			if (completed) [ws exitSelectionMode];
		};
	}
	[self presentViewController:av animated:YES completion:nil];
}

#pragma mark - Main menu

- (UIMenu *)buildMenu {
	__weak typeof(self) ws = self;

	UIAction *select = [UIAction actionWithTitle:SCILocalized(@"Select")
											image:[UIImage systemImageNamed:@"checkmark.circle"]
									   identifier:nil
										  handler:^(__kindof UIAction *_) {
		[ws enterSelectionMode];
	}];
	if (!self.group.messages.count) select.attributes = UIMenuElementAttributesDisabled;

	BOOL isGroup = self.group.isGroup;
	UIAction *clear = [UIAction actionWithTitle:(isGroup ? SCILocalized(@"Clear this chat") : SCILocalized(@"Clear from this user"))
										  image:[UIImage systemImageNamed:@"trash"]
									 identifier:nil
										handler:^(__kindof UIAction *_) {
		UIAlertController *a = [UIAlertController alertControllerWithTitle:(isGroup ? SCILocalized(@"Clear log for this chat?") : SCILocalized(@"Clear log for this user?"))
																  message:(isGroup ? SCILocalized(@"Removes every preserved deleted message from this group chat.") : SCILocalized(@"Removes every preserved deleted message from this sender."))
														   preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
			if (ws.threadId.length) [SCIDeletedMessagesStorage deleteMessagesForThreadId:ws.threadId ownerPK:ws.ownerPK];
			else [SCIDeletedMessagesStorage deleteMessagesForSenderPK:ws.senderPk ownerPK:ws.ownerPK threadlessOnly:YES];
			[ws.navigationController popViewControllerAnimated:YES];
		}]];
		[ws presentViewController:a animated:YES completion:nil];
	}];
	clear.attributes = UIMenuElementAttributesDestructive;

	UIAction *refresh = [UIAction actionWithTitle:SCILocalized(@"Refresh names & photos")
											image:[UIImage systemImageNamed:@"arrow.clockwise"]
									   identifier:nil
										  handler:^(__kindof UIAction *_) {
		if (ws.threadId.length) sciDMRefreshThreadInfo(ws.threadId, ws.ownerPK);
		else if (ws.senderPk.length) {
			[SCIInstagramAPI sendRequestWithMethod:@"GET"
											  path:[NSString stringWithFormat:@"users/%@/info/", ws.senderPk]
											  body:nil
										completion:^(NSDictionary *resp, NSError *error) {
				NSDictionary *user = [resp[@"user"] isKindOfClass:NSDictionary.class] ? resp[@"user"] : nil;
				if (user.count) [SCIDeletedMessagesStorage applySenderInfo:user forSenderPK:ws.senderPk ownerPK:ws.ownerPK overwrite:YES];
			}];
		}
		SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"Refreshing names & photos"), nil);
	}];

	return [UIMenu menuWithTitle:@"" children:@[
		[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[select, refresh]],
		clear
	]];
}

#pragma mark - Bulk selection

- (void)enterSelectionMode {
	self.inSelectionMode = YES;
	if (!self.selectedSids) self.selectedSids = [NSMutableSet set];
	[self.selectedSids removeAllObjects];
	[self installSelectionToolbar];
	[self.tableView reloadData];

	UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(exitSelectionMode)];
	UIBarButtonItem *all = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Select All") style:UIBarButtonItemStylePlain target:self action:@selector(selectAllSelectable)];
	self.navigationItem.rightBarButtonItems = @[done, all];
	[self refreshSelectionActionsEnabled];
}

- (void)exitSelectionMode {
	self.inSelectionMode = NO;
	[self.selectedSids removeAllObjects];
	[self.navigationController setToolbarHidden:YES animated:YES];
	[self.scrollToTopButton setBottomInset:24];
	[self.tableView reloadData];
	[self refreshHeader];

	UIBarButtonItem *menu = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[self buildMenu]];
	self.navigationItem.rightBarButtonItems = self.filterButton ? @[menu, self.filterButton] : @[menu];
}

- (void)selectAllSelectable {
	for (SCIDeletedMessage *m in self.visibleMessages) {
		if (m.messageId.length) [self.selectedSids addObject:m.messageId];
	}
	[self.tableView reloadData];
	[self refreshSelectionCount];
}

- (void)refreshSelectionCount {
	NSUInteger n = self.selectedSids.count;
	self.navigationItem.title = n == 0 ? SCILocalized(@"Select") : [NSString stringWithFormat:SCILocalized(@"%lu selected"), (unsigned long)n];
	[self refreshSelectionActionsEnabled];
}

- (void)installSelectionToolbar {
	UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"] style:UIBarButtonItemStylePlain target:self action:@selector(saveSelectedToGallery)];
	UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"] style:UIBarButtonItemStylePlain target:self action:@selector(shareSelected)];
	UIBarButtonItem *del = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(confirmDeleteSelected)];
	del.tintColor = UIColor.systemRedColor;

	UIBarButtonItem *(^flex)(void) = ^UIBarButtonItem *{
		return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	};

	self.toolbarItems = @[save, flex(), share, flex(), del];
	self.selectionSaveItem = save;
	self.selectionShareItem = share;
	self.selectionDeleteItem = del;

	[self.navigationController setToolbarHidden:NO animated:YES];
	[self.scrollToTopButton setBottomInset:64];
	[self refreshSelectionCount];
}

- (void)refreshSelectionActionsEnabled {
	NSMutableArray<NSURL *> *urls = [NSMutableArray array];
	NSMutableArray<SCIGallerySaveMetadata *> *metas = [NSMutableArray array];
	[self selectedFileURLs:urls metas:metas];

	BOOL anySelected = self.selectedSids.count > 0;
	self.selectionSaveItem.enabled = urls.count > 0;
	self.selectionShareItem.enabled = urls.count > 0;
	self.selectionDeleteItem.enabled = anySelected;
}

#pragma mark - Bulk save/share/delete

- (SCIGallerySaveMetadata *)gallerySaveMetadataForMessage:(SCIDeletedMessage *)m {
	SCIGallerySaveMetadata *md = [SCIGallerySaveMetadata new];
	md.sourceUsername = m.senderUsername.length ? m.senderUsername : self.group.senderUsername;
	md.sourceUserPK = m.senderPk.length ? m.senderPk : self.group.senderPk;
	md.sourceProfileURLString = m.senderProfilePicURL.length ? m.senderProfilePicURL : self.group.senderProfilePicURL;
	md.source = SCIGallerySourceDMs;
	md.skipDedup = YES;
	if (m.durationSeconds > 0) md.durationSeconds = m.durationSeconds;
	if (m.width > 0) md.pixelWidth = (int32_t)m.width;
	if (m.height > 0) md.pixelHeight = (int32_t)m.height;
	return md;
}

- (void)saveSelectedToGallery {
	NSMutableArray<NSURL *> *urls = [NSMutableArray array];
	NSMutableArray<SCIGallerySaveMetadata *> *metas = [NSMutableArray array];
	[self selectedFileURLs:urls metas:metas];

	if (!urls.count) {
		SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"Nothing to save"), nil);
		return;
	}

	[SCIMediaActions bulkSaveFilesToGallery:urls perFileMetadata:metas defaultMetadata:nil];
	[self exitSelectionMode];
}

- (void)shareSelected {
	NSMutableArray<NSURL *> *urls = [NSMutableArray array];
	NSMutableArray<SCIGallerySaveMetadata *> *metas = [NSMutableArray array];
	[self selectedFileURLs:urls metas:metas];

	if (!urls.count) {
		SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"Nothing to share"), nil);
		return;
	}

	if ([SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
		[SCIMediaActions bulkSaveFilesToGallery:urls perFileMetadata:metas defaultMetadata:nil];
	}
	[self presentShareSheetWithURLs:urls fromView:self.navigationController.toolbar ?: self.view exitOnComplete:YES];
}

- (void)confirmDeleteSelected {
	if (!self.selectedSids.count) return;

	UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Delete")
															  message:SCILocalized(@"Removes every preserved deleted message and its captured media for the current account. This cannot be undone.")
													   preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
		[self deleteSelected];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)deleteSelected {
	for (NSString *sid in self.selectedSids.allObjects) {
		[SCIDeletedMessagesStorage deleteMessageId:sid forOwnerPK:self.ownerPK];
	}
	[self exitSelectionMode];
}

#pragma mark - Search / header / table setup

- (void)installSearchController {
	UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
	sc.searchResultsUpdater = self;
	sc.obscuresBackgroundDuringPresentation = NO;
	sc.hidesNavigationBarDuringPresentation = NO;
	sc.searchBar.placeholder = SCILocalized(@"Search messages");
	sc.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.searchCtl = sc;
	self.navigationItem.searchController = sc;
	self.navigationItem.hidesSearchBarWhenScrolling = YES;
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

	if (@available(iOS 16.0, *)) {
		self.navigationItem.preferredSearchBarPlacement = UINavigationItemSearchBarPlacementStacked;
	}
	self.definesPresentationContext = YES;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
	self.filter.searchText = sc.searchBar.text;
	[self refilter];
}

- (UIView *)buildBannerHeader {
	UIView *banner = [UIView new];
	banner.frame = CGRectMake(0, 0, self.view.bounds.size.width, 64);
	banner.backgroundColor = [SCIPopupChrome backgroundColor];

	UIImageView *avatar = [UIImageView new];
	avatar.contentMode = UIViewContentModeScaleAspectFill;
	avatar.layer.cornerRadius = 18;
	avatar.layer.masksToBounds = YES;
	avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
	avatar.tintColor = UIColor.systemGray3Color;
	avatar.backgroundColor = UIColor.secondarySystemBackgroundColor;
	avatar.translatesAutoresizingMaskIntoConstraints = NO;
	[banner addSubview:avatar];

	UILabel *name = [UILabel new];
	name.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
	name.textColor = UIColor.labelColor;
	name.translatesAutoresizingMaskIntoConstraints = NO;
	[banner addSubview:name];

	UILabel *sub = [UILabel new];
	sub.font = [UIFont systemFontOfSize:13];
	sub.textColor = UIColor.secondaryLabelColor;
	sub.translatesAutoresizingMaskIntoConstraints = NO;
	[banner addSubview:sub];

	UIButton *openBtn = [UIButton buttonWithType:UIButtonTypeSystem];
	openBtn.translatesAutoresizingMaskIntoConstraints = NO;
	[openBtn setImage:[SCIIcon imageNamed:@"bcn_external-link_outline_24" pointSize:22 weight:UIImageSymbolWeightSemibold] forState:UIControlStateNormal];
	openBtn.tintColor = UIColor.labelColor;
	openBtn.accessibilityLabel = SCILocalized(@"Open profile");
	[openBtn addTarget:self action:@selector(bannerOpenProfileTapped) forControlEvents:UIControlEventTouchUpInside];
	[banner addSubview:openBtn];

	UIView *sep = [UIView new];
	sep.translatesAutoresizingMaskIntoConstraints = NO;
	sep.backgroundColor = UIColor.separatorColor;
	[banner addSubview:sep];

	[NSLayoutConstraint activateConstraints:@[
		[avatar.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:16],
		[avatar.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
		[avatar.widthAnchor constraintEqualToConstant:36],
		[avatar.heightAnchor constraintEqualToConstant:36],

		[name.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:10],
		[name.topAnchor constraintEqualToAnchor:avatar.topAnchor constant:1],
		[name.trailingAnchor constraintLessThanOrEqualToAnchor:openBtn.leadingAnchor constant:-12],

		[sub.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
		[sub.bottomAnchor constraintEqualToAnchor:avatar.bottomAnchor constant:-1],
		[sub.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],

		[openBtn.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-16],
		[openBtn.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
		[openBtn.widthAnchor constraintEqualToConstant:32],
		[openBtn.heightAnchor constraintEqualToConstant:32],

		[sep.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor],
		[sep.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor],
		[sep.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor],
		[sep.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
	]];

	self.bannerView = banner;
	self.bannerAvatar = avatar;
	self.bannerNameLabel = name;
	self.bannerSubLabel = sub;
	self.bannerOpenButton = openBtn;
	return banner;
}

- (void)bannerOpenProfileTapped {
	if (!self.group.senderUsername.length) return;
	[SCIURLOpener dismiss:self thenOpenInstagramProfileForUsername:self.group.senderUsername];
}

- (void)installTable {
	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.tableView.estimatedRowHeight = 80;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.backgroundColor = self.view.backgroundColor;
	[self.tableView registerClass:SCIDMMessageCell.class forCellReuseIdentifier:@"msg"];
	[self.view addSubview:self.tableView];

	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	if (self.bannerView) {
		CGFloat w = self.tableView.bounds.size.width;
		if (w > 1 && fabs(self.bannerView.frame.size.width - w) > 0.5) {
			CGRect f = self.bannerView.frame;
			f.size.width = w;
			self.bannerView.frame = f;
			self.tableView.tableHeaderView = self.bannerView;
		}
	}
}

#pragma mark - Data

- (void)reload {
	NSArray<SCIDeletedMessage *> *all = self.threadId.length
		? [SCIDeletedMessagesStorage messagesForThreadId:self.threadId ownerPK:self.ownerPK]
		: [SCIDeletedMessagesStorage messagesForSenderPK:self.senderPk ownerPK:self.ownerPK];

	if (all.count) {
		BOOL isGroup = self.group.isGroup;
		NSString *title = self.group.threadTitle, *avatar = self.group.threadAvatarURL;
		for (SCIDeletedMessage *m in all) {
			if (m.isGroup) isGroup = YES;
			if (!title.length && m.threadTitle.length) title = m.threadTitle;
			if (!avatar.length && m.threadAvatarURL.length) avatar = m.threadAvatarURL;
		}

		SCIDeletedMessageGroup *g = [SCIDeletedMessageGroup new];
		g.threadId = self.threadId;
		g.isGroup = isGroup;
		g.threadTitle = title;
		g.threadAvatarURL = avatar;
		g.senderPk = self.senderPk;
		g.senderUsername = all.firstObject.senderUsername;
		g.senderFullName = all.firstObject.senderFullName;
		g.senderProfilePicURL = all.firstObject.senderProfilePicURL;
		g.messages = all;
		self.group = g;
	}
	[self refreshHeader];
	[self refilter];
}

- (void)refilter {
	self.visibleMessages = [self.filter apply:self.group.messages];
	[self.tableView reloadData];
}

- (void)refreshHeader {
	if (self.group.isGroup) {
		NSString *title = self.group.threadTitle.length ? self.group.threadTitle : SCILocalized(@"Group chat");
		self.title = title;
		self.bannerNameLabel.text = title;

		NSUInteger people = self.group.distinctSenders.count;
		self.bannerSubLabel.text = [NSString stringWithFormat:SCILocalized(@"%lu people · %lu deleted"),
									(unsigned long)people, (unsigned long)self.group.count];

		self.bannerAvatar.image = [UIImage systemImageNamed:@"person.2.circle.fill"];
		self.bannerAvatar.tintColor = UIColor.systemGray3Color;
		if (self.group.threadAvatarURL.length) {
			__weak UIImageView *iv = self.bannerAvatar;
			[SCIImageCache loadImageFromURL:[NSURL URLWithString:self.group.threadAvatarURL] completion:^(UIImage *img) {
				if (img) iv.image = img;
			}];
		}
		self.bannerOpenButton.hidden = YES;
		return;
	}

	NSString *fn = self.group.senderFullName.length ? self.group.senderFullName : (self.group.senderUsername.length ? self.group.senderUsername : SCILocalized(@"Unknown user"));
	self.title = self.group.senderUsername.length ? [@"@" stringByAppendingString:self.group.senderUsername] : fn;
	self.bannerNameLabel.text = fn;

	NSString *handle = self.group.senderUsername.length ? [NSString stringWithFormat:@"@%@ · ", self.group.senderUsername] : @"";
	self.bannerSubLabel.text = [NSString stringWithFormat:SCILocalized(@"%@%lu deleted"), handle, (unsigned long)self.group.count];

	if (self.group.senderProfilePicURL.length) {
		__weak UIImageView *iv = self.bannerAvatar;
		[SCIImageCache loadImageFromURL:[NSURL URLWithString:self.group.senderProfilePicURL] completion:^(UIImage *img) {
			if (img) iv.image = img;
		}];
	}
	self.bannerOpenButton.hidden = self.group.senderUsername.length == 0;
}

- (void)storeChanged:(NSNotification *)note {
	if (!self.isViewLoaded || !self.view.window) return;
	[self reload];
	if (!self.group.count) [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Filter menu

static NSArray<NSArray<NSArray *> *> *sciFilterKindSections(void) {
	return @[
		@[@[SCILocalized(@"Photo"), @(SCIDeletedMessageKindPhoto), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindPhoto)],
		  @[SCILocalized(@"Video"), @(SCIDeletedMessageKindVideo), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindVideo)],
		  @[SCILocalized(@"GIF"), @(SCIDeletedMessageKindGif), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindGif)],
		  @[SCILocalized(@"Sticker"), @(SCIDeletedMessageKindSticker), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindSticker)]],
		@[@[SCILocalized(@"Voice"), @(SCIDeletedMessageKindVoice), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindVoice)],
		  @[SCILocalized(@"Audio"), @(SCIDeletedMessageKindAudioShare), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindAudioShare)]],
		@[@[SCILocalized(@"Share"), @(SCIDeletedMessageKindShare), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindShare)],
		  @[SCILocalized(@"Link"), @(SCIDeletedMessageKindLink), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindLink)]],
		@[@[SCILocalized(@"Text"), @(SCIDeletedMessageKindText), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindText)],
		  @[SCILocalized(@"Reaction removed"), @(SCIDeletedMessageKindReactionRemoved), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindReactionRemoved)],
		  @[SCILocalized(@"Other"), @(SCIDeletedMessageKindOther), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindOther)]],
	];
}

- (UIMenu *)buildFilterMenu {
	__weak typeof(self) ws = self;
	NSMutableArray<UIMenu *> *sections = [NSMutableArray array];

	for (NSArray<NSArray *> *group in sciFilterKindSections()) {
		NSMutableArray<UIAction *> *actions = [NSMutableArray array];

		for (NSArray *e in group) {
			SCIDeletedMessageKind k = [e[1] integerValue];
			UIAction *a = [UIAction actionWithTitle:e[0] image:[UIImage systemImageNamed:e[2]] identifier:nil handler:^(__kindof UIAction *_) {
				[ws.filter toggleKind:k];
				[ws refilter];
				[ws refreshFilterButton];
			}];
			a.state = [self.filter.kinds containsObject:@(k)] ? UIMenuElementStateOn : UIMenuElementStateOff;
			if (@available(iOS 17.0, *)) a.attributes |= UIMenuElementAttributesKeepsMenuPresented;
			[actions addObject:a];
		}

		[sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:actions]];
	}

	UIAction *ephemeral = [UIAction actionWithTitle:SCILocalized(@"Disappearing only") image:[UIImage systemImageNamed:@"timer"] identifier:nil handler:^(__kindof UIAction *_) {
		ws.filter.ephemeralOnly = !ws.filter.ephemeralOnly;
		[ws refilter];
		[ws refreshFilterButton];
	}];
	ephemeral.state = self.filter.ephemeralOnly ? UIMenuElementStateOn : UIMenuElementStateOff;
	if (@available(iOS 17.0, *)) ephemeral.attributes |= UIMenuElementAttributesKeepsMenuPresented;
	[sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[ephemeral]]];

	UIAction *reset = [UIAction actionWithTitle:SCILocalized(@"Reset") image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil handler:^(__kindof UIAction *_) {
		[ws.filter clearKinds];
		ws.filter.ephemeralOnly = NO;
		[ws refilter];
		[ws refreshFilterButton];
	}];
	reset.attributes = UIMenuElementAttributesDestructive;
	[sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[reset]]];

	NSUInteger n = self.filter.kinds.count + (self.filter.ephemeralOnly ? 1 : 0);
	NSString *menuTitle = n > 0 ? [NSString stringWithFormat:SCILocalized(@"Filter · %lu"), (unsigned long)n] : SCILocalized(@"Filter");
	return [UIMenu menuWithTitle:menuTitle children:sections];
}

- (void)refreshFilterButton {
	BOOL active = self.filter.hasKindFilter || self.filter.ephemeralOnly;
	self.filterButton.image = [UIImage systemImageNamed:active ? @"line.3.horizontal.decrease.circle.fill" : @"line.3.horizontal.decrease.circle"];
	self.filterButton.menu = [self buildFilterMenu];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.visibleMessages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	SCIDMMessageCell *cell = [tv dequeueReusableCellWithIdentifier:@"msg" forIndexPath:ip];
	SCIDeletedMessage *m = self.visibleMessages[ip.row];
	BOOL playing = m.kind == SCIDeletedMessageKindVoice && [self.playingMessageId isEqualToString:m.messageId] && self.audioIsPlaying;

	[cell applyMessage:m ownerPK:self.ownerPK playing:playing];
	[cell applySenderHeaderVisible:self.group.isGroup message:m];

	__weak typeof(self) ws = self;
	cell.onCellTap = self.inSelectionMode ? ^{ [ws toggleSelectionForMessage:m]; } : nil;
	cell.onBubbleTap = self.inSelectionMode ? nil : ^{ [ws openMessage:m]; };
	cell.onVoicePlayTap = ^{ [ws toggleVoicePlayback:m]; };
	cell.onVoiceSeekTo = ^(double seconds) { [ws seekVoicePlayback:m to:seconds]; };

	if ([self.playingMessageId isEqualToString:m.messageId] && self.audioPlayer) {
		[cell setVoiceProgressSeconds:[self audioCurrentSeconds]];
	}

	[cell applySelectionMode:self.inSelectionMode selected:[self.selectedSids containsObject:m.messageId] selectable:YES];
	return cell;
}

- (void)toggleSelectionForMessage:(SCIDeletedMessage *)m {
	if (!self.inSelectionMode || !m.messageId.length) return;

	if ([self.selectedSids containsObject:m.messageId]) [self.selectedSids removeObject:m.messageId];
	else [self.selectedSids addObject:m.messageId];

	[[self visibleCellForMessageId:m.messageId] applySelectionMode:YES selected:[self.selectedSids containsObject:m.messageId] selectable:YES];
	[self refreshSelectionCount];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
	if (ip.row >= (NSInteger)self.visibleMessages.count) return nil;
	SCIDeletedMessage *m = self.visibleMessages[ip.row];

	__weak typeof(self) ws = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *_) {
		return [ws contextMenuForMessage:m];
	}];
}

- (UIMenu *)contextMenuForMessage:(SCIDeletedMessage *)m {
	NSMutableArray<UIMenuElement *> *primary = [NSMutableArray array];
	NSMutableArray<UIMenuElement *> *saveSection = [NSMutableArray array];
	__weak typeof(self) ws = self;

	BOOL hasText = m.text.length > 0;
	BOOL hasMedia = m.kind == SCIDeletedMessageKindPhoto || m.kind == SCIDeletedMessageKindVideo || m.kind == SCIDeletedMessageKindGif || m.kind == SCIDeletedMessageKindVoice || m.kind == SCIDeletedMessageKindAudioShare || m.kind == SCIDeletedMessageKindSticker;
	BOOL isAudioOnly = m.kind == SCIDeletedMessageKindVoice || m.kind == SCIDeletedMessageKindAudioShare;
	NSURL *fileURL = [self localFileURLForMessage:m];

	if (hasText) {
		[primary addObject:[UIAction actionWithTitle:SCILocalized(@"Copy text") image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__kindof UIAction *_) {
			UIPasteboard.generalPasteboard.string = m.text;
			SCINotifySuccess(SCI_NOTIF_COPY_URL, SCILocalized(@"Copied"), nil);
		}]];
	}

	if (m.editCount > 0) {
		[primary addObject:[UIAction actionWithTitle:SCILocalized(@"Show edit history") image:[UIImage systemImageNamed:@"pencil.line"] identifier:nil handler:^(__kindof UIAction *_) {
			[ws presentEditHistory:m];
		}]];
	}

	if (hasMedia) {
		[primary addObject:[UIAction actionWithTitle:(isAudioOnly ? SCILocalized(@"Play") : SCILocalized(@"View"))
												image:[UIImage systemImageNamed:(isAudioOnly ? @"play.circle" : @"arrow.up.left.and.arrow.down.right")]
										   identifier:nil
											  handler:^(__kindof UIAction *_) {
			[ws openMessage:m];
		}]];
	}

	if (fileURL && hasMedia && !isAudioOnly) {
		[saveSection addObject:[UIAction actionWithTitle:SCILocalized(@"Save to Photos") image:[UIImage systemImageNamed:@"photo.on.rectangle"] identifier:nil handler:^(__kindof UIAction *_) {
			[SCIPhotoAlbum saveFileToAlbum:fileURL completion:^(BOOL ok, NSError *err) {
				if (ok) SCINotifySuccess(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Saved to Photos"), nil);
				else SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Save failed"), err.localizedDescription ?: @"");
			}];
		}]];
	}

	if (fileURL && hasMedia && [SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
		[saveSection addObject:[UIAction actionWithTitle:SCILocalized(@"Save to Gallery") image:[UIImage systemImageNamed:@"square.stack.3d.up"] identifier:nil handler:^(__kindof UIAction *_) {
			[SCIMediaActions bulkSaveFilesToGallery:@[fileURL] perFileMetadata:@[[ws gallerySaveMetadataForMessage:m]] defaultMetadata:nil];
		}]];
	}

	if (fileURL) {
		[saveSection addObject:[UIAction actionWithTitle:SCILocalized(@"Share") image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(__kindof UIAction *_) {
			if ([SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
				[SCIMediaActions bulkSaveFilesToGallery:@[fileURL] perFileMetadata:@[[ws gallerySaveMetadataForMessage:m]] defaultMetadata:nil];
			}
			[ws presentShareSheetWithURLs:@[fileURL] fromView:ws.view exitOnComplete:NO];
		}]];
	}

	if (m.mediaURL.length) {
		[saveSection addObject:[UIAction actionWithTitle:SCILocalized(@"Copy URL") image:[UIImage systemImageNamed:@"link"] identifier:nil handler:^(__kindof UIAction *_) {
			UIPasteboard.generalPasteboard.string = m.mediaURL;
			SCINotifySuccess(SCI_NOTIF_COPY_URL, SCILocalized(@"Copied"), nil);
		}]];
	}

	UIAction *del = [UIAction actionWithTitle:SCILocalized(@"Delete") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__kindof UIAction *_) {
		[SCIDeletedMessagesStorage deleteMessageId:m.messageId forOwnerPK:ws.ownerPK];
	}];
	del.attributes = UIMenuElementAttributesDestructive;

	NSMutableArray<UIMenu *> *sections = [NSMutableArray array];
	if (primary.count) [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:primary]];
	if (saveSection.count) [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:saveSection]];
	[sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[del]]];
	return [UIMenu menuWithTitle:@"" children:sections];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	SCIDeletedMessage *m = self.visibleMessages[ip.row];
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SCILocalized(@"Delete") handler:^(UIContextualAction *a, __kindof UIView *src, void (^done)(BOOL)) {
		[SCIDeletedMessagesStorage deleteMessageId:m.messageId forOwnerPK:self.ownerPK];
		done(YES);
	}];
	del.image = [UIImage systemImageNamed:@"trash"];
	return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

#pragma mark - Open message

- (void)openMessage:(SCIDeletedMessage *)m {
	if (m.kind == SCIDeletedMessageKindReactionRemoved) {
		[self presentReactionDetails:m];
		return;
	}
	if (m.kind == SCIDeletedMessageKindText) {
		m.text.length ? [self presentTextMessage:m] : [self presentInfoSheet:m];
		return;
	}
	if (m.kind == SCIDeletedMessageKindVoice) {
		[self toggleVoicePlayback:m];
		return;
	}
	if (m.kind == SCIDeletedMessageKindAudioShare) {
		[self openAudioShare:m];
		return;
	}
	if (m.kind == SCIDeletedMessageKindShare || m.kind == SCIDeletedMessageKindLink) {
		[self openShareOrLink:m];
		return;
	}
	[self openMediaMessage:m];
}

- (void)presentReactionDetails:(SCIDeletedMessage *)m {
	NSString *reactor = m.senderUsername.length ? [@"@" stringByAppendingString:m.senderUsername] : (m.senderFullName.length ? m.senderFullName : SCILocalized(@"Someone"));
	NSString *emoji = m.reactionEmoji.length ? m.reactionEmoji : @"♡";
	NSString *content = m.text.length ? m.text : SCILocalized(@"a message");
	NSString *when = [SCIDeletedMessagesDate stringForDate:(m.deletedAt ?: m.capturedAt)];

	NSMutableString *body = [NSMutableString string];
	[body appendFormat:SCILocalized(@"%@ removed the %@ reaction."), reactor, emoji];
	NSString *on = m.reactionTargetUsername.length
		? [NSString stringWithFormat:SCILocalized(@"on @%@: %@"), m.reactionTargetUsername, content]
		: [NSString stringWithFormat:SCILocalized(@"on: %@"), content];
	[body appendFormat:@"\n\n%@", on];
	if (when.length) [body appendFormat:@"\n\n%@", [NSString stringWithFormat:SCILocalized(@"Removed %@"), when]];

	UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Reaction removed")
															  message:body
													   preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		UIPasteboard.generalPasteboard.string = content;
		SCINotifySuccess(SCI_NOTIF_COPY_URL, SCILocalized(@"Copied"), nil);
	}]];
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Done") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)openAudioShare:(SCIDeletedMessage *)m {
	NSURL *url = [self localFileURLForMessage:m] ?: (m.mediaURL.length ? [NSURL URLWithString:m.mediaURL] : nil);
	if (!url) {
		[self presentInfoSheet:m];
		return;
	}

	NSArray<NSString *> *parts = m.text.length ? [m.text componentsSeparatedByString:@"\n"] : @[];
	NSString *caption = parts.count >= 2 ? [NSString stringWithFormat:@"%@ — %@", parts[0], parts[1]] : (parts.firstObject ?: @"");
	[SCIMediaViewer showItem:[SCIMediaViewerItem itemWithAudioURL:url caption:caption]];
}

- (void)openShareOrLink:(SCIDeletedMessage *)m {
	if (!m.mediaURL.length) {
		[self presentInfoSheet:m];
		return;
	}

	NSURL *u = [NSURL URLWithString:m.mediaURL];
	if (!u) {
		[self presentInfoSheet:m];
		return;
	}

	NSString *lower = m.mediaURL.lowercaseString;
	if ([lower containsString:@"live_location"] || ([lower containsString:@"latitude="] && [lower containsString:@"longitude="])) {
		NSURLComponents *comps = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
		NSString *lat = nil;
		NSString *lng = nil;

		for (NSURLQueryItem *q in comps.queryItems) {
			if ([q.name isEqualToString:@"latitude"]) lat = q.value;
			else if ([q.name isEqualToString:@"longitude"]) lng = q.value;
		}

		if (lat.length && lng.length) {
			NSString *label = [m.text componentsSeparatedByString:@"\n"].firstObject ?: SCILocalized(@"Live location");
			NSString *q = [label stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
			[SCIURLOpener dismiss:self thenOpenURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://maps.apple.com/?ll=%@,%@&q=%@", lat, lng, q ?: @""]]];
			return;
		}
	}

	[SCIURLOpener dismiss:self thenOpenURL:u];
}

- (void)openMediaMessage:(SCIDeletedMessage *)m {
	// No blob and the link is known-dead — show the info sheet instead of a doomed load.
	if (![self localFileURLForMessage:m] &&
		(m.mediaStatus == SCIDeletedMessageMediaStatusFailed || m.mediaStatus == SCIDeletedMessageMediaStatusUnavailable)) {
		[self presentInfoSheet:m];
		return;
	}

	NSURL *url = [self bestMediaURLForMessage:m];
	if (!url) {
		[self presentInfoSheet:m];
		return;
	}

	NSString *caption = self.group.senderUsername.length ? [@"@" stringByAppendingString:self.group.senderUsername] : (self.group.senderFullName ?: @"");

	if (m.kind == SCIDeletedMessageKindGif) [SCIMediaViewer showItem:[SCIMediaViewerItem itemWithAnimatedImageURL:url caption:caption]];
	else if (m.kind == SCIDeletedMessageKindVideo) [SCIMediaViewer showWithVideoURL:url photoURL:nil caption:caption];
	else [SCIMediaViewer showWithVideoURL:nil photoURL:url caption:caption];
}

- (NSURL *)bestMediaURLForMessage:(SCIDeletedMessage *)m {
	NSURL *local = [self localFileURLForMessage:m];
	if (local) return local;
	if (m.mediaURL.length) return [NSURL URLWithString:m.mediaURL];
	if (m.thumbnailURL.length) return [NSURL URLWithString:m.thumbnailURL];
	return nil;
}

#pragma mark - Voice playback

- (double)audioCurrentSeconds {
	if (!self.audioPlayer) return 0;
	CMTime t = self.audioPlayer.currentTime;
	return CMTIME_IS_INDEFINITE(t) ? 0 : CMTimeGetSeconds(t);
}

- (void)toggleVoicePlayback:(SCIDeletedMessage *)m {
	if (!m.messageId.length) return;

	if ([self.playingMessageId isEqualToString:m.messageId] && self.audioPlayer) {
		self.audioIsPlaying ? [self.audioPlayer pause] : [self.audioPlayer play];
		self.audioIsPlaying = !self.audioIsPlaying;
		[[self visibleCellForMessageId:m.messageId] setVoicePlayingFlag:self.audioIsPlaying];
		return;
	}

	[self stopVoicePlayback];

	NSURL *url = [self localFileURLForMessage:m] ?: (m.mediaURL.length ? [NSURL URLWithString:m.mediaURL] : nil);
	if (!url) {
		[self presentInfoSheet:m];
		return;
	}

	[AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
	[AVAudioSession.sharedInstance setActive:YES error:nil];

	AVPlayer *p = [AVPlayer playerWithURL:url];
	p.automaticallyWaitsToMinimizeStalling = YES;
	self.audioPlayer = p;
	self.playingMessageId = m.messageId;
	self.audioIsPlaying = YES;
	self.audioDuration = m.durationSeconds > 0 ? m.durationSeconds : 0;

	__weak typeof(self) ws = self;
	self.audioTimeObserver = [p addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.1, 600)
															  queue:dispatch_get_main_queue()
														 usingBlock:^(CMTime _) {
		[ws audioProgressTick];
	}];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioDidFinish:) name:AVPlayerItemDidPlayToEndTimeNotification object:p.currentItem];

	[p play];
	[self refreshVisibleVoiceCells];
}

- (void)stopVoicePlayback {
	if (self.audioTimeObserver) {
		[self.audioPlayer removeTimeObserver:self.audioTimeObserver];
		self.audioTimeObserver = nil;
	}

	[NSNotificationCenter.defaultCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
	[self.audioPlayer pause];
	self.audioPlayer = nil;
	self.playingMessageId = nil;
	self.audioIsPlaying = NO;
	self.audioDuration = 0;
}

- (void)audioProgressTick {
	[[self visibleCellForMessageId:self.playingMessageId] setVoiceProgressSeconds:[self audioCurrentSeconds]];
}

- (void)audioDidFinish:(NSNotification *)note {
	[self stopVoicePlayback];
	[self refreshVisibleVoiceCells];
}

- (void)seekVoicePlayback:(SCIDeletedMessage *)m to:(double)seconds {
	if (![self.playingMessageId isEqualToString:m.messageId] || !self.audioPlayer) return;
	[self.audioPlayer seekToTime:CMTimeMakeWithSeconds(MAX(0, seconds), 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (void)refreshVisibleVoiceCells {
	for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
		if (ip.row >= (NSInteger)self.visibleMessages.count) continue;

		SCIDeletedMessage *m = self.visibleMessages[ip.row];
		if (m.kind != SCIDeletedMessageKindVoice) continue;

		SCIDMMessageCell *cell = [self.tableView cellForRowAtIndexPath:ip];
		if (![cell isKindOfClass:SCIDMMessageCell.class]) continue;

		BOOL playing = [self.playingMessageId isEqualToString:m.messageId] && self.audioIsPlaying;
		[cell applyMessage:m ownerPK:self.ownerPK playing:playing];

		__weak typeof(self) ws = self;
		cell.onBubbleTap = ^{ [ws openMessage:m]; };
		cell.onVoicePlayTap = ^{ [ws toggleVoicePlayback:m]; };
		cell.onVoiceSeekTo = ^(double seconds) { [ws seekVoicePlayback:m to:seconds]; };

		if (playing) [cell setVoiceProgressSeconds:[self audioCurrentSeconds]];
	}
}

#pragma mark - Sheets

- (void)presentTextMessage:(SCIDeletedMessage *)m {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:SCIDeletedMessageKindLocalizedName(m.kind)
															  message:m.text
													   preferredStyle:UIAlertControllerStyleAlert];

	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		UIPasteboard.generalPasteboard.string = m.text;
	}]];

	if (m.editCount > 0) {
		__weak typeof(self) ws = self;
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Edit history") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
			[ws presentEditHistory:m];
		}]];
	}

	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Close") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)presentEditHistory:(SCIDeletedMessage *)m {
	[SCIPopupChrome presentVC:[[SCIDMEditHistoryViewController alloc] initWithMessage:m] from:self];
}

- (void)presentInfoSheet:(SCIDeletedMessage *)m {
	NSMutableString *body = [NSMutableString string];
	if (m.previewText.length) [body appendFormat:@"%@\n\n", m.previewText];
	[body appendFormat:SCILocalized(@"Kind: %@\n"), SCIDeletedMessageKindLocalizedName(m.kind)];
	if (m.isEphemeral) [body appendFormat:@"%@\n", SCILocalized(@"Disappearing (view-once) media")];
	if (m.deletedAt) [body appendFormat:SCILocalized(@"Deleted: %@\n"), m.deletedAt];

	NSString *note = SCIDeletedMessageMediaStatusNote(m);
	if (note.length) [body appendFormat:@"%@\n", note];
	else if (m.mediaURL.length) [body appendString:SCILocalized(@"Source URL recorded but media not stored.\n")];

	UIAlertController *a = [UIAlertController alertControllerWithTitle:SCIDeletedMessageKindLocalizedName(m.kind)
															  message:body
													   preferredStyle:UIAlertControllerStyleAlert];

	BOOL canRetry = ![self localFileURLForMessage:m] &&
		(m.mediaURL.length || m.mediaPk.length) &&
		(m.mediaStatus == SCIDeletedMessageMediaStatusFailed || m.mediaStatus == SCIDeletedMessageMediaStatusUnavailable);

	if (canRetry) {
		NSString *ownerPK = self.ownerPK;
		NSString *mid = m.messageId;
		[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Try to download again") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
			sciDMRetryMediaDownload(mid, ownerPK);
			SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"Retrying download…"), nil);
		}]];
	}

	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Close") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

@end