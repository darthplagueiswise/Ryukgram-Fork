#import "RYGQualityPicker.h"
#import "RYGFFmpeg.h"
#import "Utils.h"
#import "InstagramHeaders.h"
#import "ActionButton/RYGMediaActions.h"
#import "UI/RYGIcon.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

static NSString * const kRYGQualityCellId = @"RYGQualityCell";

static inline UIImage *RYGQualityIcon(NSString *name, CGFloat size) {
	if ([name hasPrefix:@"ig_icon_"] || [name hasPrefix:@"bcn_"])
		return [RYGIcon menuImageNamed:name pointSize:size];
	return [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightMedium]];
}

static inline NSString *RYGQualityBandwidth(NSInteger bandwidth) {
	if (bandwidth <= 0) return @"";
	return bandwidth >= 1000000 ? [NSString stringWithFormat:@"%.1f Mbps", bandwidth / 1000000.0] : [NSString stringWithFormat:@"%ld Kbps", (long)(bandwidth / 1000)];
}

static inline NSString *RYGQualityFileSize(long long bytes) {
	if (bytes <= 0) return @"";
	NSByteCountFormatter *fmt = [NSByteCountFormatter new];
	fmt.countStyle = NSByteCountFormatterCountStyleFile;
	fmt.allowedUnits = bytes >= 1024 * 1024 ? NSByteCountFormatterUseMB : NSByteCountFormatterUseKB;
	return [fmt stringFromByteCount:bytes];
}

static inline NSString *RYGQualityAppendInfo(NSString *info, NSString *extra) {
	if (!extra.length) return info ?: @"";
	if (!info.length) return extra;
	return [NSString stringWithFormat:@"%@ • %@", info, extra];
}

static inline NSString *RYGQualityCodec(NSString *codecs, NSString *fallback) {
	if (!codecs.length) return fallback ?: @"";
	return [codecs componentsSeparatedByString:@"."].firstObject ?: codecs;
}

static inline void RYGRemoveFiles(NSArray<NSString *> *paths) {
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *path in paths) {
		if (path.length) [fm removeItemAtPath:path error:nil];
	}
}

@interface _RYGQualityCell : UITableViewCell
@property (nonatomic, strong) UIButton *iconButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
- (void)setTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(UIImage *)icon menu:(UIMenu *)menu;
- (void)setLoading:(BOOL)loading;
@end

@implementation _RYGQualityCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	self.selectionStyle = UITableViewCellSelectionStyleDefault;
	self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

	_iconButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_iconButton.tintColor = UIColor.labelColor;
	_iconButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_iconButton];

	_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	_spinner.hidesWhenStopped = YES;
	_spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_spinner];

	_titleLabel = [UILabel new];
	_titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightSemibold];
	_titleLabel.textColor = UIColor.labelColor;
	_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_titleLabel];

	_subtitleLabel = [UILabel new];
	_subtitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
	_subtitleLabel.textColor = UIColor.secondaryLabelColor;
	_subtitleLabel.numberOfLines = 1;
	_subtitleLabel.adjustsFontSizeToFitWidth = YES;
	_subtitleLabel.minimumScaleFactor = 0.82;
	_subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_subtitleLabel];

	_menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_menuButton.tintColor = UIColor.secondaryLabelColor;
	_menuButton.showsMenuAsPrimaryAction = YES;
	_menuButton.translatesAutoresizingMaskIntoConstraints = NO;
	[_menuButton setImage:RYGQualityIcon(@"ellipsis.circle", 18.0) forState:UIControlStateNormal];
	[self.contentView addSubview:_menuButton];

	[NSLayoutConstraint activateConstraints:@[
		[_iconButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0],
		[_iconButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_iconButton.widthAnchor constraintEqualToConstant:34.0],
		[_iconButton.heightAnchor constraintEqualToConstant:34.0],

		[_spinner.centerXAnchor constraintEqualToAnchor:_iconButton.centerXAnchor],
		[_spinner.centerYAnchor constraintEqualToAnchor:_iconButton.centerYAnchor],

		[_menuButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],
		[_menuButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_menuButton.widthAnchor constraintEqualToConstant:34.0],
		[_menuButton.heightAnchor constraintEqualToConstant:34.0],

		[_titleLabel.leadingAnchor constraintEqualToAnchor:_iconButton.trailingAnchor constant:12.0],
		[_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_menuButton.leadingAnchor constant:-8.0],
		[_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9.0],

		[_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
		[_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_menuButton.leadingAnchor constant:-8.0],
		[_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3.0],
		[_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-9.0]
	]];

	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self.iconButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
	self.iconButton.tag = 0;
	self.iconButton.hidden = NO;
	self.menuButton.hidden = NO;
	self.menuButton.menu = nil;
	self.accessoryType = UITableViewCellAccessoryNone;
	[self setLoading:NO];
}

