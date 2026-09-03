#import "RYGSettingsSections.h"
#import "../../RYGFFmpeg.h"
#import "../../UI/RYGOptionSheet.h"
#import "../../RYGDefaults.h"

@implementation RYGTweakSettings (Section_Encoding)

// MARK: - Enhanced downloads section

+ (NSDictionary *)enhancedDownloadsSection {
	BOOL ffmpegAvailable = [RYGFFmpeg isAvailable];
	BOOL disabled = !ffmpegAvailable;

	NSString *footer = ffmpegAvailable
		? RYGLocalized(@"Downloads HD video via DASH streams and encodes to H.264. Requires FFmpegKit.")
		: RYGLocalized(@"FFmpegKit is not available. Install the sideloaded IPA or the _ffmpeg .deb variant to enable.");

	RYGSetting *toggle = [RYGSetting switchCellWithTitle:RYGLocalized(@"Enhanced downloads")
											   subtitle:RYGLocalized(@"Download video at the highest available quality")
											defaultsKey:@"enhance_download_quality"];
	toggle.disabled = disabled;

	RYGSetting *videoQuality = [RYGSetting menuCellWithTitle:RYGLocalized(@"Video quality")
												   subtitle:RYGLocalized(@"Which quality to download")
													   menu:[self menus][@"default_video_quality"]];
	videoQuality.disabled = disabled;

	RYGSetting *photoQuality = [RYGSetting menuCellWithTitle:RYGLocalized(@"Photo quality")
												   subtitle:RYGLocalized(@"Use highest resolution available")
													   menu:[self menus][@"default_photo_quality"]];
	photoQuality.disabled = disabled;

	RYGSetting *advToggle = [RYGSetting switchCellWithTitle:RYGLocalized(@"Advanced encoding")
												   subtitle:RYGLocalized(@"Manual ffmpeg controls in place of Encoding speed.")
												defaultsKey:@"adv_encoding_enabled"];
	advToggle.disabled = disabled;

	RYGSetting *swapSlot = [self encodingSpeedOrAdvancedNavCell];
	swapSlot.disabled = disabled;

	return @{
		@"header": RYGLocalized(@"Enhanced downloads"),
		@"footer": footer,
		@"rows": @[toggle, videoQuality, photoQuality, advToggle, swapSlot]
	};
}

// Encoding-speed menu OR Advanced-encoding nav, depending on adv_encoding_enabled.
+ (RYGSetting *)encodingSpeedOrAdvancedNavCell {
	if ([RYGUtils getBoolPref:@"adv_encoding_enabled"]) {
		return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Advanced encoding settings")
										  subtitle:@""
											  icon:nil
									   navSections:[self advancedEncodingNavSections]];
	}
	return [RYGSetting menuCellWithTitle:RYGLocalized(@"Encoding speed")
								subtitle:RYGLocalized(@"Faster = lower quality")
									menu:[self menus][@"ffmpeg_encoding_speed"]];
}

+ (NSArray *)rebuildAdvancedEncodingSlotInSections:(NSArray *)sections {
	// Rebuild the whole section — slot-only matching is fragile across l10n and row reorders.
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *sec in sections) {
		NSArray *rows = sec[@"rows"];
		BOOL containsAdvToggle = NO;
		for (RYGSetting *r in rows) {
			if ([r.defaultsKey isEqualToString:@"adv_encoding_enabled"]) {
				containsAdvToggle = YES;
				break;
			}
		}
		if (containsAdvToggle) {
			[out addObject:[self enhancedDownloadsSection]];
		} else {
			[out addObject:sec];
		}
	}
	return out;
}

