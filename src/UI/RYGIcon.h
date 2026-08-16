#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Icon resolver — accepts friendly keys ("eye"), SF symbol names ("eye.fill"),
// or raw catalog names ("ig_icon_eye_outline_24"). FB assets render template-
// mode so tintColor controls the color.
@interface RYGIcon : NSObject

// Hybrid: FB if mapped, else SF symbol, else bundle PNG.
+ (nullable UIImage *)imageNamed:(NSString *)name;
+ (nullable UIImage *)imageNamed:(NSString *)name pointSize:(CGFloat)pointSize;
+ (nullable UIImage *)imageNamed:(NSString *)name pointSize:(CGFloat)pointSize weight:(UIImageSymbolWeight)weight;
+ (nullable UIImage *)imageNamed:(NSString *)name configuration:(nullable UIImageSymbolConfiguration *)config;

// Menu/action-row glyph: IG assets (ig_icon_/bcn_) are alpha-trimmed so they
// fill a UIMenu icon box like an SF symbol; everything else is an SF symbol.
+ (nullable UIImage *)menuImageNamed:(NSString *)name pointSize:(CGFloat)pointSize;

// YES for names the FB/asset resolver handles (ig_icon_/bcn_ template glyphs
// and colour pet sprites), NO for SF symbol names.
+ (BOOL)isIGAssetName:(NSString *)name;

// YES only for the colour pet sprites — they render in colour, so callers that
// tint or redact must treat them differently from monochrome glyphs.
+ (BOOL)isPetAssetName:(NSString *)name;

// FB-only — nil if no FB asset registered.
+ (nullable UIImage *)fbImageNamed:(NSString *)name;
+ (nullable UIImage *)fbImageNamed:(NSString *)name pointSize:(CGFloat)pointSize;

// SF-only — nil if no SF symbol with that name.
+ (nullable UIImage *)sfImageNamed:(NSString *)name;
+ (nullable UIImage *)sfImageNamed:(NSString *)name pointSize:(CGFloat)pointSize;
+ (nullable UIImage *)sfImageNamed:(NSString *)name pointSize:(CGFloat)pointSize weight:(UIImageSymbolWeight)weight;
+ (nullable UIImage *)sfImageNamed:(NSString *)name configuration:(nullable UIImageSymbolConfiguration *)config;

@end

NS_ASSUME_NONNULL_END