- (void)setTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(UIImage *)icon menu:(UIMenu *)menu {
	self.titleLabel.text = title ?: @"";
	self.subtitleLabel.text = subtitle ?: @"";
	[self.iconButton setImage:icon forState:UIControlStateNormal];
	self.menuButton.menu = menu;
	self.menuButton.hidden = menu == nil;
}

- (void)setLoading:(BOOL)loading {
	self.iconButton.hidden = loading;
	loading ? [self.spinner startAnimating] : [self.spinner stopAnimating];
}

@end

typedef NS_ENUM(NSInteger, RYGQSectionKind) {
	RYGQSectionStandard,
	RYGQSectionHD,
	RYGQSectionVideoOnly,
	RYGQSectionAudio,
	RYGQSectionPhoto,
};

@interface _RYGQualitySheetVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *optionsButton;
@property (nonatomic, strong) NSArray<NSNumber *> *sections;
@property (nonatomic, strong) NSArray<RYGDashRepresentation *> *videoReps;
@property (nonatomic, strong) NSArray<RYGDashRepresentation *> *allAudioReps;
@property (nonatomic, strong) RYGDashRepresentation *audioRep;
@property (nonatomic, strong) NSURL *standardURL;
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, strong) id mediaRef;
@property (nonatomic, assign) DownloadAction saveAction;
@property (nonatomic, assign) BOOL hasAudio;
@property (nonatomic, assign) BOOL standardPending;
@property (nonatomic, copy) void (^onPickStandard)(void);
@property (nonatomic, copy) void (^onPickHD)(RYGDashRepresentation *video, RYGDashRepresentation *audio);
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *sizeCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *sizeLoading;
@property (nonatomic, strong) NSMutableIndexSet *loadingVideoRows;
@end

@implementation _RYGQualitySheetVC

- (void)viewDidLoad {
	[super viewDidLoad];

	self.sizeCache = [NSMutableDictionary dictionary];
	self.sizeLoading = [NSMutableSet set];
	self.loadingVideoRows = [NSMutableIndexSet indexSet];

	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.titleLabel = [UILabel new];
	self.titleLabel.text = RYGLocalized(@"Download Quality");
	self.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
	self.titleLabel.textColor = UIColor.labelColor;
	self.titleLabel.textAlignment = NSTextAlignmentCenter;
	self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.titleLabel];

	self.optionsButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.optionsButton.tintColor = UIColor.whiteColor;
	self.optionsButton.showsMenuAsPrimaryAction = YES;
	self.optionsButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.optionsButton.hidden = self.audioRep.url == nil;
	[self.optionsButton setImage:RYGQualityIcon(@"ellipsis", 18.0) forState:UIControlStateNormal];
	[self.view addSubview:self.optionsButton];
	[self refreshOptionsButton];

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 58.0;
	self.tableView.backgroundColor = UIColor.clearColor;
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.sectionHeaderTopPadding = 8.0;
	[self.tableView registerClass:_RYGQualityCell.class forCellReuseIdentifier:kRYGQualityCellId];
	[self.view addSubview:self.tableView];

	[NSLayoutConstraint activateConstraints:@[
		[self.titleLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24.0],
		[self.titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

		[self.optionsButton.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
		[self.optionsButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18.0],
		[self.optionsButton.widthAnchor constraintEqualToConstant:40.0],
		[self.optionsButton.heightAnchor constraintEqualToConstant:40.0],

		[self.tableView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8.0],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
	]];

	[self rebuildSections];
	[self hydrateStandardIfNeeded];
}

- (void)hydrateStandardIfNeeded {
	if (self.standardURL || !self.mediaRef) return;

	self.standardPending = YES;
	[self rebuildSections];

	__weak typeof(self) weakSelf = self;
	[RYGMediaActions progressiveVideoURLForMedia:self.mediaRef completion:^(NSURL *url) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		strongSelf.standardURL = url;
		strongSelf.standardPending = NO;
		[strongSelf rebuildSections];
		[strongSelf.tableView reloadData];
	}];
}

