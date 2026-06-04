// SCIActionIcon — icon source for every RyukGram action button: a shared global
// icon, plus optional per-source overrides.

#import <UIKit/UIKit.h>
#import "../SCIChrome.h"
#import "SCIActionCatalog.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SCIActionIconPrefKey;
extern NSString *const SCIActionIconDefaultName;
extern NSString *const SCIActionIconDidChangeNote;

typedef NS_ENUM(NSInteger, SCIActionIconStyle) {
    SCIActionIconStylePlain = 0,
    // Reels — floats on media, needs baked drop shadow instead of a bubble.
    SCIActionIconStyleShadowBaked,
};

@interface SCIActionIcon : NSObject

// Global icon — the fallback every button uses without a per-source override.
+ (NSString *)symbolName;
+ (void)setSymbolName:(NSString *)name;

+ (NSArray<NSString *> *)availableSystemIcons;

// Per-source overrides; @"" means follow the global icon. Instants is excluded
// from overridableSources — its button is a download arrow, not an icon-family one.
+ (NSArray<NSNumber *> *)overridableSources;
+ (NSString *)effectiveSymbolNameForSource:(SCIActionSource)source;
+ (NSString *)overrideForSource:(SCIActionSource)source;
+ (void)setOverride:(NSString *)name forSource:(SCIActionSource)source;

+ (void)applyToButton:(SCIChromeButton *)button
            pointSize:(CGFloat)pointSize
                style:(SCIActionIconStyle)style;

// Apply now and re-apply on every pref change. Button is held weakly.
+ (void)attachAutoUpdate:(SCIChromeButton *)button
               pointSize:(CGFloat)pointSize
                   style:(SCIActionIconStyle)style;

+ (void)attachAutoUpdate:(SCIChromeButton *)button
                  source:(SCIActionSource)source
               pointSize:(CGFloat)pointSize
                   style:(SCIActionIconStyle)style;

@end

NS_ASSUME_NONNULL_END
