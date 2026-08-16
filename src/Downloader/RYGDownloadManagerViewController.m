#import "RYGDownloadManagerViewController.h"
#import "RYGDownloadCenter.h"
#import "RYGDownloadThumbs.h"
#import "Download.h"
#import "../Utils.h"
#import "../UI/RYGPopupChrome.h"
#import "../UI/RYGIcon.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#pragma mark - Formatting

static NSString *rygDLBytes(int64_t bytes) {
	return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

static NSString *rygDLRate(double bytesPerSecond) {
	return [NSString stringWithFormat:RYGLocalized(@"%@/s"), rygDLBytes((int64_t)bytesPerSecond)];
}

static NSString *rygDLDuration(NSTimeInterval seconds) {
	if (seconds < 1) return RYGLocalized(@"1s");
	if (seconds < 60) return [NSString stringWithFormat:RYGLocalized(@"%ds"), (int)round(seconds)];
	if (seconds < 3600) return [NSString stringWithFormat:RYGLocalized(@"%dm"), (int)round(seconds / 60.0)];
	return [NSString stringWithFormat:RYGLocalized(@"%dh"), (int)round(seconds / 3600.0)];
}

static NSString *rygDLRelativeTime(NSDate *date) {
	if (!date) return nil;
	static NSRelativeDateTimeFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		fmt = [NSRelativeDateTimeFormatter new];
		fmt.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleShort;
	});
	return [fmt localizedStringForDate:date relativeToDate:[NSDate date]];
}

static BOOL rygDLFileExists(NSURL *url) {
	return url.isFileURL && [NSFileManager.defaultManager fileExistsAtPath:url.path];
}

static int64_t rygDLFileSize(NSURL *url) {
	if (!url.isFileURL) return 0;
	NSNumber *size = nil;
	[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
	return size.longLongValue;
}

static UIColor *rygAccentForState(RYGDownloadJobState s) {
	switch (s) {
		case RYGDownloadJobStateDownloading:
		case RYGDownloadJobStateEncoding:  return [UIColor systemBlueColor];
		case RYGDownloadJobStateQueued:    return [UIColor systemGrayColor];
		case RYGDownloadJobStateWaiting:   return [UIColor systemOrangeColor];
		case RYGDownloadJobStateFinished:  return [UIColor systemGreenColor];
		case RYGDownloadJobStateFailed:    return [UIColor systemRedColor];
		case RYGDownloadJobStateCancelled: return [UIColor systemGrayColor];
	}
	return [UIColor systemGrayColor];
}

static NSString *rygGlyphForJob(RYGDownloadJob *job) {
	switch (job.state) {
		case RYGDownloadJobStateFailed:    return @"exclamationmark.triangle.fill";
		case RYGDownloadJobStateCancelled: return @"slash.circle.fill";
		case RYGDownloadJobStateWaiting:   return @"wifi.exclamationmark";
		case RYGDownloadJobStateQueued:    return @"clock.fill";
		default: break;
	}
	switch (job.mediaKind) {
		case RYGDownloadMediaKindVideo: return @"play.fill";
		case RYGDownloadMediaKindPhoto: return @"photo.fill";
		case RYGDownloadMediaKindAudio: return @"waveform";
		case RYGDownloadMediaKindOther: break;
	}
	return @"arrow.down.doc.fill";
}

static void rygDLHaptic(void) {
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

static NSString *rygJoinMeta(NSArray<NSString *> *parts) {
	NSMutableArray *keep = [NSMutableArray array];
	for (NSString *p in parts) if (p.length) [keep addObject:p];
	return [keep componentsJoinedByString:@" · "];
}

#pragma mark - Progress bar

@interface RYGDownloadBarView : UIView
@property (nonatomic, assign) float progress;
@property (nonatomic, strong) UIView *fill;
- (void)setProgress:(float)progress animated:(BOOL)animated;
@end

@implementation RYGDownloadBarView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;
	self.backgroundColor = [UIColor systemFillColor];
	self.layer.cornerRadius = 2.5;
	self.clipsToBounds = YES;
	_fill = [UIView new];
	_fill.layer.cornerRadius = 2.5;
	[self addSubview:_fill];
	return self;
}

- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 5); }

- (void)layoutSubviews {
	[super layoutSubviews];
	[self layoutFill];
}

- (void)layoutFill {
	CGFloat w = CGRectGetWidth(self.bounds) * MAX(0.0f, MIN(1.0f, _progress));
	self.fill.frame = CGRectMake(0, 0, MAX(w, w > 0 ? 5 : 0), CGRectGetHeight(self.bounds));
}

- (void)setProgress:(float)progress animated:(BOOL)animated {
	BOOL forward = progress >= _progress;
	_progress = progress;
	if (!animated || !forward) { [self layoutFill]; return; }
	[UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
	                 animations:^{ [self layoutFill]; } completion:nil];
}

@end

#pragma mark - Row cell

@interface RYGDownloadRowCell : UICollectionViewListCell
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, copy) void (^onCancel)(void);
- (void)applyJob:(RYGDownloadJob *)job thumb:(UIImage *)thumb editing:(BOOL)editing;
@end