- (void)refreshOptionsButton {
	BOOL on = [RYGUtils getBoolPref:@"enhance_download_advanced"];

	UIAction *adv = [UIAction actionWithTitle:RYGLocalized(@"Advanced")
										image:nil
								   identifier:nil
									  handler:^(__unused UIAction *a) {
		[RYGUtils setPref:@(!on) forKey:@"enhance_download_advanced"];
		[self refreshOptionsButton];
		[self rebuildSections];
		[self.tableView reloadData];
	}];
	adv.subtitle = RYGLocalized(@"Video-only & every audio track");
	adv.state = on ? UIMenuElementStateOn : UIMenuElementStateOff;

	self.optionsButton.menu = [UIMenu menuWithTitle:@"" children:@[adv]];
}

- (BOOL)advanced {
	return [RYGUtils getBoolPref:@"enhance_download_advanced"] && self.audioRep.url != nil;
}

- (void)rebuildSections {
	NSMutableArray *s = [NSMutableArray array];
	if (self.standardURL || self.standardPending) [s addObject:@(RYGQSectionStandard)];
	[s addObject:@(RYGQSectionHD)];
	if (self.advanced) [s addObject:@(RYGQSectionVideoOnly)];
	if (self.audioRep.url) [s addObject:@(RYGQSectionAudio)];
	if (self.photoURL) [s addObject:@(RYGQSectionPhoto)];
	self.sections = s;
}

