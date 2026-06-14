#import "SCIQualityPicker.h"
#import "SCIFFmpeg.h"
#import "Utils.h"
#import "InstagramHeaders.h"
#import "ActionButton/SCIMediaActions.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

static NSString * const kSCIQualityCellId = @"SCIQualityCell";

static inline UIImage *SCIQualityIcon(NSString *name, CGFloat size) {
	return [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightMedium]];
}

static inline NSString *SCIQualityBandwidth(NSInteger bandwidth) {
	if (bandwidth <= 0) return @"";
	return bandwidth >= 1000000 ? [NSString stringWithFormat:@"%.1f Mbps", bandwidth / 1000000.0] : [NSString stringWithFormat:@"%ld Kbps", (long)(bandwidth / 1000)];
}

static inline NSString *SCIQualityFileSize(long long bytes) {
	if (bytes <= 0) return @"";
	NSByteCountFormatter *fmt = [NSByteCountFormatter new];
	fmt.countStyle = NSByteCountFormatterCountStyleFile;
	fmt.allowedUnits = bytes >= 1024 * 1024 ? NSByteCountFormatterUseMB : NSByteCountFormatterUseKB;
	return [fmt stringFromByteCount:bytes];
}

static inline NSString *SCIQualityAppendInfo(NSString *info, NSString *extra) {
	if (!extra.length) return info ?: @"";
	if (!info.length) return extra;
	return [NSString stringWithFormat:@"%@ • %@", info, extra];
}

static inline NSString *SCIQualityCodec(NSString *codecs, NSString *fallback) {
	if (!codecs.length) return fallback ?: @"";
	return [codecs componentsSeparatedByString:@"."].firstObject ?: codecs;
}

static inline void SCIRemoveFiles(NSArray<NSString *> *paths) {
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *path in paths) {
		if (path.length) [fm removeItemAtPath:path error:nil];
	}
}

@interface _SCIQualityCell : UITableViewCell
@property (nonatomic, strong) UIButton *iconButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
- (void)setTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(UIImage *)icon menu:(UIMenu *)menu;
- (void)setLoading:(BOOL)loading;
@end

@implementation _SCIQualityCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	self.selectionStyle = UITableViewCellSelectionStyleDefault;
	self.backgroundColor = SCIUIKit26PanelFillColor();

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
	[_menuButton setImage:SCIQualityIcon(@"ellipsis.circle", 18.0) forState:UIControlStateNormal];
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

@interface _SCIQualitySheetVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSArray<SCIDashRepresentation *> *videoReps;
@property (nonatomic, strong) SCIDashRepresentation *audioRep;
@property (nonatomic, strong) NSURL *standardURL;
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, strong) id mediaRef;
@property (nonatomic, assign) DownloadAction saveAction;
@property (nonatomic, assign) BOOL hasAudio;
@property (nonatomic, copy) void (^onPickStandard)(void);
@property (nonatomic, copy) void (^onPickHD)(SCIDashRepresentation *video, SCIDashRepresentation *audio);
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *sizeCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *sizeLoading;
@property (nonatomic, strong) NSMutableIndexSet *loadingVideoRows;
@end

@implementation _SCIQualitySheetVC

- (void)viewDidLoad {
	[super viewDidLoad];
	SCIUIKit26ConfigureViewController(self);
	SCIUIKit26ConfigureTableView(self.tableView);

	self.sizeCache = [NSMutableDictionary dictionary];
	self.sizeLoading = [NSMutableSet set];
	self.loadingVideoRows = [NSMutableIndexSet indexSet];

	self.view.backgroundColor = SCIUIKit26BaseSurfaceColor();

	self.titleLabel = [UILabel new];
	self.titleLabel.text = SCILocalized(@"Download Quality");
	self.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
	self.titleLabel.textColor = UIColor.labelColor;
	self.titleLabel.textAlignment = NSTextAlignmentCenter;
	self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.titleLabel];

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 58.0;
	self.tableView.backgroundColor = UIColor.clearColor;
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.sectionHeaderTopPadding = 8.0;
	[self.tableView registerClass:_SCIQualityCell.class forCellReuseIdentifier:kSCIQualityCellId];
	[self.view addSubview:self.tableView];

	[NSLayoutConstraint activateConstraints:@[
		[self.titleLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24.0],
		[self.titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

		[self.tableView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8.0],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
	]];
}

- (BOOL)hasAudioSection {
	return self.audioRep.url != nil;
}

- (BOOL)hasPhotoSection {
	return self.photoURL != nil;
}

- (BOOL)isAudioSection:(NSInteger)section {
	return section == 2 && self.hasAudioSection;
}