@implementation RYGDownloadRowCell {
	UIView *_tile;
	UIImageView *_thumbView;
	UIImageView *_glyphView;
	UILabel *_titleLabel;
	UILabel *_metaLabel;
	UILabel *_statusLabel;
	RYGDownloadBarView *_bar;
	UILabel *_detailLabel;
	UIStackView *_progressRow;
	UICellAccessoryCustomView *_actionAccessory;
	UICellAccessoryMultiselect *_multiselectAccessory;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	_tile = [UIView new];
	_tile.layer.cornerRadius = 11;
	_tile.layer.cornerCurve = kCACornerCurveContinuous;
	_tile.clipsToBounds = YES;
	_tile.translatesAutoresizingMaskIntoConstraints = NO;

	_thumbView = [UIImageView new];
	_thumbView.contentMode = UIViewContentModeScaleAspectFill;
	_thumbView.clipsToBounds = YES;
	_thumbView.translatesAutoresizingMaskIntoConstraints = NO;
	[_tile addSubview:_thumbView];

	_glyphView = [UIImageView new];
	_glyphView.contentMode = UIViewContentModeScaleAspectFit;
	_glyphView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
	_glyphView.translatesAutoresizingMaskIntoConstraints = NO;
	[_tile addSubview:_glyphView];

	_titleLabel = [UILabel new];
	_titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	_titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

	_metaLabel = [UILabel new];
	_metaLabel.font = [UIFont systemFontOfSize:12.5];
	_metaLabel.textColor = [UIColor secondaryLabelColor];

	_bar = [RYGDownloadBarView new];

	_detailLabel = [UILabel new];
	_detailLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightMedium];
	_detailLabel.textColor = [UIColor tertiaryLabelColor];
	_detailLabel.textAlignment = NSTextAlignmentRight;
	[_detailLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[_detailLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	_progressRow = [[UIStackView alloc] initWithArrangedSubviews:@[_bar, _detailLabel]];
	_progressRow.axis = UILayoutConstraintAxisHorizontal;
	_progressRow.alignment = UIStackViewAlignmentCenter;
	_progressRow.spacing = 8;

	_statusLabel = [UILabel new];
	_statusLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
	_statusLabel.numberOfLines = 2;

	UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _metaLabel, _progressRow, _statusLabel]];
	text.axis = UILayoutConstraintAxisVertical;
	text.spacing = 4;
	text.translatesAutoresizingMaskIntoConstraints = NO;

	[self.contentView addSubview:_tile];
	[self.contentView addSubview:text];

	_actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[_actionButton setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22]
	                              forImageInState:UIControlStateNormal];
	[_actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
	[_actionButton.widthAnchor constraintEqualToConstant:30].active = YES;
	[_actionButton.heightAnchor constraintEqualToConstant:34].active = YES;

	[NSLayoutConstraint activateConstraints:@[
		[_tile.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
		[_tile.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_tile.widthAnchor constraintEqualToConstant:46],
		[_tile.heightAnchor constraintEqualToConstant:46],
		[_tile.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:11],

		[_thumbView.leadingAnchor constraintEqualToAnchor:_tile.leadingAnchor],
		[_thumbView.trailingAnchor constraintEqualToAnchor:_tile.trailingAnchor],
		[_thumbView.topAnchor constraintEqualToAnchor:_tile.topAnchor],
		[_thumbView.bottomAnchor constraintEqualToAnchor:_tile.bottomAnchor],

		[_glyphView.centerXAnchor constraintEqualToAnchor:_tile.centerXAnchor],
		[_glyphView.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],

		[text.leadingAnchor constraintEqualToAnchor:_tile.trailingAnchor constant:12],
		[text.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
		[text.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:11],
		[text.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-11],
	]];
	return self;
}

- (void)actionTapped { if (self.onCancel) self.onCancel(); }

- (void)applyJob:(RYGDownloadJob *)job thumb:(UIImage *)thumb editing:(BOOL)editing {
	UIColor *accent = rygAccentForState(job.state);

	_thumbView.image = thumb;
	_glyphView.hidden = (thumb != nil);
	_glyphView.image = [UIImage systemImageNamed:rygGlyphForJob(job)];
	_glyphView.tintColor = accent;
	_tile.backgroundColor = thumb ? [UIColor blackColor] : [accent colorWithAlphaComponent:0.15];

	_titleLabel.text = job.title;

	BOOL active = job.isActive;
	_metaLabel.text = [self metaTextForJob:job];
	_metaLabel.hidden = (_metaLabel.text.length == 0);

	_progressRow.hidden = !active;
	if (active) {
		_bar.fill.backgroundColor = accent;
		[_bar setProgress:job.progress animated:YES];
		_detailLabel.text = [self detailTextForJob:job];
		_detailLabel.hidden = (_detailLabel.text.length == 0);
	}

	NSString *status = nil;
	if (job.state == RYGDownloadJobStateFailed)
		status = job.error.localizedDescription ?: RYGLocalized(@"Download failed");
	else if (job.state == RYGDownloadJobStateWaiting)
		status = job.stageText ?: RYGLocalized(@"Waiting…");
	_statusLabel.text = status;
	_statusLabel.textColor = accent;
	_statusLabel.hidden = (status.length == 0);

	NSString *symbol = job.isTerminal ? @"ellipsis.circle" : @"xmark.circle.fill";
	[_actionButton setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
	_actionButton.tintColor = job.isTerminal ? [UIColor systemGrayColor] : [UIColor systemGray2Color];
	_actionButton.menu = nil;
	_actionButton.showsMenuAsPrimaryAction = job.isTerminal;

	// UICellAccessoryCustomView rejects a view that already has a superview.
	if (!_actionAccessory)
		_actionAccessory = [[UICellAccessoryCustomView alloc] initWithCustomView:_actionButton
		                                                              placement:UICellAccessoryPlacementTrailing];
	if (!_multiselectAccessory) {
		_multiselectAccessory = [UICellAccessoryMultiselect new];
		// Defaults to WhenEditing; nothing here drives cell editing state.
		_multiselectAccessory.displayedState = UICellAccessoryDisplayedAlways;
	}
	self.accessories = editing ? @[_multiselectAccessory] : @[_actionAccessory];
}

- (NSString *)metaTextForJob:(RYGDownloadJob *)job {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	// The title already carries the kind word when there's no @user byline.
	if (job.subtitle.length && ![job.subtitle isEqualToString:job.title]) [parts addObject:job.subtitle];

	if (job.isActive) {
		if (job.bytesExpected > 0)
			[parts addObject:[NSString stringWithFormat:RYGLocalized(@"%@ of %@"),
			                  rygDLBytes(job.bytesReceived), rygDLBytes(job.bytesExpected)]];
		else if (job.stageText.length)
			[parts addObject:job.stageText];
	} else if (job.state == RYGDownloadJobStateQueued) {
		[parts addObject:RYGLocalized(@"Waiting for a free slot")];
	} else if (job.state == RYGDownloadJobStateFinished) {
		int64_t size = rygDLFileSize(job.resultFileURL) ?: job.bytesExpected;
		if (size > 0) [parts addObject:rygDLBytes(size)];
		if (job.successText.length) [parts addObject:job.successText];
	}

	NSString *when = job.isTerminal ? rygDLRelativeTime(job.finishedAt ?: job.createdAt) : nil;
	if (when) [parts addObject:when];
	return rygJoinMeta(parts);
}

- (NSString *)detailTextForJob:(RYGDownloadJob *)job {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	if (job.bytesPerSecond > 0) [parts addObject:rygDLRate(job.bytesPerSecond)];
	NSTimeInterval eta = job.estimatedSecondsRemaining;
	if (eta > 0) [parts addObject:[NSString stringWithFormat:RYGLocalized(@"%@ left"), rygDLDuration(eta)]];
	if (!parts.count) [parts addObject:[NSString stringWithFormat:@"%d%%", (int)lroundf(job.progress * 100.0f)]];
	return rygJoinMeta(parts);
}

@end

#pragma mark - Filter bar

@interface RYGDownloadFilterBar : UIView
@property (nonatomic, copy) void (^onSelect)(NSString *filterID);
- (void)applyFilters:(NSArray<NSDictionary *> *)filters selected:(NSString *)selected;
@end

static UIFont *rygDLSegmentFont(void) { return [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]; }

@implementation RYGDownloadFilterBar {
	UIScrollView *_scroll;
	UISegmentedControl *_segmented;
	NSArray<NSString *> *_ids;
	NSArray<NSString *> *_titles;
	NSString *_signature;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	_scroll = [UIScrollView new];
	_scroll.showsHorizontalScrollIndicator = NO;
	[self addSubview:_scroll];

	_segmented = [[UISegmentedControl alloc] initWithItems:@[]];
	// A heavier selected title would resize segments and desync the measured widths.
	NSDictionary *attrs = @{ NSFontAttributeName: rygDLSegmentFont() };
	[_segmented setTitleTextAttributes:attrs forState:UIControlStateNormal];
	[_segmented setTitleTextAttributes:attrs forState:UIControlStateSelected];
	[_segmented addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
	[_scroll addSubview:_segmented];
	return self;
}

// Frames, not constraints — pinning to contentLayoutGuide left contentSize
// ambiguous, so the strip clipped instead of scrolling.
- (void)layoutSubviews {
	[super layoutSubviews];

	CGFloat height = CGRectGetHeight(self.bounds);
	CGFloat viewport = CGRectGetWidth(self.bounds);
	_scroll.frame = self.bounds;
	if (viewport <= 0 || !_titles.count) return;

	NSDictionary *attrs = @{ NSFontAttributeName: rygDLSegmentFont() };
	CGFloat needed = 0;
	NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
	for (NSString *title in _titles) {
		CGFloat w = MAX(ceil([title sizeWithAttributes:attrs].width) + 30, 52);
		[widths addObject:@(w)];
		needed += w;
	}
	// Per-title widths; equal widths squeeze long labels and strand short ones.
	for (NSUInteger i = 0; i < widths.count && i < (NSUInteger)_segmented.numberOfSegments; i++)
		[_segmented setWidth:widths[i].doubleValue forSegmentAtIndex:i];

	BOOL fits = (needed <= viewport - 32);
	CGFloat x = fits ? floor((viewport - needed) / 2.0) : 16;
	_segmented.frame = CGRectMake(x, floor((height - 34) / 2.0), needed, 32);
	_scroll.contentSize = CGSizeMake(MAX(viewport, x + needed + 16), height);
}

- (void)segmentChanged {
	NSInteger i = _segmented.selectedSegmentIndex;
	if (i < 0 || i >= (NSInteger)_ids.count) return;
	if (self.onSelect) self.onSelect(_ids[i]);
}

- (NSString *)titleForFilter:(NSDictionary *)filter {
	return [NSString stringWithFormat:@"%@ (%@)", filter[@"title"], filter[@"count"]];
}

// Rebuild only when the buckets change — a count tick retitles in place, so the
// thumb keeps its slide.
- (void)applyFilters:(NSArray<NSDictionary *> *)filters selected:(NSString *)selected {
	NSMutableString *sig = [NSMutableString stringWithString:selected ?: @"all"];
	for (NSDictionary *f in filters) [sig appendFormat:@"|%@:%@", f[@"id"], f[@"count"]];
	if ([sig isEqualToString:_signature]) return;
	_signature = sig;

	NSArray<NSString *> *ids = [filters valueForKey:@"id"];
	NSMutableArray<NSString *> *titles = [NSMutableArray array];
	for (NSDictionary *f in filters) [titles addObject:[self titleForFilter:f]];
	_titles = titles;

	if (![ids isEqualToArray:_ids]) {
		[_segmented removeAllSegments];
		for (NSUInteger i = 0; i < titles.count; i++)
			[_segmented insertSegmentWithTitle:titles[i] atIndex:i animated:NO];
		_ids = ids;
	} else {
		for (NSUInteger i = 0; i < titles.count; i++)
			[_segmented setTitle:titles[i] forSegmentAtIndex:i];
	}
	[self setNeedsLayout];

	NSUInteger index = [ids indexOfObject:selected ?: @"all"];
	// Assigning this doesn't fire valueChanged.
	_segmented.selectedSegmentIndex = (index == NSNotFound) ? 0 : (NSInteger)index;
}

@end

#pragma mark - Empty state

static UIView *rygDLEmptyView(void) {
	UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle"]];
	icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:46 weight:UIImageSymbolWeightLight];
	icon.tintColor = [UIColor tertiaryLabelColor];
	icon.contentMode = UIViewContentModeScaleAspectFit;

	UILabel *title = [UILabel new];
	title.text = RYGLocalized(@"No downloads yet");
	title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
	title.textColor = [UIColor secondaryLabelColor];
	title.textAlignment = NSTextAlignmentCenter;

	UILabel *hint = [UILabel new];
	hint.text = RYGLocalized(@"Media you download shows up here, with its progress and where it was saved.");
	hint.font = [UIFont systemFontOfSize:13];
	hint.textColor = [UIColor tertiaryLabelColor];
	hint.textAlignment = NSTextAlignmentCenter;
	hint.numberOfLines = 0;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, hint]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 10;
	[stack setCustomSpacing:16 afterView:icon];
	stack.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *host = [UIView new];
	[host addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
		[stack.centerYAnchor constraintEqualToAnchor:host.centerYAnchor constant:-30],
		[stack.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:44],
		[stack.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-44],
	]];
	return host;
}

#pragma mark - Settings page (shares prefs with Media saving)

@interface RYGDownloadSettingsViewController : UITableViewController
@end

@implementation RYGDownloadSettingsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Download settings");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	if (s == 1) return 2;
	if (s == 3) return 2;
	return 1;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	if (s == 0) return RYGLocalized(@"Download queue");
	if (s == 1) return RYGLocalized(@"Auto-retry");
	if (s == 2) return RYGLocalized(@"Background");
	return RYGLocalized(@"Download history");
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s == 0) return RYGLocalized(@"Extra downloads wait in line and start as slots free up.");
	if (s == 1) return RYGLocalized(@"Retry automatically when a download drops on a network error");
	if (s == 2) return RYGLocalized(@"Don't pause downloads, encoding, or profile scans when you leave the app");
	return RYGLocalized(@"How long finished, failed and cancelled downloads stay in the manager after you close the app. The files themselves are never touched — only the list.");
}