- (RYGQSectionKind)kindForSection:(NSInteger)section {
	return (RYGQSectionKind)self.sections[section].integerValue;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch ([self kindForSection:section]) {
		case RYGQSectionHD:
		case RYGQSectionVideoOnly: return self.videoReps.count;
		case RYGQSectionAudio: return self.advanced ? self.allAudioReps.count : 1;
		default: return 1;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch ([self kindForSection:section]) {
		case RYGQSectionStandard: return RYGLocalized(@"Standard");
		case RYGQSectionHD: return RYGLocalized(@"HD");
		case RYGQSectionVideoOnly: return RYGLocalized(@"Video only");
		case RYGQSectionAudio: return RYGLocalized(@"Audio");
		case RYGQSectionPhoto: return RYGLocalized(@"Extras");
	}
	return @"";
}

- (UIImage *)previewIcon {
	return RYGQualityIcon(self.hasAudio ? @"ig_icon_play_prism_filled_24" : @"ig_icon_volume_off_filled_24", 18.0);
}

- (NSString *)qualityLabelForRep:(RYGDashRepresentation *)rep {
	if (rep.width > 0 && rep.height > 0) return [NSString stringWithFormat:@"%ldp", (long)MIN(rep.width, rep.height)];
	return rep.qualityLabel.length ? rep.qualityLabel : RYGLocalized(@"HD");
}

- (NSString *)subtitleForRep:(RYGDashRepresentation *)rep silent:(BOOL)silent {
	NSMutableArray *parts = [NSMutableArray array];

	if (rep.width > 0 && rep.height > 0)
		[parts addObject:[NSString stringWithFormat:@"%ld×%ld", (long)rep.width, (long)rep.height]];

	if (rep.frameRate > 0)
		[parts addObject:[NSString stringWithFormat:@"%.0ffps", rep.frameRate]];

	if (rep.codecs.length)
		[parts addObject:RYGQualityCodec(rep.codecs, rep.codecs)];

	if (silent)
		[parts addObject:RYGLocalized(@"silent")];

	return [parts componentsJoinedByString:@" • "];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
	_RYGQualityCell *cell = [tableView dequeueReusableCellWithIdentifier:kRYGQualityCellId forIndexPath:ip];
	[cell.iconButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
	cell.contentView.alpha = 1.0;
	cell.userInteractionEnabled = YES;

	switch ([self kindForSection:ip.section]) {
		case RYGQSectionStandard: {
			NSString *subtitle;
			if (self.standardURL) {
				subtitle = self.hasAudio ? RYGLocalized(@"720p • progressive • fastest") : RYGLocalized(@"720p • progressive • silent");
				subtitle = RYGQualityAppendInfo(subtitle, [self sizeTextForURL:self.standardURL]);
			} else {
				subtitle = RYGLocalized(@"Checking…");
			}

			[cell setTitle:RYGLocalized(@"Standard") subtitle:subtitle icon:self.previewIcon menu:[self menuForStandard]];
			cell.contentView.alpha = self.standardURL ? 1.0 : 0.5;
			cell.userInteractionEnabled = self.standardURL != nil;
			cell.iconButton.hidden = self.standardURL == nil;
			cell.iconButton.tag = -1;
			[cell.iconButton addTarget:self action:@selector(playStandardPreview) forControlEvents:UIControlEventTouchUpInside];
			return cell;
		}

		case RYGQSectionHD: {
			RYGDashRepresentation *rep = self.videoReps[ip.row];
			NSString *bandwidth = RYGQualityBandwidth(rep.bandwidth);
			NSString *title = bandwidth.length ? [NSString stringWithFormat:@"%@ • %@", [self qualityLabelForRep:rep], bandwidth] : [self qualityLabelForRep:rep];

			NSString *subtitle = [self subtitleForRep:rep silent:!self.hasAudio];
			subtitle = RYGQualityAppendInfo(subtitle, [self combinedSizeTextForVideo:rep.url audio:self.audioRep.url]);

			[cell setTitle:title subtitle:subtitle icon:self.previewIcon menu:[self menuForVideoRep:rep]];
			cell.iconButton.tag = ip.row;
			[cell.iconButton addTarget:self action:@selector(playPreview:) forControlEvents:UIControlEventTouchUpInside];
			[cell setLoading:[self.loadingVideoRows containsIndex:ip.row]];
			return cell;
		}

		case RYGQSectionVideoOnly: {
			RYGDashRepresentation *rep = self.videoReps[ip.row];
			NSString *bandwidth = RYGQualityBandwidth(rep.bandwidth);
			NSString *title = bandwidth.length ? [NSString stringWithFormat:@"%@ • %@", [self qualityLabelForRep:rep], bandwidth] : [self qualityLabelForRep:rep];

			NSString *subtitle = [self subtitleForRep:rep silent:YES];
			subtitle = RYGQualityAppendInfo(subtitle, [self sizeTextForURL:rep.url]);

			[cell setTitle:title subtitle:subtitle icon:RYGQualityIcon(@"ig_icon_volume_off_filled_24", 18.0) menu:[self menuForVideoRep:rep]];
			cell.iconButton.tag = ip.row;
			[cell.iconButton addTarget:self action:@selector(playVideoOnlyPreview:) forControlEvents:UIControlEventTouchUpInside];
			return cell;
		}

		case RYGQSectionAudio: {
			RYGDashRepresentation *rep = self.advanced ? self.allAudioReps[ip.row] : self.audioRep;
			NSMutableArray *parts = [NSMutableArray array];
			NSString *codec = RYGQualityCodec(rep.codecs, @"m4a");
			NSString *bandwidth = RYGQualityBandwidth(rep.bandwidth);

			if (codec.length) [parts addObject:codec];
			if (bandwidth.length) [parts addObject:bandwidth];

			NSString *subtitle = parts.count ? [parts componentsJoinedByString:@" • "] : @"m4a";
			subtitle = RYGQualityAppendInfo(subtitle, [self sizeTextForURL:rep.url]);

			NSString *title = self.advanced && self.allAudioReps.count > 1
				? [NSString stringWithFormat:RYGLocalized(@"Audio track %ld"), (long)(ip.row + 1)]
				: RYGLocalized(@"Audio only");
			[cell setTitle:title subtitle:subtitle icon:RYGQualityIcon(@"ig_icon_audio_wave_outline_24", 18.0) menu:[self menuForAudioRep:rep]];
			return cell;
		}

		case RYGQSectionPhoto: {
			NSString *subtitle = RYGQualityAppendInfo(RYGLocalized(@"Raw image"), [self sizeTextForURL:self.photoURL]);
			[cell setTitle:RYGLocalized(@"Photo") subtitle:subtitle icon:RYGQualityIcon(@"ig_icon_photo_filled_24", 18.0) menu:nil];
			return cell;
		}
	}
	return cell;
}

- (UIMenu *)menuForStandard {
	if (!self.standardURL) return nil;

	NSURL *url = self.standardURL;
	UIAction *copy = [UIAction actionWithTitle:RYGLocalized(@"Copy video URL") image:RYGQualityIcon(@"video.fill", 18.0) identifier:nil handler:^(__unused UIAction *action) {
		UIPasteboard.generalPasteboard.string = url.absoluteString;
		RYGNotifySuccess(RYG_NOTIF_COPY_QUALITY_URL, RYGLocalized(@"Copied video URL"), nil);
	}];

	return [UIMenu menuWithTitle:@"" children:@[copy]];
}

- (UIMenu *)menuForVideoRep:(RYGDashRepresentation *)rep {
	NSURL *videoURL = rep.url;
	NSURL *audioURL = self.audioRep.url;

	UIAction *copyVideo = [UIAction actionWithTitle:RYGLocalized(@"Copy video URL") image:RYGQualityIcon(@"video.fill", 18.0) identifier:nil handler:^(__unused UIAction *action) {
		if (!videoURL) return;
		UIPasteboard.generalPasteboard.string = videoURL.absoluteString;
		RYGNotifySuccess(RYG_NOTIF_COPY_QUALITY_URL, RYGLocalized(@"Copied video URL"), nil);
	}];

	UIAction *copyInfo = [UIAction actionWithTitle:RYGLocalized(@"Copy quality info") image:RYGQualityIcon(@"info.circle", 18.0) identifier:nil handler:^(__unused UIAction *action) {
		NSString *info = [NSString stringWithFormat:@"%@ — %ld×%ld — %@", [self qualityLabelForRep:rep], (long)rep.width, (long)rep.height, RYGQualityBandwidth(rep.bandwidth)];
		UIPasteboard.generalPasteboard.string = info;
		RYGNotifySuccess(RYG_NOTIF_COPY_QUALITY_URL, RYGLocalized(@"Copied quality info"), nil);
	}];

	NSMutableArray *items = [NSMutableArray arrayWithObjects:copyVideo, copyInfo, nil];

	if (audioURL) {
		UIAction *copyAudio = [UIAction actionWithTitle:RYGLocalized(@"Copy audio URL") image:RYGQualityIcon(@"waveform", 18.0) identifier:nil handler:^(__unused UIAction *action) {
			UIPasteboard.generalPasteboard.string = audioURL.absoluteString;
			RYGNotifySuccess(RYG_NOTIF_COPY_AUDIO_URL, RYGLocalized(@"Copied audio URL"), nil);
		}];

		[items insertObject:copyAudio atIndex:1];
	}

	return [UIMenu menuWithTitle:@"" children:items];
}

- (UIMenu *)menuForAudioRep:(RYGDashRepresentation *)rep {
	NSURL *audioURL = rep.url;
	if (!audioURL) return nil;
	UIAction *copyAudio = [UIAction actionWithTitle:RYGLocalized(@"Copy audio URL") image:RYGQualityIcon(@"waveform", 18.0) identifier:nil handler:^(__unused UIAction *action) {
		UIPasteboard.generalPasteboard.string = audioURL.absoluteString;
		RYGNotifySuccess(RYG_NOTIF_COPY_AUDIO_URL, RYGLocalized(@"Copied audio URL"), nil);
	}];
	return [UIMenu menuWithTitle:@"" children:@[copyAudio]];
}

- (void)playStandardPreview {
	if (!self.standardURL) return;
	[self presentPlayerWithURL:self.standardURL];
}

- (void)playVideoOnlyPreview:(UIButton *)sender {
	NSInteger idx = sender.tag;
	if (idx < 0 || idx >= (NSInteger)self.videoReps.count) return;
	NSURL *url = self.videoReps[idx].url;
	if (url) [self presentPlayerWithURL:url];
}

- (void)playPreview:(UIButton *)sender {
	NSInteger idx = sender.tag;
	if (idx < 0 || idx >= (NSInteger)self.videoReps.count) return;

	[self.loadingVideoRows addIndex:idx];
	NSIndexPath *ip = [NSIndexPath indexPathForRow:idx inSection:1];
	[( _RYGQualityCell *)[self.tableView cellForRowAtIndexPath:ip] setLoading:YES];

	RYGDashRepresentation *videoRep = self.videoReps[idx];
	NSURL *videoURL = videoRep.url;
	NSURL *audioURL = self.audioRep.url;

	if (!videoURL) {
		[self restorePlayButton:idx];
		return;
	}

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *vPath = [RYGTempFiles claimWithExt:@"mp4" ttl:300 tag:@"q_v"].path;
		NSString *aPath = [RYGTempFiles claimWithExt:@"m4a" ttl:300 tag:@"q_a"].path;
		NSString *oPath = [RYGTempFiles claimWithExt:@"mp4" ttl:1800 tag:@"q_o"].path;

		NSData *videoData = [NSData dataWithContentsOfURL:videoURL];
		if (!videoData.length || ![videoData writeToFile:vPath atomically:YES]) {
			RYGRemoveFiles(@[vPath, aPath, oPath]);
			[self restorePlayButton:idx];
			return;
		}

		BOOL hasAudioFile = NO;
		if (audioURL) {
			NSData *audioData = [NSData dataWithContentsOfURL:audioURL];
			hasAudioFile = audioData.length && [audioData writeToFile:aPath atomically:YES];
		}

		NSDictionary *args = [RYGFFmpeg encodingArgsForFallbackPreset:nil];
		NSString *vArgs = args[@"video"];
		NSString *aArgs = args[@"audio"];
		NSString *cArgs = args[@"container"];
		NSString *fArgs = args[@"filter"];
		NSString *cmd = hasAudioFile
			? [NSString stringWithFormat:@"-y -hide_banner -analyzeduration 100M -probesize 100M -fflags +genpts -i '%@' -i '%@' -map 0:v:0 -map 1:a:0 %@ %@ %@ %@ -shortest '%@'", vPath, aPath, fArgs, vArgs, aArgs, cArgs, oPath]
			: [NSString stringWithFormat:@"-y -hide_banner -analyzeduration 100M -probesize 100M -fflags +genpts -i '%@' %@ %@ %@ '%@'", vPath, fArgs, vArgs, cArgs, oPath];

		[RYGFFmpeg executeCommand:cmd completion:^(BOOL success, __unused NSString *output) {
			RYGRemoveFiles(@[vPath, aPath]);

			dispatch_async(dispatch_get_main_queue(), ^{
				if (success && [NSFileManager.defaultManager fileExistsAtPath:oPath])
					[self presentPlayerWithURL:[NSURL fileURLWithPath:oPath]];

				[self restorePlayButton:idx];
			});
		}];
	});
}

