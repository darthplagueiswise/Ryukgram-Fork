#import "RYGActionIcon.h"
#import "../Utils.h"
#import "../UI/RYGIcon.h"
#import "../Observers/RYGPrefObserver.h"
#import <objc/runtime.h>

// Valid if it renders — FB asset for ig_icon_/bcn_ names, else SF symbol.
static BOOL RYGActionIconRenders(NSString *name) {
	if (!name.length) return NO;
	if ([RYGIcon isIGAssetName:name]) return [RYGIcon fbImageNamed:name] != nil;
	return [UIImage systemImageNamed:name] != nil;
}

NSString *const RYGActionIconPrefKey = @"action_button_icon";
NSString *const RYGActionIconDefaultName = @"ellipsis.circle";
NSString *const RYGActionIconDidChangeNote = @"RYGActionIconDidChange";

static const void *kRYGActionIconConfigKey = &kRYGActionIconConfigKey;

@interface RYGActionIcon ()
+ (NSString *)prefKeyForSource:(RYGActionSource)source;
@end

@interface RYGActionIconConfig : NSObject
@property (nonatomic, assign) CGFloat pointSize;
@property (nonatomic, assign) RYGActionIconStyle style;
@property (nonatomic, assign) RYGActionSource source;  // RYGActionSourceCount == global, no override
@end

@implementation RYGActionIconConfig
@end

@implementation RYGActionIcon

+ (NSHashTable<RYGChromeButton *> *)attached {
	static NSHashTable *table;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ table = NSHashTable.weakObjectsHashTable; });
	return table;
}

+ (void)ensureObserver {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		[RYGPrefObserver observeKey:RYGActionIconPrefKey handler:^{ [self broadcastChange]; }];
		for (NSNumber *src in [self overridableSources]) {
			NSString *key = [self prefKeyForSource:(RYGActionSource)src.integerValue];
			if (key) [RYGPrefObserver observeKey:key handler:^{ [self broadcastChange]; }];
		}
	});
}

+ (void)broadcastChange {
	for (RYGChromeButton *button in self.attached.allObjects) {
		RYGActionIconConfig *config = objc_getAssociatedObject(button, kRYGActionIconConfigKey);
		if (config) [self applyToButton:button source:config.source pointSize:config.pointSize style:config.style];
	}

	[NSNotificationCenter.defaultCenter postNotificationName:RYGActionIconDidChangeNote object:nil];
}

+ (NSString *)symbolName {
	NSString *raw = [RYGUtils getStringPref:RYGActionIconPrefKey];
	return RYGActionIconRenders(raw) ? raw : RYGActionIconDefaultName;
}

+ (void)setSymbolName:(NSString *)name {
	if (!RYGActionIconRenders(name)) return;

	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	NSString *current = [defaults stringForKey:RYGActionIconPrefKey];

	if (![current isEqualToString:name]) {
		[defaults setObject:name forKey:RYGActionIconPrefKey];
	}
}

+ (NSArray<NSNumber *> *)overridableSources {
	// Sources with a chrome trigger we skin — DM Save button rides IG's own button.
	NSMutableArray *out = [NSMutableArray array];
	for (NSInteger s = 0; s < RYGActionSourceCount; s++) {
		if (s == RYGActionSourceDMNativeSave) continue;
		[out addObject:@(s)];
	}
	return out;
}

+ (NSString *)prefKeyForSource:(RYGActionSource)source {
	if (source < 0 || source >= RYGActionSourceCount) return nil;
	return [@"action_button_icon_" stringByAppendingString:[RYGActionCatalog slugForSource:source]];
}

+ (NSString *)overrideForSource:(RYGActionSource)source {
	NSString *key = [self prefKeyForSource:source];
	if (!key) return @"";
	NSString *raw = [RYGUtils getStringPref:key];
	return RYGActionIconRenders(raw) ? raw : @"";
}

+ (NSString *)effectiveSymbolNameForSource:(RYGActionSource)source {
	NSString *override = [self overrideForSource:source];
	return override.length ? override : self.symbolName;
}

+ (void)setOverride:(NSString *)name forSource:(RYGActionSource)source {
	NSString *key = [self prefKeyForSource:source];
	if (!key) return;

	NSString *value = RYGActionIconRenders(name) ? name : @"";
	NSString *current = [NSUserDefaults.standardUserDefaults stringForKey:key] ?: @"";
	if (![current isEqualToString:value]) {
		[NSUserDefaults.standardUserDefaults setObject:value forKey:key];
	}
}