- (NSArray<NSArray<NSString *> *> *)retentionOptions {
	return @[ @[@"off", RYGLocalized(@"Don't keep")], @[@"12", RYGLocalized(@"12 hours")],
	          @[@"24", RYGLocalized(@"24 hours")], @[@"48", RYGLocalized(@"48 hours")],
	          @[@"168", RYGLocalized(@"7 days")], @[@"720", RYGLocalized(@"30 days")],
	          @[@"forever", RYGLocalized(@"Keep forever")] ];
}

- (NSString *)retentionTitleForValue:(NSString *)value {
	for (NSArray<NSString *> *opt in [self retentionOptions])
		if ([opt.firstObject isEqualToString:value]) return opt.lastObject;
	return RYGLocalized(@"48 hours");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	if (ip.section == 0) {
		cell.textLabel.text = RYGLocalized(@"Max simultaneous downloads");
		[self attachStepperTo:cell key:@"dl_max_concurrent" min:1 max:6];
	} else if (ip.section == 1 && ip.row == 0) {
		cell.textLabel.text = RYGLocalized(@"Auto-retry failed downloads");
		UISwitch *sw = [UISwitch new];
		sw.on = [RYGUtils getBoolPref:@"dl_auto_retry"];
		[sw addTarget:self action:@selector(autoRetryToggled:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
	} else if (ip.section == 1) {
		cell.textLabel.text = RYGLocalized(@"Auto-retry attempts");
		cell.textLabel.enabled = [RYGUtils getBoolPref:@"dl_auto_retry"];
		[self attachStepperTo:cell key:@"dl_auto_retry_count" min:1 max:5];
		((UIStepper *)cell.accessoryView).enabled = [RYGUtils getBoolPref:@"dl_auto_retry"];
	} else if (ip.section == 2) {
		cell.textLabel.text = RYGLocalized(@"Keep running in background");
		UISwitch *sw = [UISwitch new];
		sw.on = [RYGUtils getBoolPref:@"bg_keepalive"];
		[sw addTarget:self action:@selector(keepAliveToggled:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
	} else if (ip.row == 0) {
		cell.textLabel.text = RYGLocalized(@"Keep history for");
		[self attachRetentionMenuTo:cell];
	} else {
		cell.textLabel.text = RYGLocalized(@"Clear download history");
		cell.textLabel.textColor = [UIColor systemRedColor];
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	}
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section == 3 && ip.row == 1) [RYGDownloadManagerViewController presentClearHistoryConfirmation];
}

- (void)attachRetentionMenuTo:(UITableViewCell *)cell {
	NSString *current = [RYGUtils getStringPref:@"dl_history_retention"];
	__weak typeof(self) weakSelf = self;
	NSMutableArray<UIAction *> *actions = [NSMutableArray array];
	for (NSArray<NSString *> *opt in [self retentionOptions]) {
		NSString *value = opt.firstObject;
		UIAction *a = [UIAction actionWithTitle:opt.lastObject image:nil identifier:nil handler:^(__unused id x) {
			[[NSUserDefaults standardUserDefaults] setObject:value forKey:@"dl_history_retention"];
			[weakSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationNone];
			// Takes effect now, not at the next launch.
			if ([value isEqualToString:@"off"]) [[RYGDownloadCenter shared] clearHistory];
		}];
		a.state = [value isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
		[actions addObject:a];
	}

	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	[button setTitle:[self retentionTitleForValue:current] forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont systemFontOfSize:16];
	[button setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
	button.menu = [UIMenu menuWithTitle:@"" children:actions];
	button.showsMenuAsPrimaryAction = YES;
	[button sizeToFit];
	cell.accessoryView = button;
}

- (void)attachStepperTo:(UITableViewCell *)cell key:(NSString *)key min:(double)min max:(double)max {
	double v = [RYGUtils getDoublePref:key];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)v];
	UIStepper *st = [UIStepper new];
	st.minimumValue = min; st.maximumValue = max; st.value = v; st.stepValue = 1;
	objc_setAssociatedObject(st, @selector(attachStepperTo:key:min:max:), key, OBJC_ASSOCIATION_COPY_NONATOMIC);
	[st addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = st;
}

- (void)stepperChanged:(UIStepper *)st {
	NSString *key = objc_getAssociatedObject(st, @selector(attachStepperTo:key:min:max:));
	[[NSUserDefaults standardUserDefaults] setObject:@((int)st.value) forKey:key];
	UITableViewCell *cell = (UITableViewCell *)st.superview;
	while (cell && ![cell isKindOfClass:UITableViewCell.class]) cell = (id)cell.superview;
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)st.value];
}

- (void)autoRetryToggled:(UISwitch *)sw {
	[[NSUserDefaults standardUserDefaults] setObject:@(sw.on) forKey:@"dl_auto_retry"];
	[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)keepAliveToggled:(UISwitch *)sw {
	[[NSUserDefaults standardUserDefaults] setObject:@(sw.on) forKey:@"bg_keepalive"];
}

@end

#pragma mark - Controller

@interface RYGDownloadManagerViewController () <UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UICollectionViewDiffableDataSource<NSString *, NSString *> *dataSource;
@property (nonatomic, strong) NSDictionary<NSString *, RYGDownloadJob *> *jobsByID;
@property (nonatomic, strong) NSArray<NSString *> *lastStructure;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *lastSignatures;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *sectionCounts;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIBarButtonItem *moreItem;
@property (nonatomic, strong) RYGDownloadFilterBar *filterBar;
@property (nonatomic, strong) NSLayoutConstraint *filterBarHeight;
/// Section identifier to show alone; nil = all.
@property (nonatomic, copy, nullable) NSString *filter;
@property (nonatomic, assign) BOOL selecting;
@property (nonatomic, assign) BOOL reloadPending;
@end

@implementation RYGDownloadManagerViewController

+ (void)load {
	[[RYGNotificationCenter shared] setDefaultTapProvider:^{
		return ^{ [RYGDownloadManagerViewController present]; };
	} ownerVCClass:[RYGDownloadManagerViewController class]
	  forAction:RYG_NOTIF_DOWNLOAD];
}

+ (void)present {
	[RYGPopupChrome presentVC:[RYGDownloadManagerViewController new] from:nil];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Downloads");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];

	[self setupCollectionView];
	[self setupDataSource];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(centerChanged)
	                                             name:RYGDownloadCenterDidChangeNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(thumbLoaded:)
	                                             name:RYGDownloadThumbDidLoadNotification object:nil];
	[self applySnapshotAnimated:NO];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

#pragma mark - Layout / data source

// A filtered header would just echo the selected segment.
- (UICollectionViewLayout *)makeLayout {
	__weak typeof(self) weakSelf = self;
	UICollectionLayoutListConfiguration *cfg = [[UICollectionLayoutListConfiguration alloc]
		initWithAppearance:UICollectionLayoutListAppearanceInsetGrouped];
	cfg.headerMode = self.filter ? UICollectionLayoutListHeaderModeNone : UICollectionLayoutListHeaderModeSupplementary;
	cfg.backgroundColor = [UIColor clearColor];
	cfg.leadingSwipeActionsConfigurationProvider = ^UISwipeActionsConfiguration *(NSIndexPath *ip) {
		return [weakSelf leadingSwipeForIndexPath:ip];
	};
	cfg.trailingSwipeActionsConfigurationProvider = ^UISwipeActionsConfiguration *(NSIndexPath *ip) {
		return [weakSelf trailingSwipeForIndexPath:ip];
	};
	return [UICollectionViewCompositionalLayout layoutWithListConfiguration:cfg];
}

- (void)setupCollectionView {
	__weak typeof(self) weakSelf = self;
	self.filterBar = [RYGDownloadFilterBar new];
	self.filterBar.translatesAutoresizingMaskIntoConstraints = NO;
	self.filterBar.onSelect = ^(NSString *filterID) { [weakSelf filterPicked:filterID]; };
	[self.view addSubview:self.filterBar];

	self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:[self makeLayout]];
	self.collectionView.backgroundColor = [UIColor clearColor];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.delegate = self;
	self.collectionView.alwaysBounceVertical = YES;
	[self.view addSubview:self.collectionView];

	self.filterBarHeight = [self.filterBar.heightAnchor constraintEqualToConstant:46];
	[NSLayoutConstraint activateConstraints:@[
		[self.filterBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.filterBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.filterBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		self.filterBarHeight,

		[self.collectionView.topAnchor constraintEqualToAnchor:self.filterBar.bottomAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	self.emptyView = rygDLEmptyView();
	self.collectionView.backgroundView = self.emptyView;
}

#pragma mark - Filters

- (NSArray<NSString *> *)filterOrder {
	return @[@"active", @"waiting", @"queued", @"failed", @"cancelled", @"completed"];
}

// A segment that filters to an empty list is a dead end.
- (NSArray<NSDictionary *> *)availableFilters {
	NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
	NSInteger total = 0;
	for (NSString *secID in [self filterOrder]) total += self.sectionCounts[secID].integerValue;
	if (total == 0) return out;

	[out addObject:@{ @"id": @"all", @"title": RYGLocalized(@"All"), @"count": @(total) }];
	for (NSString *secID in [self filterOrder]) {
		NSInteger count = self.sectionCounts[secID].integerValue;
		if (count > 0) [out addObject:@{ @"id": secID, @"title": [self baseTitleForSection:secID], @"count": @(count) }];
	}
	return out.count > 2 ? out : @[];   // one bucket = nothing to filter between
}

- (void)filterPicked:(NSString *)filterID {
	NSString *next = [filterID isEqualToString:@"all"] ? nil : filterID;
	if ((next == self.filter) || [next isEqualToString:self.filter]) return;

	BOOL headerModeChanged = ((self.filter == nil) != (next == nil));
	self.filter = next;
	rygDLHaptic();
	if (headerModeChanged) [self.collectionView setCollectionViewLayout:[self makeLayout] animated:NO];
	[self reloadAllRows];
	[self applySnapshotAnimated:YES];
}

- (void)refreshFilterBar {
	NSArray<NSDictionary *> *filters = [self availableFilters];
	[self.filterBar applyFilters:filters selected:(self.filter ?: @"all")];

	CGFloat height = filters.count ? 46 : 0;
	if (self.filterBarHeight.constant == height) return;
	self.filterBarHeight.constant = height;
	self.filterBar.hidden = (height == 0);
}

- (void)setupDataSource {
	__weak typeof(self) weakSelf = self;
	UICollectionViewCellRegistration *cellReg = [UICollectionViewCellRegistration registrationWithCellClass:RYGDownloadRowCell.class
		configurationHandler:^(RYGDownloadRowCell *cell, NSIndexPath *ip, NSString *jobID) {
			[weakSelf configureCell:cell forJobID:jobID];
		}];

	self.dataSource = [[UICollectionViewDiffableDataSource alloc] initWithCollectionView:self.collectionView
		cellProvider:^UICollectionViewCell *(UICollectionView *cv, NSIndexPath *ip, NSString *jobID) {
			return [cv dequeueConfiguredReusableCellWithRegistration:cellReg forIndexPath:ip item:jobID];
		}];

	UICollectionViewSupplementaryRegistration *headerReg = [UICollectionViewSupplementaryRegistration
		registrationWithSupplementaryClass:UICollectionViewListCell.class
		                       elementKind:UICollectionElementKindSectionHeader
		              configurationHandler:^(UICollectionViewListCell *header, NSString *kind, NSIndexPath *ip) {
			NSString *sectionID = [weakSelf.dataSource sectionIdentifierForIndex:ip.section];
			UIListContentConfiguration *content = [UIListContentConfiguration groupedHeaderConfiguration];
			content.text = [weakSelf titleForSection:sectionID];
			header.contentConfiguration = content;
		}];
	self.dataSource.supplementaryViewProvider = ^UICollectionReusableView *(UICollectionView *cv, NSString *kind, NSIndexPath *ip) {
		return [cv dequeueConfiguredReusableSupplementaryViewWithRegistration:headerReg forIndexPath:ip];
	};
}

- (void)configureCell:(RYGDownloadRowCell *)cell forJobID:(NSString *)jobID {
	RYGDownloadJob *job = self.jobsByID[jobID];
	if (!job) return;

	__weak typeof(self) weakSelf = self;
	[cell applyJob:job thumb:[RYGDownloadThumbs thumbForJobID:jobID] editing:self.selecting];
	cell.onCancel = ^{ [weakSelf handleRowActionForJob:job]; };
	if (job.isTerminal) cell.actionButton.menu = [self menuForJob:job];
}

- (void)thumbLoaded:(NSNotification *)note {
	[self reconfigureJobID:note.object];
}

- (void)reconfigureJobID:(NSString *)jobID {
	NSDiffableDataSourceSnapshot *snap = self.dataSource.snapshot;
	if (![snap.itemIdentifiers containsObject:jobID]) return;
	[snap reconfigureItemsWithIdentifiers:@[jobID]];
	[self.dataSource applySnapshot:snap animatingDifferences:NO];
}

- (NSString *)baseTitleForSection:(NSString *)sectionID {
	if ([sectionID isEqualToString:@"active"])    return RYGLocalized(@"Active");
	if ([sectionID isEqualToString:@"waiting"])   return RYGLocalized(@"Waiting to retry");
	if ([sectionID isEqualToString:@"queued"])    return RYGLocalized(@"Queued");
	if ([sectionID isEqualToString:@"failed"])    return RYGLocalized(@"Failed");
	if ([sectionID isEqualToString:@"cancelled"]) return RYGLocalized(@"Cancelled");
	if ([sectionID isEqualToString:@"completed"]) return RYGLocalized(@"Completed");
	return @"";
}

- (NSString *)titleForSection:(NSString *)sectionID {
	NSString *base = [self baseTitleForSection:sectionID];
	NSInteger count = self.sectionCounts[sectionID].integerValue;
	return count > 1 ? [NSString stringWithFormat:@"%@ · %ld", base, (long)count] : base;
}

#pragma mark - Snapshot

- (void)centerChanged {
	if (self.reloadPending) return;
	self.reloadPending = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		weakSelf.reloadPending = NO;
		[weakSelf applySnapshotAnimated:YES];
	});
}

// Everything the row draws, so a progress tick only reconfigures what changed.
- (NSString *)signatureForJob:(RYGDownloadJob *)job {
	return [NSString stringWithFormat:@"%ld|%d|%lld|%lld|%d|%@|%@|%@",
	        (long)job.state, (int)lroundf(job.progress * 100.0f), job.bytesReceived, job.bytesExpected,
	        (int)round(job.bytesPerSecond / 1024.0), job.stageText ?: @"", job.successText ?: @"",
	        job.error.localizedDescription ?: @""];
}

- (void)reloadAllRows {
	self.lastStructure = nil;
	self.lastSignatures = nil;
}

- (void)applySnapshotAnimated:(BOOL)animated {
	NSMutableArray<RYGDownloadJob *> *active = [NSMutableArray array];
	NSMutableArray<RYGDownloadJob *> *waiting = [NSMutableArray array];
	NSMutableArray<RYGDownloadJob *> *queued = [NSMutableArray array];
	NSMutableArray<RYGDownloadJob *> *done = [NSMutableArray array];
	NSMutableArray<RYGDownloadJob *> *failed = [NSMutableArray array];
	NSMutableArray<RYGDownloadJob *> *cancelled = [NSMutableArray array];
	NSMutableDictionary<NSString *, RYGDownloadJob *> *map = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSString *> *signatures = [NSMutableDictionary dictionary];

	for (RYGDownloadJob *j in [[RYGDownloadCenter shared] allJobs]) {
		map[j.jobID] = j;
		signatures[j.jobID] = [self signatureForJob:j];
		switch (j.state) {
			case RYGDownloadJobStateDownloading:
			case RYGDownloadJobStateEncoding:  [active addObject:j]; break;
			case RYGDownloadJobStateWaiting:   [waiting addObject:j]; break;
			case RYGDownloadJobStateQueued:    [queued addObject:j]; break;
			case RYGDownloadJobStateFinished:  [done insertObject:j atIndex:0]; break;
			case RYGDownloadJobStateFailed:    [failed insertObject:j atIndex:0]; break;
			case RYGDownloadJobStateCancelled: [cancelled insertObject:j atIndex:0]; break;
		}
	}
	self.jobsByID = map;
	self.emptyView.hidden = (map.count > 0);

	NSDictionary<NSString *, NSArray<RYGDownloadJob *> *> *buckets = @{
		@"active": active, @"waiting": waiting, @"queued": queued,
		@"failed": failed, @"cancelled": cancelled, @"completed": done,
	};
	NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
	for (NSString *secID in buckets) if ([buckets[secID] count]) counts[secID] = @([buckets[secID] count]);
	self.sectionCounts = counts;

	// Counts settle before anything reads the filter; a drained one falls back to All.
	if (self.filter && (!counts[self.filter] || counts.count < 2)) {
		self.filter = nil;
		[self.collectionView setCollectionViewLayout:[self makeLayout] animated:NO];
		[self reloadAllRows];
	}
	[self refreshFilterBar];

	NSDiffableDataSourceSnapshot<NSString *, NSString *> *snap = [NSDiffableDataSourceSnapshot new];
	NSMutableArray<NSString *> *structure = [NSMutableArray array];
	void (^addSec)(NSString *) = ^(NSString *secID) {
		NSArray<RYGDownloadJob *> *jobs = buckets[secID];
		if (!jobs.count) return;
		if (self.filter && ![self.filter isEqualToString:secID]) return;
		[snap appendSectionsWithIdentifiers:@[secID]];
		NSMutableArray<NSString *> *ids = [NSMutableArray array];
		for (RYGDownloadJob *j in jobs) [ids addObject:j.jobID];
		[snap appendItemsWithIdentifiers:ids intoSectionWithIdentifier:secID];
		[structure addObject:secID];
		[structure addObjectsFromArray:ids];
	};
	for (NSString *secID in [self filterOrder]) addSec(secID);

	// A diffable move keeps the cell's old content.
	NSMutableArray<NSString *> *dirty = [NSMutableArray array];
	for (NSString *jobID in snap.itemIdentifiers) {
		NSString *was = self.lastSignatures[jobID];
		if (!was || ![was isEqualToString:signatures[jobID]]) [dirty addObject:jobID];
	}
	if (dirty.count) [snap reconfigureItemsWithIdentifiers:dirty];

	BOOL structureSame = [structure isEqualToArray:self.lastStructure];
	self.lastStructure = structure;
	self.lastSignatures = signatures;

	__weak typeof(self) weakSelf = self;
	[self.dataSource applySnapshot:snap animatingDifferences:(animated && !structureSame) completion:^{
		if (!structureSame) [weakSelf refreshVisibleHeaders];
	}];
	[self updateBars];
}

// A surviving section's header isn't re-dequeued, so its count goes stale.
- (void)refreshVisibleHeaders {
	NSString *kind = UICollectionElementKindSectionHeader;
	for (NSIndexPath *ip in [self.collectionView indexPathsForVisibleSupplementaryElementsOfKind:kind]) {
		UICollectionViewListCell *header = (UICollectionViewListCell *)[self.collectionView supplementaryViewForElementKind:kind atIndexPath:ip];
		if (![header isKindOfClass:UICollectionViewListCell.class]) continue;
		NSString *sectionID = [self.dataSource sectionIdentifierForIndex:ip.section];
		if (!sectionID) continue;
		UIListContentConfiguration *content = [UIListContentConfiguration groupedHeaderConfiguration];
		content.text = [self titleForSection:sectionID];
		header.contentConfiguration = content;
	}
}

#pragma mark - Bars

- (NSArray<NSString *> *)selectedJobIDs {
	NSMutableArray<NSString *> *ids = [NSMutableArray array];
	for (NSIndexPath *ip in self.collectionView.indexPathsForSelectedItems) {
		NSString *jobID = [self.dataSource itemIdentifierForIndexPath:ip];
		if (jobID) [ids addObject:jobID];
	}
	return ids;
}

- (NSArray<RYGDownloadJob *> *)selectedJobs {
	NSMutableArray<RYGDownloadJob *> *jobs = [NSMutableArray array];
	for (NSString *jobID in [self selectedJobIDs]) {
		RYGDownloadJob *j = self.jobsByID[jobID];
		if (j) [jobs addObject:j];
	}
	return jobs;
}

// Only while something runs — idle totals are already on the filter segments.
- (NSString *)summaryText {
	NSInteger activeCount = 0;
	double rate = 0;
	for (RYGDownloadJob *j in self.jobsByID.allValues)
		if (j.isActive) { activeCount++; rate += j.bytesPerSecond; }
	if (activeCount == 0) return nil;

	NSString *head = [NSString stringWithFormat:RYGLocalized(@"%ld downloading"), (long)activeCount];
	return rate > 0 ? rygJoinMeta(@[head, rygDLRate(rate)]) : head;
}

- (NSInteger)completedCount {
	NSInteger n = 0;
	for (RYGDownloadJob *j in self.jobsByID.allValues)
		if (j.state == RYGDownloadJobStateFinished) n++;
	return n;
}

- (void)setTitleText:(NSString *)title subtitle:(NSString *)subtitle {
	if (!self.titleLabel) {
		self.titleLabel = [UILabel new];
		self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
		self.titleLabel.textAlignment = NSTextAlignmentCenter;

		self.subtitleLabel = [UILabel new];
		self.subtitleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
		self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
		self.subtitleLabel.textAlignment = NSTextAlignmentCenter;

		UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.subtitleLabel]];
		stack.axis = UILayoutConstraintAxisVertical;
		stack.alignment = UIStackViewAlignmentCenter;
		stack.spacing = 1;
		self.navigationItem.titleView = stack;
	}
	self.titleLabel.text = title;
	self.subtitleLabel.text = subtitle;
	self.subtitleLabel.hidden = (subtitle.length == 0);
	[self.navigationItem.titleView sizeToFit];
}

// Never reassigned — a progress tick would dismiss the menu mid-open.
- (UIBarButtonItem *)moreItem {
	if (_moreItem) return _moreItem;
	__weak typeof(self) weakSelf = self;
	UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
		completion([weakSelf overflowChildren]);
	}];
	_moreItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
	                                              menu:[UIMenu menuWithTitle:@"" children:@[deferred]]];
	return _moreItem;
}