- (void)presentPlayerWithURL:(NSURL *)url {
	AVPlayerViewController *playerVC = [AVPlayerViewController new];
	playerVC.player = [AVPlayer playerWithURL:url];
	playerVC.modalPresentationStyle = UIModalPresentationOverFullScreen;

	[self presentViewController:playerVC animated:YES completion:^{
		[playerVC.player play];
	}];
}

- (void)restorePlayButton:(NSInteger)idx {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.loadingVideoRows removeIndex:idx];
		NSIndexPath *ip = [NSIndexPath indexPathForRow:idx inSection:1];
		[( _RYGQualityCell *)[self.tableView cellForRowAtIndexPath:ip] setLoading:NO];
	});
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tableView deselectRowAtIndexPath:ip animated:YES];

	RYGQSectionKind kind = [self kindForSection:ip.section];
	if (kind == RYGQSectionStandard && !self.standardURL) return;

	[self dismissViewControllerAnimated:YES completion:^{
		switch (kind) {
			case RYGQSectionStandard:
				if (self.onPickStandard) self.onPickStandard();
				return;
			case RYGQSectionHD:
				if (ip.row < (NSInteger)self.videoReps.count && self.onPickHD)
					self.onPickHD(self.videoReps[ip.row], self.audioRep);
				return;
			case RYGQSectionVideoOnly:
				if (ip.row < (NSInteger)self.videoReps.count && self.onPickHD)
					self.onPickHD(self.videoReps[ip.row], nil);
				return;
			case RYGQSectionAudio: {
				RYGDashRepresentation *rep = self.advanced && ip.row < (NSInteger)self.allAudioReps.count
					? self.allAudioReps[ip.row] : self.audioRep;
				[RYGMediaActions downloadAudioRepresentation:rep action:self.saveAction];
				return;
			}
			case RYGQSectionPhoto:
				if (self.photoURL)
					[RYGMediaActions downloadPhotoOnlyForMedia:self.mediaRef action:self.saveAction];
				return;
		}
	}];
}
- (NSString *)sizeTextForURL:(NSURL *)url {
	if (!url.absoluteString.length) return @"";

	NSNumber *cached = self.sizeCache[url.absoluteString];
	if (cached) {
		long long bytes = cached.longLongValue;
		return bytes > 0 ? RYGQualityFileSize(bytes) : RYGLocalized(@"Size unknown");
	}

	[self fetchSizeForURL:url];
	return RYGLocalized(@"calculating size…");
}

