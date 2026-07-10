#import "SCISettingsSections.h"

@implementation SCITweakSettings (Section_About)

+ (SCISetting *)aboutNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"About")
										   subtitle:SCILocalized(@"Version, credits, and links")
											   icon:[SCISymbol symbolWithIGName:@"info" fallback:@"info.circle"]
										navSections:[self aboutNavSections]];
}


// MARK: - About

+ (SCISetting *)releaseNotesButtonCell {
	SCISetting *cell = [SCISetting buttonCellWithTitle:SCILocalized(@"Release notes")
											   subtitle:SCILocalized(@"Browse changes from previous releases")
												   icon:nil
												 action:^{ [SCIChangelog presentAllFromViewController:sciTopVC()]; }];
	cell.titleColor = [UIColor labelColor];
	return cell;
}

+ (SCISetting *)aboutVersionRowTitle:(NSString *)title value:(NSString *)value icon:(SCISymbol *)icon {
	SCISetting *cell = [SCISetting staticCellWithTitle:title subtitle:@"" icon:icon];
	cell.valueText = value;
	return cell;
}

+ (NSArray *)aboutNavSections {
	return @[
		@{
			@"header": SCILocalized(@"Version"),
			@"rows": @[
				[self aboutVersionRowTitle:@"RyukGram" value:SCIVersionString icon:[SCISymbol symbolWithName:@"wrench.and.screwdriver.fill" color:[UIColor systemGrayColor] size:14.0]],
				[self aboutVersionRowTitle:@"Instagram" value:[SCIUtils IGVersionString] icon:[SCISymbol symbolWithIGName:@"instagram" fallback:@"camera.fill" color:[UIColor systemGrayColor] size:14.0]],
				[self aboutVersionRowTitle:SCILocalized(@"Bundle") value:[[NSBundle mainBundle] bundleIdentifier] icon:[SCISymbol symbolWithName:@"number" color:[UIColor systemGrayColor] size:14.0]],
			]
		},
		@{
			@"header": SCILocalized(@"Developers"),
			@"rows": @[
				[SCISetting linkCellWithTitle:@"Ryuk" subtitle:SCILocalized(@"RyukGram developer") imageUrl:@"https://github.com/faroukbmiled.png?v=2" url:SCIAuthorURL],
				[SCISetting linkCellWithTitle:@"Hitori" subtitle:SCILocalized(@"Code contributions") imageUrl:@"https://github.com/mikasa-san.png" url:@"https://github.com/mikasa-san"],
				[SCISetting linkCellWithTitle:@"darthplagueiswise (Radan)" subtitle:SCILocalized(@"Experimental features") imageUrl:@"https://github.com/darthplagueiswise.png" url:@"https://github.com/darthplagueiswise"],			
			]
		},
		@{
			@"header": @"",
			@"rows": @[
				[self releaseNotesButtonCell],
				[SCISetting navigationCellWithTitle:SCILocalized(@"Credits")
										   subtitle:SCILocalized(@"Inspirations, contributors, translators")
											   icon:nil
										navSections:[self creditsNavSections]],
			]
		},
		@{
			@"header": SCILocalized(@"Links"),
			@"rows": @[
				[SCISetting linkCellWithTitle:SCILocalized(@"Source code") subtitle:@"" icon:nil url:SCIRepoURL],
				[SCISetting linkCellWithTitle:SCILocalized(@"Report an issue") subtitle:@"" icon:nil url:SCIRepoIssuesURL],
				[SCISetting linkCellWithTitle:SCILocalized(@"Releases") subtitle:@"" icon:nil url:SCIRepoReleasesURL],
				[SCISetting linkCellWithTitle:SCILocalized(@"Telegram channel") subtitle:@"" icon:nil url:SCITelegramURL],
			]
		},
		@{
			@"header": @"",
			@"rows": @[
				[SCISetting linkCellWithTitle:SCILocalized(@"Donate to Ryuk") subtitle:SCILocalized(@"Support RyukGram development") icon:[SCISymbol symbolWithName:@"heart.fill" color:[UIColor systemPinkColor] size:20.0] url:SCIDonateURL],
			]
		},
	];
}