- (NSArray<UIMenuElement *> *)overflowChildren {
	__weak typeof(self) weakSelf = self;
	NSInteger jobCount = self.jobsByID.count;

	UIAction *select = [UIAction actionWithTitle:RYGLocalized(@"Select") image:[UIImage systemImageNamed:@"checkmark.circle"]
	                                  identifier:nil handler:^(__unused id a) { [weakSelf toggleSelecting]; }];
	select.attributes = jobCount ? 0 : UIMenuElementAttributesDisabled;

	UIAction *clearDone = [UIAction actionWithTitle:RYGLocalized(@"Clear completed") image:[UIImage systemImageNamed:@"checkmark.circle.badge.xmark"]
	                                     identifier:nil handler:^(__unused id a) { [weakSelf clearTapped]; }];
	clearDone.attributes = [self completedCount] ? 0 : UIMenuElementAttributesDisabled;

	UIAction *clearAll = [UIAction actionWithTitle:RYGLocalized(@"Clear all") image:[UIImage systemImageNamed:@"trash"]
	                                    identifier:nil handler:^(__unused id a) { [weakSelf clearAllTapped]; }];
	clearAll.attributes = jobCount ? UIMenuElementAttributesDestructive
	                               : (UIMenuElementAttributesDestructive | UIMenuElementAttributesDisabled);

	UIAction *settings = [UIAction actionWithTitle:RYGLocalized(@"Download settings") image:[UIImage systemImageNamed:@"gearshape"]
	                                    identifier:nil handler:^(__unused id a) { [weakSelf openSettings]; }];

	UIMenu *clearGroup = [UIMenu menuWithTitle:@"" image:nil identifier:nil
	                                   options:UIMenuOptionsDisplayInline children:@[clearDone, clearAll]];
	UIMenu *settingsGroup = [UIMenu menuWithTitle:@"" image:nil identifier:nil
	                                      options:UIMenuOptionsDisplayInline children:@[settings]];
	return @[select, clearGroup, settingsGroup];
}

