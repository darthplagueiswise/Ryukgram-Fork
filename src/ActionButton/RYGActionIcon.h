// RYGActionIcon — icon source for every RyukGram action button: a shared global
// icon, plus optional per-source overrides.

#import <UIKit/UIKit.h>
#import "../RYGChrome.h"
#import "RYGActionCatalog.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const RYGActionIconPrefKey;
extern NSString *const RYGActionIconDefaultName;
extern NSString *const RYGActionIconDidChangeNote;

typedef NS_ENUM(NSInteger, RYGActionIconStyle) {
    RYGActionIconStylePlain = 0,
    // Reels — floats on media, needs baked drop shadow instead of a bubble.
    RYGActionIconStyleShadowBaked,
};

@interface RYGActionIcon : NSObject

// Global icon — the fallback every button uses without a per-source override.
+ (NSString *)symbolName;
+ (void)setSymbolName:(NSString *)name;

+ (NSArray<NSString *> *)availableSystemIcons;

// Per-source overrides; @"" means follow the global icon. Instants is excluded
// from overridableSources — its button is a download arrow, not an icon-family one.
+ (NSArray<NSNumber *> *)overridableSources;
+ (NSString *)effectiveSymbolNameForSource:(RYGActionSource)source;
+ (NSString *)overrideForSource:(RYGActionSource)source;
+ (void)setOverride:(NSString *)name forSource:(RYGActionSource)source;

+ (void)applyToButton:(RYGChromeButton *)button
            pointSize:(CGFloat)pointSize
                style:(RYGActionIconStyle)style;

// Apply now and re-apply on every pref change. Button is held weakly.
+ (void)attachAutoUpdate:(RYGChromeButton *)button
               pointSize:(CGFloat)pointSize
                   style:(RYGActionIconStyle)style;

+ (void)attachAutoUpdate:(RYGChromeButton *)button
                  source:(RYGActionSource)source
               pointSize:(CGFloat)pointSize
                   style:(RYGActionIconStyle)style;

@end

NS_ASSUME_NONNULL_END