+ (NSArray *)advancedEncodingNavSections {
	// Inner panel uses RYGOptionSheet pickers; no per-row subtitles.
	RYGSetting *codec = [self optionCellTitle:RYGLocalized(@"Video codec") key:@"adv_video_codec" options:@[
		@{ @"title": RYGLocalized(@"Hardware (VideoToolbox)"), @"value": @"h264_videotoolbox",
		   @"description": RYGLocalized(@"Fast, fixed-bitrate, GPU-accelerated.") },
		@{ @"title": RYGLocalized(@"Software (libx264)"), @"value": @"libx264",
		   @"description": RYGLocalized(@"Slower, better compression per bit.") },
	]];
	RYGSetting *preset = [self optionCellTitle:RYGLocalized(@"Preset") key:@"adv_preset" options:@[
		@{ @"title": @"ultrafast", @"value": @"ultrafast", @"description": RYGLocalized(@"Fastest, worst compression.") },
		@{ @"title": @"superfast", @"value": @"superfast" },
		@{ @"title": @"veryfast",  @"value": @"veryfast" },
		@{ @"title": @"faster",    @"value": @"faster" },
		@{ @"title": @"fast",      @"value": @"fast" },
		@{ @"title": @"medium",    @"value": @"medium",    @"description": RYGLocalized(@"Balanced. libx264 default.") },
		@{ @"title": @"slow",      @"value": @"slow" },
		@{ @"title": @"slower",    @"value": @"slower" },
		@{ @"title": @"veryslow",  @"value": @"veryslow", @"description": RYGLocalized(@"Best practical quality per bit.") },
		@{ @"title": @"placebo",   @"value": @"placebo",  @"description": RYGLocalized(@"Marginal gain, huge time cost.") },
	]];
	RYGSetting *tune = [self optionCellTitle:RYGLocalized(@"Tune") key:@"adv_tune" options:@[
		@{ @"title": RYGLocalized(@"None"), @"value": @"none", @"description": RYGLocalized(@"No tuning. Default.") },
		@{ @"title": @"film",        @"value": @"film",        @"description": RYGLocalized(@"Live-action video.") },
		@{ @"title": @"animation",   @"value": @"animation",   @"description": RYGLocalized(@"Cartoons / anime.") },
		@{ @"title": @"grain",       @"value": @"grain",       @"description": RYGLocalized(@"Preserve film grain.") },
		@{ @"title": @"stillimage",  @"value": @"stillimage",  @"description": RYGLocalized(@"Slideshow-like content.") },
		@{ @"title": @"fastdecode",  @"value": @"fastdecode",  @"description": RYGLocalized(@"Easier to play back on weak devices.") },
		@{ @"title": @"zerolatency", @"value": @"zerolatency", @"description": RYGLocalized(@"Low-latency streaming.") },
	]];
	RYGSetting *profile = [self optionCellTitle:RYGLocalized(@"H.264 profile") key:@"adv_h264_profile" options:@[
		@{ @"title": @"baseline", @"value": @"baseline", @"description": RYGLocalized(@"Widest compatibility, no B-frames.") },
		@{ @"title": @"main",     @"value": @"main",     @"description": RYGLocalized(@"Standard 8-bit.") },
		@{ @"title": @"high",     @"value": @"high",     @"description": RYGLocalized(@"8-bit. Best for modern devices.") },
		@{ @"title": @"high10",   @"value": @"high10",   @"description": RYGLocalized(@"10-bit colour. Slower, smoother gradients. Software only.") },
		@{ @"title": @"high422",  @"value": @"high422",  @"description": RYGLocalized(@"8-bit 4:2:2 chroma. Niche playback.") },
		@{ @"title": @"high444",  @"value": @"high444",  @"description": RYGLocalized(@"8-bit 4:4:4 full chroma. Niche playback.") },
	]];
	RYGSetting *level = [self optionCellTitle:RYGLocalized(@"H.264 level") key:@"adv_h264_level" options:@[
		@{ @"title": RYGLocalized(@"Auto"), @"value": @"auto", @"description": RYGLocalized(@"Let the encoder pick.") },
		@{ @"title": @"3.0", @"value": @"3.0" },
		@{ @"title": @"3.1", @"value": @"3.1" },
		@{ @"title": @"3.2", @"value": @"3.2" },
		@{ @"title": @"4.0", @"value": @"4.0", @"description": RYGLocalized(@"1080p30 baseline.") },
		@{ @"title": @"4.1", @"value": @"4.1" },
		@{ @"title": @"4.2", @"value": @"4.2" },
		@{ @"title": @"5.0", @"value": @"5.0" },
		@{ @"title": @"5.1", @"value": @"5.1", @"description": RYGLocalized(@"4K30 baseline.") },
		@{ @"title": @"5.2", @"value": @"5.2" },
	]];
	RYGSetting *pixFmt = [self optionCellTitle:RYGLocalized(@"Pixel format") key:@"adv_pixel_format" options:@[
		@{ @"title": @"yuv420p",     @"value": @"yuv420p",     @"description": RYGLocalized(@"8-bit 4:2:0. Universal default.") },
		@{ @"title": @"yuv422p",     @"value": @"yuv422p",     @"description": RYGLocalized(@"8-bit 4:2:2 chroma. Software only.") },
		@{ @"title": @"yuv444p",     @"value": @"yuv444p",     @"description": RYGLocalized(@"8-bit 4:4:4 chroma. Software only.") },
		@{ @"title": @"yuv420p10le", @"value": @"yuv420p10le", @"description": RYGLocalized(@"10-bit 4:2:0. ~2x slower, smoother gradients.") },
	]];

	RYGSetting *crf = [self optionCellTitle:RYGLocalized(@"CRF quality") key:@"adv_crf" options:@[
		@{ @"title": @"0",  @"value": @"0",  @"description": RYGLocalized(@"Lossless. Huge files.") },
		@{ @"title": @"12", @"value": @"12", @"description": RYGLocalized(@"Archival quality.") },
		@{ @"title": @"15", @"value": @"15", @"description": RYGLocalized(@"Very high quality.") },
		@{ @"title": @"17", @"value": @"17" },
		@{ @"title": @"18", @"value": @"18", @"description": RYGLocalized(@"Visually lossless. RyukGram default.") },
		@{ @"title": @"20", @"value": @"20" },
		@{ @"title": @"22", @"value": @"22" },
		@{ @"title": @"23", @"value": @"23", @"description": RYGLocalized(@"Balanced. libx264 default.") },
		@{ @"title": @"26", @"value": @"26" },
		@{ @"title": @"28", @"value": @"28", @"description": RYGLocalized(@"Smaller, visible artefacts.") },
		@{ @"title": @"32", @"value": @"32" },
		@{ @"title": @"35", @"value": @"35" },
		@{ @"title": @"40", @"value": @"40" },
		@{ @"title": @"51", @"value": @"51", @"description": RYGLocalized(@"Worst quality.") },
	]];

	RYGSetting *bitrate = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Video bitrate")
												 subtitle:@""
													 icon:nil
												   action:^{ [self promptAdvVideoBitrate]; }];
	bitrate.dynamicValueText = ^NSString *{ return [RYGTweakSettings advBitrateValueText]; };
	bitrate.defaultsKey = @"adv_video_bitrate"; // button cells ignore defaultsKey; set for the what's-new dot

	RYGSetting *maxRes = [self optionCellTitle:RYGLocalized(@"Max resolution") key:@"adv_max_resolution" options:@[
		@{ @"title": RYGLocalized(@"Original"), @"value": @"original" },
		@{ @"title": @"2160p (4K)", @"value": @"2160" },
		@{ @"title": @"1440p",      @"value": @"1440" },
		@{ @"title": @"1080p",      @"value": @"1080" },
		@{ @"title": @"720p",       @"value": @"720" },
		@{ @"title": @"480p",       @"value": @"480" },
	]];
	RYGSetting *fps = [self optionCellTitle:RYGLocalized(@"Frame rate") key:@"adv_fps" options:@[
		@{ @"title": RYGLocalized(@"Original"), @"value": @"original", @"description": RYGLocalized(@"Keep the source frame rate.") },
		@{ @"title": @"60", @"value": @"60" },
		@{ @"title": @"30", @"value": @"30" },
		@{ @"title": @"24", @"value": @"24", @"description": RYGLocalized(@"Cinematic. Smaller files.") },
	]];

	RYGSetting *audioCodec = [self optionCellTitle:RYGLocalized(@"Audio codec") key:@"adv_audio_codec" options:@[
		@{ @"title": RYGLocalized(@"Copy (passthrough)"), @"value": @"copy",
		   @"description": RYGLocalized(@"Keep original audio. Fast.") },
		@{ @"title": @"AAC", @"value": @"aac",
		   @"description": RYGLocalized(@"Re-encode. Use when source is opus or unsupported.") },
	]];
	RYGSetting *audioBitrate = [self optionCellTitle:RYGLocalized(@"Audio bitrate") key:@"adv_audio_bitrate" options:@[
		@{ @"title": @"64k",  @"value": @"64k" },
		@{ @"title": @"96k",  @"value": @"96k" },
		@{ @"title": @"128k", @"value": @"128k", @"description": RYGLocalized(@"Streaming default.") },
		@{ @"title": @"192k", @"value": @"192k" },
		@{ @"title": @"256k", @"value": @"256k" },
		@{ @"title": @"320k", @"value": @"320k", @"description": RYGLocalized(@"Top of AAC.") },
	]];
	RYGSetting *audioChannels = [self optionCellTitle:RYGLocalized(@"Audio channels") key:@"adv_audio_channels" options:@[
		@{ @"title": RYGLocalized(@"Original"), @"value": @"original" },
		@{ @"title": RYGLocalized(@"Stereo"),   @"value": @"stereo" },
		@{ @"title": RYGLocalized(@"Mono"),     @"value": @"mono" },
	]];
	RYGSetting *audioSampleRate = [self optionCellTitle:RYGLocalized(@"Audio sample rate") key:@"adv_audio_samplerate" options:@[
		@{ @"title": RYGLocalized(@"Original"), @"value": @"original" },
		@{ @"title": @"44.1 kHz", @"value": @"44100" },
		@{ @"title": @"48 kHz",   @"value": @"48000" },
	]];

	RYGSetting *faststart = [RYGSetting switchCellWithTitle:RYGLocalized(@"Faststart")
												   subtitle:@""
												defaultsKey:@"adv_faststart"];

	RYGSetting *stripMetadata = [RYGSetting switchCellWithTitle:RYGLocalized(@"Strip metadata")
													   subtitle:@""
													defaultsKey:@"adv_strip_metadata"];

	RYGSetting *reset = [RYGSetting actionCellWithTitle:RYGLocalized(@"Reset to defaults")
												  color:UIColor.systemRedColor
												 action:^{ [self resetAdvancedEncoding]; }];

	RYGSetting *docs = [RYGSetting linkCellWithTitle:RYGLocalized(@"FFmpeg documentation")
											subtitle:@""
												icon:[RYGSymbol symbolWithName:@"info.circle"]
												 url:@"https://ffmpeg.org/ffmpeg-codecs.html#libx264_002c-libx264rgb"];

	return @[
		@{ @"header": RYGLocalized(@"Codec"),
		   @"footer": RYGLocalized(@"Preset and Tune apply to Software (libx264) only. Pair profile with pixel format: high↔yuv420p, high10↔yuv420p10le, high422↔yuv422p, high444↔yuv444p. Mismatches downconvert silently. Hardware always uses yuv420p."),
		   @"rows": @[codec, preset, tune, profile, level, pixFmt] },
		@{ @"header": RYGLocalized(@"Quality"),
		   @"footer": RYGLocalized(@"Setting a video bitrate switches Software to fixed-bitrate and ignores CRF. Leave empty for CRF. Hardware uses bitrate."),
		   @"rows": @[crf, bitrate, maxRes, fps] },
		@{ @"header": RYGLocalized(@"Audio"),
		   @"footer": RYGLocalized(@"Bitrate, channels, and sample rate apply only when the codec is AAC (re-encoding)."),
		   @"rows": @[audioCodec, audioBitrate, audioChannels, audioSampleRate] },
		@{ @"header": RYGLocalized(@"Container"),
		   @"footer": RYGLocalized(@"Faststart moves the MP4 index to the start so playback begins before the file fully buffers. Strip metadata removes source tags (creation date, handler, encoder) from the file."),
		   @"rows": @[faststart, stripMetadata] },
		@{ @"header": @"",
		   @"rows": @[docs] },
		@{ @"header": @"",
		   @"rows": @[reset] },
	];
}