- (void)updateBars {
	NSInteger jobCount = self.jobsByID.count;
	// Chrome's X owns the leading slot — never touch it.
	if (self.selecting) {
		NSInteger selectedCount = [self selectedJobIDs].count;
		UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Done")
			style:UIBarButtonItemStyleDone target:self action:@selector(toggleSelecting)];
		self.navigationItem.rightBarButtonItems = @[done];
		[self setTitleText:RYGLocalized(@"Downloads")
		          subtitle:[NSString stringWithFormat:RYGLocalized(@"%lu selected"), (unsigned long)selectedCount]];
	} else {
		if (self.navigationItem.rightBarButtonItems.firstObject != [self moreItem])
			self.navigationItem.rightBarButtonItems = @[[self moreItem]];
		[self setTitleText:RYGLocalized(@"Downloads") subtitle:[self summaryText]];
	}

	if (self.selecting) {
		BOOL anyRunning = NO, anyRetryable = NO, anyTerminal = NO;
		for (RYGDownloadJob *j in [self selectedJobs]) {
			if (!j.isTerminal) anyRunning = YES;
			else { anyTerminal = YES; if (j.canRetry) anyRetryable = YES; }
		}
		BOOL allSelected = jobCount > 0 && [self selectedJobIDs].count == (NSUInteger)jobCount;
		UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
		UIBarButtonItem *all = [[UIBarButtonItem alloc]
			initWithTitle:(allSelected ? RYGLocalized(@"Deselect All") : RYGLocalized(@"Select All"))
			style:UIBarButtonItemStylePlain target:self action:@selector(selectAllTapped)];
		UIBarButtonItem *stop = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Stop") style:UIBarButtonItemStylePlain target:self action:@selector(bulkCancel)];
		UIBarButtonItem *retry = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Retry") style:UIBarButtonItemStylePlain target:self action:@selector(bulkRetry)];
		UIBarButtonItem *remove = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Remove") style:UIBarButtonItemStylePlain target:self action:@selector(bulkRemove)];
		remove.tintColor = [UIColor systemRedColor];
		all.enabled = jobCount > 0;
		stop.enabled = anyRunning;
		retry.enabled = anyRetryable;
		remove.enabled = anyTerminal;
		self.toolbarItems = @[all, flex, stop, flex, retry, flex, remove];
	}

	BOOL hideToolbar = !self.selecting;
	if (self.navigationController.isToolbarHidden != hideToolbar)
		[self.navigationController setToolbarHidden:hideToolbar animated:(self.view.window != nil)];
}