- (BOOL)isPhotoSection:(NSInteger)section {
	return section == 2 + (self.hasAudioSection ? 1 : 0);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2 + (self.hasAudioSection ? 1 : 0) + (self.hasPhotoSection ? 1 : 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 1 ? self.videoReps.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return SCILocalized(@"Standard");
	if (section == 1) return SCILocalized(@"HD");
	if ([self isAudioSection:section]) return SCILocalized(@"Audio");
	return SCILocalized(@"Extras");
}

- (UIImage *)previewIcon {
	return SCIQualityIcon(self.hasAudio ? @"play.fill" : @"play.slash.fill", 18.0);
}

- (NSString *)qualityLabelForRep:(SCIDashRepresentation *)rep {
	if (rep.width > 0 && rep.height > 0) return [NSString stringWithFormat:@"%ldp", (long)MIN(rep.width, rep.height)];
	return rep.qualityLabel.length ? rep.qualityLabel : SCILocalized(@"HD");
}

- (NSString *)subtitleForRep:(SCIDashRepresentation *)rep {
	NSMutableArray *parts = [NSMutableArray array];

	if (rep.width > 0 && rep.height > 0)
		[parts addObject:[NSString stringWithFormat:@"%ld×%ld", (long)rep.width, (long)rep.height]];

	if (rep.frameRate > 0)
		[parts addObject:[NSString stringWithFormat:@"%.0ffps", rep.frameRate]];

	if (rep.codecs.length)
		[parts addObject:SCIQualityCodec(rep.codecs, rep.codecs)];

	if (!self.hasAudio)
		[parts addObject:SCILocalized(@"silent")];

	return [parts componentsJoinedByString:@" • "];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
	_SCIQualityCell *cell = [tableView dequeueReusableCellWithIdentifier:kSCIQualityCellId forIndexPath:ip];
	SCIUIKit26ConfigureTableCell(cell);
	[cell.iconButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];

	if (ip.section == 0) {
		NSString *subtitle = self.hasAudio ? SCILocalized(@"720p • progressive • fastest") : SCILocalized(@"720p • progressive • silent");
		subtitle = SCIQualityAppendInfo(subtitle, [self sizeTextForURL:self.standardURL]);
		[cell setTitle:SCILocalized(@"Standard") subtitle:subtitle icon:self.previewIcon menu:[self menuForStandard]];
		cell.iconButton.hidden = self.standardURL == nil;
		cell.iconButton.tag = -1;
		[cell.iconButton addTarget:self action:@selector(playStandardPreview) forControlEvents:UIControlEventTouchUpInside];
		return cell;
	}

	if (ip.section == 1) {
		SCIDashRepresentation *rep = self.videoReps[ip.row];
		NSString *bandwidth = SCIQualityBandwidth(rep.bandwidth);
		NSString *title = bandwidth.length ? [NSString stringWithFormat:@"%@ • %@", [self qualityLabelForRep:rep], bandwidth] : [self qualityLabelForRep:rep];

		NSString *subtitle = [self subtitleForRep:rep];
		subtitle = SCIQualityAppendInfo(subtitle, [self combinedSizeTextForVideo:rep.url audio:self.audioRep.url]);

		[cell setTitle:title subtitle:subtitle icon:self.previewIcon menu:[self menuForVideoRep:rep]];
		cell.iconButton.tag = ip.row;
		[cell.iconButton addTarget:self action:@selector(playPreview:) forControlEvents:UIControlEventTouchUpInside];
		[cell setLoading:[self.loadingVideoRows containsIndex:ip.row]];
		return cell;
	}

	if ([self isAudioSection:ip.section]) {
		NSMutableArray *parts = [NSMutableArray array];
		NSString *codec = SCIQualityCodec(self.audioRep.codecs, @"m4a");
		NSString *bandwidth = SCIQualityBandwidth(self.audioRep.bandwidth);

		if (codec.length) [parts addObject:codec];
		if (bandwidth.length) [parts addObject:bandwidth];

		NSString *subtitle = parts.count ? [parts componentsJoinedByString:@" • "] : @"m4a";
		subtitle = SCIQualityAppendInfo(subtitle, [self sizeTextForURL:self.audioRep.url]);

		[cell setTitle:SCILocalized(@"Audio only") subtitle:subtitle icon:SCIQualityIcon(@"music.note", 18.0) menu:nil];

		return cell;
	}

	NSString *subtitle = SCIQualityAppendInfo(SCILocalized(@"Raw image"), [self sizeTextForURL:self.photoURL]);
	[cell setTitle:SCILocalized(@"Photo") subtitle:subtitle icon:SCIQualityIcon(@"photo", 18.0) menu:nil];
	return cell;
}

- (UIMenu *)menuForStandard {
	if (!self.standardURL) return nil;

	NSURL *url = self.standardURL;
	UIAction *copy = [UIAction actionWithTitle:SCILocalized(@"Copy video URL") image:SCIQualityIcon(@"video.fill", 18.0) identifier:nil handler:^(__unused UIAction *action) {
		UIPasteboard.generalPasteboard.string = url.absoluteString;
		SCINotifySuccess(SCI_NOTIF_COPY_QUALITY_URL, SCILocalized(@"Copied video URL"), nil);
	}];

	return [UIMenu menuWithTitle:@"" children:@[copy]];
}

- (UIMenu *)menuForVideoRep:(SCIDashRepresentation *)rep {
	NSURL *videoURL = rep.url;
	NSURL *audioURL = self.audioRep.url;

	UIAction *copyVideo = [UIAction actionWithTitle:SCILocalized(@"Copy video URL") image:SCIQualityIcon(@"video.fill", 18.0) identifier:nil handler:^(__unused UIAction *action) {
		if (!videoURL) return;
		UIPasteboard.generalPasteboard.string = videoURL.absoluteString;
		SCINotifySuccess(SCI_NOTIF_COPY_QUALITY_URL, SCILocalized(@"Copied video URL"), nil);
	}];

	UIAction *copyInfo = [UIAction actionWithTitle:SCILocalized(@"Copy quality info") image:SCIQualityIcon(@"info.circle", 18.0) identifier:nil handler:^(__unused UIAction *action) {
		NSString *info = [NSString stringWithFormat:@"%@ — %ld×%ld — %@", [self qualityLabelForRep:rep], (long)rep.width, (long)rep.height, SCIQualityBandwidth(rep.bandwidth)];
		UIPasteboard.generalPasteboard.string = info;
		SCINotifySuccess(SCI_NOTIF_COPY_QUALITY_URL, SCILocalized(@"Copied quality info"), nil);
	}];

	NSMutableArray *items = [NSMutableArray arrayWithObjects:copyVideo, copyInfo, nil];

	if (audioURL) {
		UIAction *copyAudio = [UIAction actionWithTitle:SCILocalized(@"Copy audio URL") image:SCIQualityIcon(@"waveform", 18.0) identifier:nil handler:^(__unused UIAction *action) {
			UIPasteboard.generalPasteboard.string = audioURL.absoluteString;
			SCINotifySuccess(SCI_NOTIF_COPY_AUDIO_URL, SCILocalized(@"Copied audio URL"), nil);
		}];

		[items insertObject:copyAudio atIndex:1];
	}

	return [UIMenu menuWithTitle:@"" children:items];
}

- (void)playStandardPreview {
	if (!self.standardURL) return;
	[self presentPlayerWithURL:self.standardURL];
}

- (void)playPreview:(UIButton *)sender {
	NSInteger idx = sender.tag;
	if (idx < 0 || idx >= (NSInteger)self.videoReps.count) return;

	[self.loadingVideoRows addIndex:idx];
	NSIndexPath *ip = [NSIndexPath indexPathForRow:idx inSection:1];
	[( _SCIQualityCell *)[self.tableView cellForRowAtIndexPath:ip] setLoading:YES];

	SCIDashRepresentation *videoRep = self.videoReps[idx];
	NSURL *videoURL = videoRep.url;
	NSURL *audioURL = self.audioRep.url;

	if (!videoURL) {
		[self restorePlayButton:idx];
		return;
	}

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *vPath = [SCITempFiles claimWithExt:@"mp4" ttl:300 tag:@"q_v"].path;
		NSString *aPath = [SCITempFiles claimWithExt:@"m4a" ttl:300 tag:@"q_a"].path;
		NSString *oPath = [SCITempFiles claimWithExt:@"mp4" ttl:1800 tag:@"q_o"].path;

		NSData *videoData = [NSData dataWithContentsOfURL:videoURL];
		if (!videoData.length || ![videoData writeToFile:vPath atomically:YES]) {
			SCIRemoveFiles(@[vPath, aPath, oPath]);
			[self restorePlayButton:idx];
			return;
		}

		BOOL hasAudioFile = NO;
		if (audioURL) {
			NSData *audioData = [NSData dataWithContentsOfURL:audioURL];
			hasAudioFile = audioData.length && [audioData writeToFile:aPath atomically:YES];
		}

		NSDictionary *args = [SCIFFmpeg encodingArgsForFallbackPreset:nil];
		NSString *vArgs = args[@"video"];
		NSString *aArgs = args[@"audio"];
		NSString *cArgs = args[@"container"];
		NSString *fArgs = args[@"filter"];
		NSString *cmd = hasAudioFile
			? [NSString stringWithFormat:@"-y -hide_banner -analyzeduration 100M -probesize 100M -fflags +genpts -i '%@' -i '%@' -map 0:v:0 -map 1:a:0 %@ %@ %@ %@ -shortest '%@'", vPath, aPath, fArgs, vArgs, aArgs, cArgs, oPath]
			: [NSString stringWithFormat:@"-y -hide_banner -analyzeduration 100M -probesize 100M -fflags +genpts -i '%@' %@ %@ %@ '%@'", vPath, fArgs, vArgs, cArgs, oPath];

		[SCIFFmpeg executeCommand:cmd completion:^(BOOL success, __unused NSString *output) {
			SCIRemoveFiles(@[vPath, aPath]);

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
		[( _SCIQualityCell *)[self.tableView cellForRowAtIndexPath:ip] setLoading:NO];
	});
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tableView deselectRowAtIndexPath:ip animated:YES];

	[self dismissViewControllerAnimated:YES completion:^{
		if (ip.section == 0) {
			if (self.onPickStandard) self.onPickStandard();
			return;
		}

		if (ip.section == 1) {
			if (ip.row < (NSInteger)self.videoReps.count && self.onPickHD)
				self.onPickHD(self.videoReps[ip.row], self.audioRep);
			return;
		}

		if ([self isAudioSection:ip.section])
			[SCIMediaActions downloadAudioOnlyForMedia:self.mediaRef action:self.saveAction];
		else if (self.photoURL)
			[SCIMediaActions downloadPhotoOnlyForMedia:self.mediaRef action:self.saveAction];
	}];
}
- (NSString *)sizeTextForURL:(NSURL *)url {
	if (!url.absoluteString.length) return @"";

	NSNumber *cached = self.sizeCache[url.absoluteString];
	if (cached) {
		long long bytes = cached.longLongValue;
		return bytes > 0 ? SCIQualityFileSize(bytes) : SCILocalized(@"Size unknown");
	}

	[self fetchSizeForURL:url];
	return SCILocalized(@"calculating size…");
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
		return SCILocalized(@"calculating size…");

	long long v = videoSize.longLongValue;
	long long a = audioSize.longLongValue;

	if (v <= 0 || a < 0)
		return SCILocalized(@"Size unknown");

	return SCIQualityFileSize(v + a);
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

@implementation SCIQualityPicker

+ (BOOL)pickQualityForMedia:(id)media fromView:(UIView *)sourceView action:(DownloadAction)action picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked fallback:(void(^)(void))fallback {
	if (!media || ![SCIUtils getBoolPref:@"enhance_download_quality"] || ![SCIFFmpeg isAvailable]) {
		if (fallback) fallback();
		return NO;
	}

	NSURL *standardURL = [SCIUtils getVideoUrlForMedia:(IGMedia *)media];
	if (!standardURL) {
		if (fallback) fallback();
		return NO;
	}

	NSString *manifest = [SCIDashParser dashManifestForMedia:media];
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

+ (BOOL)continueWithManifest:(NSString *)manifest standardURL:(NSURL *)standardURL media:(id)media fromView:(UIView *)sourceView action:(DownloadAction)action picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked fallback:(void(^)(void))fallback {
	NSArray<SCIDashRepresentation *> *allReps = [SCIDashParser parseManifest:manifest];
	NSArray<SCIDashRepresentation *> *videoReps = [SCIDashParser videoRepresentations:allReps];
	SCIDashRepresentation *audioRep = [SCIDashParser bestAudioFromRepresentations:allReps];

	if (!videoReps.count) {
		if (fallback) fallback();
		return NO;
	}

	NSString *qualityPref = [SCIUtils getStringPref:@"default_video_quality"] ?: @"always_ask";

	if ([qualityPref isEqualToString:@"always_ask"]) {
		[self showSheetWithVideoReps:videoReps audioRep:audioRep standardURL:standardURL media:media action:action picked:picked fallback:fallback];
		return YES;
	}

	SCIVideoQuality quality = SCIVideoQualityHighest;
	if ([qualityPref isEqualToString:@"medium"]) quality = SCIVideoQualityMedium;
	else if ([qualityPref isEqualToString:@"low"]) quality = SCIVideoQualityLowest;

	SCIDashRepresentation *videoRep = [SCIDashParser representationForQuality:quality fromRepresentations:allReps];
	if (picked) picked(videoRep, audioRep);
	return YES;
}

+ (void)showSheetWithVideoReps:(NSArray<SCIDashRepresentation *> *)videoReps audioRep:(SCIDashRepresentation *)audioRep standardURL:(NSURL *)standardURL media:(id)media action:(DownloadAction)action picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked fallback:(void(^)(void))fallback {
	dispatch_async(dispatch_get_main_queue(), ^{
		_SCIQualitySheetVC *vc = [_SCIQualitySheetVC new];
		vc.videoReps = videoReps ?: @[];
		vc.audioRep = audioRep;
		vc.standardURL = standardURL;
		vc.mediaRef = media;
		vc.saveAction = action;
		vc.hasAudio = audioRep.url != nil;
		vc.photoURL = [SCIUtils getPhotoUrlForMedia:(IGMedia *)media];
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