- (NSString *)combinedSizeTextForVideo:(NSURL *)videoURL audio:(NSURL *)audioURL {
	NSString *videoKey = videoURL.absoluteString;
	NSString *audioKey = audioURL.absoluteString;

	if (!videoKey.length) return @"";

	NSNumber *videoSize = self.sizeCache[videoKey];
	NSNumber *audioSize = audioKey.length ? self.sizeCache[audioKey] : @(0);

	if (!videoSize) [self fetchSizeForURL:videoURL];
	if (audioKey.length && !audioSize) [self fetchSizeForURL:audioURL];

	if (!videoSize || (audioKey.length && !audioSize))
		return RYGLocalized(@"calculating size…");

	long long v = videoSize.longLongValue;
	long long a = audioSize.longLongValue;

	if (v <= 0 || a < 0)
		return RYGLocalized(@"Size unknown");

	return RYGQualityFileSize(v + a);
}

- (void)fetchSizeForURL:(NSURL *)url {
	NSString *key = url.absoluteString;
	if (!key.length || self.sizeCache[key] || [self.sizeLoading containsObject:key]) return;

	[self.sizeLoading addObject:key];

	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
	req.HTTPMethod = @"HEAD";
	req.timeoutInterval = 8.0;
	req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

	NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(__unused NSData *data, NSURLResponse *response, __unused NSError *error) {
		long long bytes = response.expectedContentLength;
		if (bytes <= 0 && [response isKindOfClass:NSHTTPURLResponse.class]) {
			NSString *length = ((NSHTTPURLResponse *)response).allHeaderFields[@"Content-Length"];
			bytes = length.longLongValue;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			self.sizeCache[key] = @(bytes > 0 ? bytes : -1);
			[self.sizeLoading removeObject:key];
			[self.tableView reloadData];
		});
	}];

	[task resume];
}
@end