- (void)toggleSelecting {
	self.selecting = !self.selecting;
	self.collectionView.allowsMultipleSelection = self.selecting;
	if (!self.selecting) [self deselectAll];
	rygDLHaptic();
	[self reloadAllRows];
	[self applySnapshotAnimated:YES];
}

- (void)deselectAll {
	for (NSIndexPath *ip in [self.collectionView.indexPathsForSelectedItems copy])
		[self.collectionView deselectItemAtIndexPath:ip animated:NO];
}

- (void)selectAllTapped {
	BOOL deselect = ([self selectedJobIDs].count == self.jobsByID.count);
	if (deselect) {
		[self deselectAll];
	} else {
		for (NSInteger s = 0; s < [self.collectionView numberOfSections]; s++) {
			for (NSInteger i = 0; i < [self.collectionView numberOfItemsInSection:s]; i++) {
				[self.collectionView selectItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:s]
				                                  animated:NO scrollPosition:UICollectionViewScrollPositionNone];
			}
		}
	}
	[self updateBars];
}

- (void)clearTapped {
	[[RYGDownloadCenter shared] clearFinished];
	rygDLHaptic();
}

- (void)clearAllTapped { [RYGDownloadManagerViewController presentClearHistoryConfirmation]; }

// Running downloads aren't history — stop them first, or the list can't empty.
+ (void)presentClearHistoryConfirmation {
	UIViewController *top = [RYGPopupChrome topMostController];
	if (!top) return;
	RYGDownloadCenter *center = [RYGDownloadCenter shared];

	NSInteger running = 0;
	for (RYGDownloadJob *j in [center allJobs]) if (!j.isTerminal) running++;
	NSString *message = running > 0
		? [NSString stringWithFormat:RYGLocalized(@"%ld still running — they'll be stopped. The files already saved are kept."), (long)running]
		: RYGLocalized(@"The files already saved are kept — this only empties the list.");

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Clear download history?")
	                                                              message:message
	                                                       preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Clear") style:UIAlertActionStyleDestructive handler:^(__unused id a) {
		for (RYGDownloadJob *j in [center allJobs]) if (!j.isTerminal) [center cancelJob:j];
		[center clearHistory];
		rygDLHaptic();
	}]];
	[top presentViewController:alert animated:YES completion:nil];
}

