#import "RYGSettingsSections.h"

@implementation RYGTweakSettings (Section_About)

+ (RYGSetting *)aboutNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"About")
										   subtitle:RYGLocalized(@"Version, credits, and links")
											   icon:[RYGSymbol symbolWithIGName:@"info" fallback:@"info.circle"]
										navSections:[self aboutNavSections]];
}


// MARK: - About

+ (RYGSetting *)releaseNotesButtonCell {
	RYGSetting *cell = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Release notes")
											   subtitle:RYGLocalized(@"Browse changes from previous releases")
												   icon:nil
												 action:^{ [RYGChangelog presentAllFromViewController:rygTopVC()]; }];
	cell.titleColor = [UIColor labelColor];
	return cell;
}

+ (RYGSetting *)aboutVersionRowTitle:(NSString *)title value:(NSString *)value icon:(RYGSymbol *)icon {
	RYGSetting *cell = [RYGSetting staticCellWithTitle:title subtitle:@"" icon:icon];
	cell.valueText = value;
	return cell;
}

+ (NSArray *)aboutNavSections {
	return @[
		@{
			@"header": @"",
			@"rows": @[
				[RYGSetting linkCellWithTitle:RYGLocalized(@"Donate to Ryuk") subtitle:RYGLocalized(@"Support RyukGram development") icon:[RYGSymbol symbolWithName:@"heart.fill" color:[UIColor systemPinkColor] size:20.0] url:RYGDonateURL],
			]
		},
		@{
			@"header": RYGLocalized(@"Version"),
			@"rows": @[
				[self aboutVersionRowTitle:@"RyukGram" value:RYGVersionString icon:[RYGSymbol symbolWithName:@"wrench.and.screwdriver.fill" color:[UIColor systemGrayColor] size:14.0]],
				[self aboutVersionRowTitle:@"Instagram" value:[RYGUtils IGVersionString] icon:[RYGSymbol symbolWithIGName:@"instagram" fallback:@"camera.fill" color:[UIColor systemGrayColor] size:14.0]],
				[self aboutVersionRowTitle:RYGLocalized(@"Bundle") value:[[NSBundle mainBundle] bundleIdentifier] icon:[RYGSymbol symbolWithName:@"number" color:[UIColor systemGrayColor] size:14.0]],
			]
		},
		@{
			@"header": RYGLocalized(@"Developers"),
			@"rows": @[
				[RYGSetting linkCellWithTitle:@"Ryuk" subtitle:RYGLocalized(@"RyukGram developer") imageUrl:@"https://github.com/faroukbmiled.png?v=2" url:RYGAuthorURL],
				[RYGSetting linkCellWithTitle:@"Hitori" subtitle:RYGLocalized(@"Code contributions") imageUrl:@"https://github.com/mikasa-san.png" url:@"https://github.com/mikasa-san"],
				[RYGSetting linkCellWithTitle:@"darthplagueiswise (Radan)" subtitle:RYGLocalized(@"Experimental features") imageUrl:@"https://github.com/darthplagueiswise.png" url:@"https://github.com/darthplagueiswise"],
			]
		},
		@{
			@"header": @"",
			@"rows": @[
				[self releaseNotesButtonCell],
				[RYGSetting navigationCellWithTitle:RYGLocalized(@"Credits")
										   subtitle:RYGLocalized(@"Inspirations, contributors, translators")
											   icon:nil
										navSections:[self creditsNavSections]],
			]
		},
		@{
			@"header": RYGLocalized(@"Links"),
			@"rows": @[
				[RYGSetting linkCellWithTitle:RYGLocalized(@"Source code") subtitle:@"" icon:nil url:RYGRepoURL],
				[RYGSetting linkCellWithTitle:RYGLocalized(@"Report an issue") subtitle:@"" icon:nil url:RYGRepoIssuesURL],
				[RYGSetting linkCellWithTitle:RYGLocalized(@"Releases") subtitle:@"" icon:nil url:RYGRepoReleasesURL],
				[RYGSetting linkCellWithTitle:RYGLocalized(@"Telegram channel") subtitle:@"" icon:nil url:RYGTelegramURL],
			]
		},
	];
}