// Tappable cell opening RYGOptionSheet for a single-select pref. After pick,
// posts RYGSettingsShouldReload — observer path beats hand-chasing the
// visible VC across modal stacks.
+ (RYGSetting *)optionCellTitle:(NSString *)title key:(NSString *)key options:(NSArray<NSDictionary *> *)options {
	RYGSetting *cell = [RYGSetting buttonCellWithTitle:title subtitle:@"" icon:nil action:^{
		[RYGOptionSheet presentFrom:rygTopVC() title:title defaultsKey:key options:options onChange:^(__unused NSString *v) {
			[[NSNotificationCenter defaultCenter] postNotificationName:@"RYGSettingsShouldReload" object:nil];
		}];
	}];
	cell.dynamicValueText = ^NSString *{ return [RYGTweakSettings optionCellValueTextForKey:key options:options]; };
	cell.defaultsKey = key; // button cells ignore defaultsKey; set for the what's-new dot
	return cell;
}

+ (NSString *)optionCellValueTextForKey:(NSString *)key options:(NSArray<NSDictionary *> *)options {
	NSString *cur = [[NSUserDefaults standardUserDefaults] stringForKey:key] ?: @"";
	for (NSDictionary *opt in options) {
		if ([opt[@"value"] isEqualToString:cur]) return opt[@"title"] ?: cur;
	}
	return cur.length ? cur : @"—";
}