- (void)openSettings {
	UIViewController *vc = [[RYGDownloadSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
	[self.navigationController pushViewController:vc animated:YES];
}

// Refresh now, not on the throttle — a stale "cancel" tap would become a retry.
- (void)handleRowActionForJob:(RYGDownloadJob *)job {
	if (job.isTerminal) return;
	[[RYGDownloadCenter shared] cancelJob:job];
	rygDLHaptic();
	[self applySnapshotAnimated:YES];
}

- (void)bulkCancel {
	RYGDownloadCenter *c = [RYGDownloadCenter shared];
	for (RYGDownloadJob *j in [self selectedJobs]) if (!j.isTerminal) [c cancelJob:j];
	[self exitSelection];
}
- (void)bulkRetry {
	RYGDownloadCenter *c = [RYGDownloadCenter shared];
	for (RYGDownloadJob *j in [self selectedJobs]) if (j.isTerminal && j.canRetry) [c retryJob:j];
	[self exitSelection];
}
- (void)bulkRemove {
	RYGDownloadCenter *c = [RYGDownloadCenter shared];
	for (RYGDownloadJob *j in [self selectedJobs]) if (j.isTerminal) [c removeJob:j];
	[self exitSelection];
}
- (void)exitSelection {
	rygDLHaptic();
	[self deselectAll];
	self.selecting = NO;
	self.collectionView.allowsMultipleSelection = NO;
	[self reloadAllRows];
	[self applySnapshotAnimated:YES];
}

#pragma mark - Swipe actions

- (RYGDownloadJob *)jobAtIndexPath:(NSIndexPath *)indexPath {
	NSString *jobID = [self.dataSource itemIdentifierForIndexPath:indexPath];
	return jobID ? self.jobsByID[jobID] : nil;
}

- (UISwipeActionsConfiguration *)leadingSwipeForIndexPath:(NSIndexPath *)indexPath {
	if (self.selecting) return nil;
	RYGDownloadJob *job = [self jobAtIndexPath:indexPath];
	if (!job || !job.isTerminal || !job.canRetry) return nil;

	UIContextualAction *retry = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
		title:RYGLocalized(@"Retry") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
			[[RYGDownloadCenter shared] retryJob:job];
			done(YES);
		}];
	retry.image = [UIImage systemImageNamed:@"arrow.clockwise"];
	retry.backgroundColor = [UIColor systemBlueColor];
	return [UISwipeActionsConfiguration configurationWithActions:@[retry]];
}