+ (NSArray<NSString *> *)availableSystemIcons {
	// Curated to "more / open menu / take action" reads.
	return @[
		@"ellipsis.circle", @"ellipsis.circle.fill", @"ellipsis", @"ellipsis.rectangle",
		@"circle.grid.2x2", @"circle.grid.2x2.fill", @"circle.grid.3x3", @"square.grid.2x2",
		@"line.3.horizontal", @"line.3.horizontal.circle", @"line.3.horizontal.circle.fill",

		@"plus.circle", @"plus.circle.fill", @"plus.app", @"plus.app.fill",
		@"xmark.circle", @"xmark.circle.fill",

		@"arrow.down.circle", @"arrow.down.circle.fill",
		@"arrow.up.circle", @"arrow.up.circle.fill",
		@"arrow.up.right.circle", @"arrow.up.right.circle.fill",
		@"square.and.arrow.down", @"square.and.arrow.down.fill",
		@"square.and.arrow.up", @"square.and.arrow.up.fill",
		@"arrow.triangle.2.circlepath", @"arrow.triangle.2.circlepath.circle",
		@"arrow.down", @"arrow.down.to.line", @"arrow.down.to.line.compact",
		@"arrow.down.app", @"arrow.down.app.fill",
		@"arrow.down.square", @"arrow.down.square.fill",
		@"tray.and.arrow.down", @"tray.and.arrow.down.fill",
		@"icloud.and.arrow.down", @"icloud.and.arrow.down.fill",

		@"gear", @"gearshape", @"gearshape.fill", @"gearshape.2", @"gearshape.2.fill",
		@"slider.horizontal.3", @"slider.vertical.3",
		@"wrench", @"wrench.fill", @"wrench.and.screwdriver", @"wrench.and.screwdriver.fill",
		@"hammer", @"hammer.fill", @"hammer.circle", @"hammer.circle.fill",
		@"command", @"command.circle", @"command.circle.fill", @"command.square", @"command.square.fill",

		@"sparkle", @"sparkles", @"wand.and.stars", @"wand.and.stars.inverse",
		@"star", @"star.fill", @"star.circle", @"star.circle.fill",
		@"bolt", @"bolt.fill", @"bolt.circle", @"bolt.circle.fill",
		@"flame", @"flame.fill",

		@"heart", @"heart.fill", @"heart.circle", @"heart.circle.fill",
		@"crown", @"crown.fill", @"leaf", @"leaf.fill", @"hare", @"hare.fill",
		@"moon", @"moon.fill", @"sun.max", @"sun.max.fill",
		@"gift", @"gift.fill", @"gift.circle", @"gift.circle.fill"
	];
}

+ (void)clearIconImageState:(RYGChromeButton *)button {
	button.iconView.image = nil;
	button.iconView.layer.shadowOpacity = 0.0;
	button.iconView.layer.shadowRadius = 0.0;
	button.iconView.layer.shadowOffset = CGSizeZero;
	button.iconView.layer.shadowColor = nil;
}

+ (void)applyToButton:(RYGChromeButton *)button pointSize:(CGFloat)pointSize style:(RYGActionIconStyle)style {
	[self applyToButton:button source:RYGActionSourceCount pointSize:pointSize style:style];
}

+ (void)applyToButton:(RYGChromeButton *)button source:(RYGActionSource)source pointSize:(CGFloat)pointSize style:(RYGActionIconStyle)style {
	if (!button) return;

	// ShadowBaked is intentionally treated as plain now.
	// This keeps old callers working without generating baked shadows.
	[self clearIconImageState:button];

	button.symbolPointSize = pointSize;
	button.symbolName = (source < RYGActionSourceCount) ? [self effectiveSymbolNameForSource:source]
													    : self.symbolName;
}

+ (void)attachAutoUpdate:(RYGChromeButton *)button pointSize:(CGFloat)pointSize style:(RYGActionIconStyle)style {
	[self attachAutoUpdate:button source:RYGActionSourceCount pointSize:pointSize style:style];
}

+ (void)attachAutoUpdate:(RYGChromeButton *)button source:(RYGActionSource)source pointSize:(CGFloat)pointSize style:(RYGActionIconStyle)style {
	if (!button) return;

	[self ensureObserver];

	RYGActionIconConfig *config = RYGActionIconConfig.new;
	config.pointSize = pointSize;
	config.style = style;
	config.source = source;

	objc_setAssociatedObject(button, kRYGActionIconConfigKey, config, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[self.attached addObject:button];
	[self applyToButton:button source:source pointSize:pointSize style:style];
}

@end