+ (NSArray *)creditsNavSections {
	return @[
		@{
			@"header": SCILocalized(@"Inspirations"),
			@"rows": @[
				[SCISetting linkCellWithTitle:@"SoCuul" subtitle:SCILocalized(@"Original SCInsta developer") icon:nil url:SCISoCuulRepoURL],
				[SCISetting linkCellWithTitle:@"BandarHL" subtitle:SCILocalized(@"Original BHInstagram developer") icon:nil url:@"https://github.com/BandarHL"],
				[SCISetting linkCellWithTitle:@"Instaoled (@VAXMG)" subtitle:SCILocalized(@"OLED theme inspiration") icon:nil url:@"https://t.me/ciesIPAs"],
			]
		},
		@{
			@"header": SCILocalized(@"Code and research"),
			@"rows": @[
				[SCISetting linkCellWithTitle:@"Edoardo (@n3d1117)" subtitle:SCILocalized(@"Following feed mode (from InstaSane)") icon:nil url:@"https://github.com/n3d1117"],
				[SCISetting linkCellWithTitle:@"John (@erupts0)" subtitle:SCILocalized(@"Testing and feature suggestions") icon:nil url:@"https://github.com/erupts0"],
				[SCISetting linkCellWithTitle:@"efibalogh" subtitle:SCILocalized(@"Code inspiration") icon:nil url:@"https://github.com/efibalogh"],
				[SCISetting linkCellWithTitle:@"asdfzxcvbn" subtitle:SCILocalized(@"zxPluginsInject sideload compatibility shim") icon:nil url:@"https://github.com/asdfzxcvbn/zxPluginsInject"],
			]
		},
		@{
			@"header": SCILocalized(@"Translators"),
			@"rows": @[
				[SCISetting linkCellWithTitle:@"ZomkaDEV" subtitle:SCILocalized(@"Russian translation") icon:nil url:@"https://github.com/ZomkaDEV"],
				[SCISetting staticCellWithTitle:@"Furamako" subtitle:SCILocalized(@"Spanish translation") icon:nil],
				[SCISetting linkCellWithTitle:@"N4C (@ch1tmdgus)" subtitle:SCILocalized(@"Korean translation") icon:nil url:@"https://github.com/ch1tmdgus"],
				[SCISetting linkCellWithTitle:@"bruuhim" subtitle:SCILocalized(@"Arabic translation") icon:nil url:@"https://github.com/bruuhim"],
				[SCISetting linkCellWithTitle:@"jaydenjcpy" subtitle:SCILocalized(@"Chinese (Traditional and Simplified) translation") icon:nil url:@"https://github.com/jaydenjcpy"],
				[SCISetting linkCellWithTitle:@"Bruno (@brunorainha)" subtitle:SCILocalized(@"Portuguese (Brazil) translation") icon:nil url:@"https://github.com/brunorainha"],
				[SCISetting linkCellWithTitle:@"yesnt10" subtitle:SCILocalized(@"Turkish translation") icon:nil url:@"https://github.com/yesnt10"],
				[SCISetting linkCellWithTitle:@"tranbinh02" subtitle:SCILocalized(@"Vietnamese translation") icon:nil url:@"https://github.com/tranbinh02"],
				[SCISetting linkCellWithTitle:@"Yann (@yannouuuu)" subtitle:SCILocalized(@"French translation") icon:nil url:@"https://github.com/yannouuuu"],
			]
		},
		@{
			@"header": @"",
			@"footer": SCILocalized(@"RyukGram is a heavily reworked fork of SCInsta — supporting the original developer is appreciated."),
			@"rows": @[
				[SCISetting linkCellWithTitle:SCILocalized(@"Donate to SoCuul") subtitle:SCILocalized(@"Support the original SCInsta developer") icon:[SCISymbol symbolWithName:@"heart.fill" color:[UIColor systemPinkColor] size:20.0] url:SCISoCuulDonateURL],
			]
		},
	];
}

@end