@implementation RYGQualityPicker

+ (BOOL)pickQualityForMedia:(id)media fromView:(UIView *)sourceView action:(DownloadAction)action picked:(void(^)(RYGDashRepresentation *video, RYGDashRepresentation *audio))picked fallback:(void(^)(void))fallback {
	if (!media || ![RYGUtils getBoolPref:@"enhance_download_quality"] || ![RYGFFmpeg isAvailable]) {
		if (fallback) fallback();
		return NO;
	}

	NSURL *standardURL = [RYGUtils getVideoUrlForMedia:(IGMedia *)media];
	NSString *manifest = [RYGDashParser dashManifestForMedia:media];
	if (!manifest.length) {
		if (fallback) fallback();
		return NO;
	}

	// Some media carry the manifest as a URL, not inline XML — fetch it first.
	if ([manifest hasPrefix:@"http"]) {
		NSURL *manifestURL = [NSURL URLWithString:manifest];
		if (!manifestURL) {
			if (fallback) fallback();
			return NO;
		}

		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:manifestURL];
		req.timeoutInterval = 10.0;
		[[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, __unused NSURLResponse *response, __unused NSError *error) {
			NSString *xml = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
			dispatch_async(dispatch_get_main_queue(), ^{
				[self continueWithManifest:xml standardURL:standardURL media:media fromView:sourceView action:action picked:picked fallback:fallback];
			});
		}] resume];
		return YES;
	}

	return [self continueWithManifest:manifest standardURL:standardURL media:media fromView:sourceView action:action picked:picked fallback:fallback];
}