+ (NSString *)advBitrateValueText {
	NSString *cur = [[RYGUtils getStringPref:@"adv_video_bitrate"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	return cur.length ? cur : RYGLocalized(@"Auto");
}

+ (void)promptAdvVideoBitrate {
	NSString *current = [RYGUtils getStringPref:@"adv_video_bitrate"];
	UIViewController *presenter = rygTopVC();
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Video bitrate")
																   message:RYGLocalized(@"Examples: 8M, 12M, 25M, 4500k. Leave empty for auto.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = @"8M";
		tf.text = current ?: @"";
		tf.autocorrectionType = UITextAutocorrectionTypeNo;
		tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		NSString *v = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		[[NSUserDefaults standardUserDefaults] setObject:(v ?: @"") forKey:@"adv_video_bitrate"];
		// No row handle here — post the reload signal and let observers re-derive valueText.
		[[NSNotificationCenter defaultCenter] postNotificationName:@"RYGSettingsAdvBitrateChanged" object:nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"RYGSettingsShouldReload" object:nil];
	}]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

+ (void)resetAdvancedEncoding {
	[RYGUtils showConfirmation:^{
		NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
		NSArray *keys = @[
			@"adv_encoding_enabled", @"adv_video_codec", @"adv_preset", @"adv_tune",
			@"adv_h264_profile", @"adv_h264_level", @"adv_crf",
			@"adv_video_bitrate", @"adv_max_resolution", @"adv_fps", @"adv_audio_codec",
			@"adv_audio_bitrate", @"adv_audio_channels", @"adv_audio_samplerate", @"adv_pixel_format",
			@"adv_faststart", @"adv_strip_metadata",
		];
		NSDictionary *defaults = RYGDefaultsDictionary();
		for (NSString *k in keys) {
			id v = defaults[k];
			if (v) [d setObject:v forKey:k];
			else [d removeObjectForKey:k];
		}
		UIViewController *presenter = rygTopVC();
		if ([presenter respondsToSelector:@selector(tableView)]) {
			id tv = [presenter performSelector:@selector(tableView)];
			if ([tv respondsToSelector:@selector(reloadData)]) [tv performSelector:@selector(reloadData)];
		}
	} title:RYGLocalized(@"Reset advanced encoding")];
}

@end