+ (NSArray *)creditsNavSections {
	return @[
		@{
			@"header": RYGLocalized(@"Inspirations"),
			@"rows": @[
				[RYGSetting linkCellWithTitle:@"SoCuul" subtitle:RYGLocalized(@"SCInsta developer") icon:nil url:RYGSoCuulRepoURL],
				[RYGSetting linkCellWithTitle:@"BandarHL" subtitle:RYGLocalized(@"BHInstagram developer") icon:nil url:@"https://github.com/BandarHL"],
				[RYGSetting linkCellWithTitle:@"Instaoled (@VAXMG)" subtitle:RYGLocalized(@"OLED theme inspiration") icon:nil url:@"https://t.me/ciesIPAs"],
			]
		},
		@{
			@"header": RYGLocalized(@"Code and research"),
			@"rows": @[
				[RYGSetting linkCellWithTitle:@"Edoardo (@n3d1117)" subtitle:RYGLocalized(@"Following feed mode (from InstaSane)") icon:nil url:@"https://github.com/n3d1117"],
				[RYGSetting linkCellWithTitle:@"John (@erupts0)" subtitle:RYGLocalized(@"Testing and feature suggestions") icon:nil url:@"https://github.com/erupts0"],
				[RYGSetting linkCellWithTitle:@"efibalogh" subtitle:RYGLocalized(@"Code inspiration") icon:nil url:@"https://github.com/efibalogh"],
				[RYGSetting linkCellWithTitle:@"asdfzxcvbn" subtitle:RYGLocalized(@"Sideload compatibility research (integrated into RyukGram)") icon:nil url:@"https://github.com/asdfzxcvbn/zxPluginsInject"],
			]
		},
		@{
			@"header": RYGLocalized(@"Translators"),
			@"rows": @[
				[RYGSetting linkCellWithTitle:@"ZomkaDEV" subtitle:RYGLocalized(@"Russian translation") icon:nil url:@"https://github.com/ZomkaDEV"],
				[RYGSetting staticCellWithTitle:@"Furamako" subtitle:RYGLocalized(@"Spanish translation") icon:nil],
				[RYGSetting linkCellWithTitle:@"N4C (@ch1tmdgus)" subtitle:RYGLocalized(@"Korean translation") icon:nil url:@"https://github.com/ch1tmdgus"],
				[RYGSetting linkCellWithTitle:@"bruuhim" subtitle:RYGLocalized(@"Arabic translation") icon:nil url:@"https://github.com/bruuhim"],
				[RYGSetting linkCellWithTitle:@"jaydenjcpy" subtitle:RYGLocalized(@"Chinese (Traditional and Simplified) translation") icon:nil url:@"https://github.com/jaydenjcpy"],
				[RYGSetting linkCellWithTitle:@"Bruno (@brunorainha)" subtitle:RYGLocalized(@"Portuguese (Brazil) translation") icon:nil url:@"https://github.com/brunorainha"],
				[RYGSetting linkCellWithTitle:@"yesnt10" subtitle:RYGLocalized(@"Turkish translation") icon:nil url:@"https://github.com/yesnt10"],
				[RYGSetting linkCellWithTitle:@"tranbinh02" subtitle:RYGLocalized(@"Vietnamese translation") icon:nil url:@"https://github.com/tranbinh02"],
				[RYGSetting linkCellWithTitle:@"Yann (@yannouuuu)" subtitle:RYGLocalized(@"French translation") icon:nil url:@"https://github.com/yannouuuu"],
				[RYGSetting linkCellWithTitle:@"willybilly981" subtitle:RYGLocalized(@"Japanese translation") icon:nil url:@"https://github.com/willybilly981"],
			],
			@"footer": RYGLocalized(@"RyukGram is an independent project inspired by SCInsta.")
		},
	];
}

@end