+ (BOOL)pickQualityWithManifestXML:(NSString *)manifestXML standardURL:(NSURL *)standardURL fromView:(UIView *)sourceView action:(DownloadAction)action picked:(void(^)(RYGDashRepresentation *video, RYGDashRepresentation *audio))picked fallback:(void(^)(void))fallback {
	if (!manifestXML.length || ![RYGUtils getBoolPref:@"enhance_download_quality"] || ![RYGFFmpeg isAvailable]) {
		if (fallback) fallback();
		return NO;
	}
	return [self continueWithManifest:manifestXML standardURL:standardURL media:nil fromView:sourceView action:action picked:picked fallback:fallback];
}

+ (BOOL)continueWithManifest:(NSString *)manifest standardURL:(NSURL *)standardURL media:(id)media fromView:(UIView *)sourceView action:(DownloadAction)action picked:(void(^)(RYGDashRepresentation *video, RYGDashRepresentation *audio))picked fallback:(void(^)(void))fallback {
	NSArray<RYGDashRepresentation *> *allReps = [RYGDashParser parseManifest:manifest];
	NSArray<RYGDashRepresentation *> *videoReps = [RYGDashParser videoRepresentations:allReps];
	NSArray<RYGDashRepresentation *> *audioReps = [RYGDashParser audioRepresentations:allReps];
	RYGDashRepresentation *audioRep = audioReps.firstObject;

	if (!videoReps.count) {
		if (fallback) fallback();
		return NO;
	}

	NSString *qualityPref = [RYGUtils getStringPref:@"default_video_quality"] ?: @"always_ask";

	if ([qualityPref isEqualToString:@"always_ask"]) {
		[self showSheetWithVideoReps:videoReps audioReps:audioReps standardURL:standardURL media:media action:action picked:picked fallback:fallback];
		return YES;
	}

	RYGVideoQuality quality = RYGVideoQualityHighest;
	if ([qualityPref isEqualToString:@"medium"]) quality = RYGVideoQualityMedium;
	else if ([qualityPref isEqualToString:@"low"]) quality = RYGVideoQualityLowest;

	RYGDashRepresentation *videoRep = [RYGDashParser representationForQuality:quality fromRepresentations:allReps];
	if (picked) picked(videoRep, audioRep);
	return YES;
}

+ (void)showSheetWithVideoReps:(NSArray<RYGDashRepresentation *> *)videoReps audioReps:(NSArray<RYGDashRepresentation *> *)audioReps standardURL:(NSURL *)standardURL media:(id)media action:(DownloadAction)action picked:(void(^)(RYGDashRepresentation *video, RYGDashRepresentation *audio))picked fallback:(void(^)(void))fallback {
	dispatch_async(dispatch_get_main_queue(), ^{
		_RYGQualitySheetVC *vc = [_RYGQualitySheetVC new];
		vc.videoReps = videoReps ?: @[];
		vc.allAudioReps = audioReps ?: @[];
		vc.audioRep = audioReps.firstObject;
		vc.standardURL = standardURL;
		vc.mediaRef = media;
		vc.saveAction = action;
		vc.hasAudio = audioReps.firstObject.url != nil;
		vc.photoURL = [RYGUtils getPhotoUrlForMedia:(IGMedia *)media];
		vc.onPickStandard = fallback;
		vc.onPickHD = picked;
		vc.modalPresentationStyle = UIModalPresentationPageSheet;

		UISheetPresentationController *sheet = vc.sheetPresentationController;
		if (sheet) {
			sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
			sheet.prefersGrabberVisible = YES;
			sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
		}

		[topMostController() presentViewController:vc animated:YES completion:nil];
	});
}

@end