- (UISwipeActionsConfiguration *)trailingSwipeForIndexPath:(NSIndexPath *)indexPath {
	if (self.selecting) return nil;
	RYGDownloadJob *job = [self jobAtIndexPath:indexPath];
	if (!job) return nil;

	UIContextualAction *action;
	if (job.isTerminal) {
		action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
			title:RYGLocalized(@"Remove") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
				[[RYGDownloadCenter shared] removeJob:job];
				done(YES);
			}];
		action.image = [UIImage systemImageNamed:@"trash"];
	} else {
		action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
			title:RYGLocalized(@"Cancel") handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
				[[RYGDownloadCenter shared] cancelJob:job];
				done(YES);
			}];
		action.image = [UIImage systemImageNamed:@"xmark"];
	}
	UISwipeActionsConfiguration *cfg = [UISwipeActionsConfiguration configurationWithActions:@[action]];
	cfg.performsFirstActionWithFullSwipe = YES;
	return cfg;
}

#pragma mark - Selection / tap

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (self.selecting) { [self updateBars]; return; }

	[collectionView deselectItemAtIndexPath:indexPath animated:YES];
	RYGDownloadJob *job = [self jobAtIndexPath:indexPath];
	if (!job || job.state != RYGDownloadJobStateFinished) return;
	// A reaped scratch file gives QuickLook's blank "Data" sheet.
	if (rygDLFileExists(job.resultFileURL)) [RYGUtils showQuickLookVC:@[job.resultFileURL]];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (self.selecting) [self updateBars];
}

#pragma mark - Context menu (long press)

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView
        contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath
                                             point:(CGPoint)point {
	if (self.selecting) return nil;
	RYGDownloadJob *job = [self jobAtIndexPath:indexPath];
	if (!job) return nil;
	__weak typeof(self) weakSelf = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil
	                                              previewProvider:nil
	                                               actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		return [weakSelf menuForJob:job];
	}];
}

- (UIMenu *)menuForJob:(RYGDownloadJob *)job {
	RYGDownloadCenter *center = [RYGDownloadCenter shared];
	NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];

	if (!job.isTerminal) {
		UIAction *cancel = [UIAction actionWithTitle:RYGLocalized(@"Cancel") image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil handler:^(__unused id a) { [center cancelJob:job]; }];
		cancel.attributes = UIMenuElementAttributesDestructive;
		return [UIMenu menuWithTitle:@"" children:@[cancel]];
	}

	NSURL *file = job.resultFileURL;
	if (rygDLFileExists(file)) {
		[items addObject:[UIAction actionWithTitle:RYGLocalized(@"Preview") image:[UIImage systemImageNamed:@"eye"] identifier:nil handler:^(__unused id a) { [RYGUtils showQuickLookVC:@[file]]; }]];
		[items addObject:[UIAction actionWithTitle:RYGLocalized(@"Share") image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(__unused id a) { [RYGUtils showShareVC:file]; }]];
		[items addObject:[UIAction actionWithTitle:RYGLocalized(@"Save to Photos") image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(__unused id a) { [self saveLocalFile:file action:saveToPhotos]; }]];
		if ([RYGUtils getBoolPref:@"ryg_gallery_enabled"])
			[items addObject:[UIAction actionWithTitle:RYGLocalized(@"Save to Gallery") image:[RYGIcon menuImageNamed:@"ig_icon_photo_gallery_prism_outline_24" pointSize:18] identifier:nil handler:^(__unused id a) { [self saveLocalFile:file action:saveToGallery]; }]];
	}

	if (job.canRetry)
		[items addObject:[UIAction actionWithTitle:RYGLocalized(@"Redownload") image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil handler:^(__unused id a) { [center retryJob:job]; }]];

	UIAction *remove = [UIAction actionWithTitle:RYGLocalized(@"Remove") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__unused id a) { [center removeJob:job]; }];
	remove.attributes = UIMenuElementAttributesDestructive;
	[items addObject:remove];

	return [UIMenu menuWithTitle:@"" children:items];
}

- (void)saveLocalFile:(NSURL *)file action:(DownloadAction)action {
	RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:action showProgress:NO];
	[dl saveLocalFileURL:file hudLabel:nil];
}

@end
