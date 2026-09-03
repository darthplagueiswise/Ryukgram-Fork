// RYGAssetUtils — gallery icon resolver. Friendly names → IG glyph, SF fallback.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGAssetCatalogSource) {
	RYGAssetCatalogSourceAutomatic = 0,
	RYGAssetCatalogSourceFBSharedFramework = 1,
	RYGAssetCatalogSourceMainApp = 2,
};

typedef NS_ENUM(NSInteger, RYGResolvedImageSource) {
	RYGResolvedImageSourceAutomatic = 0,
	RYGResolvedImageSourceInstagramIcon = 1,
	RYGResolvedImageSourceSystemSymbol = 2,
};

@interface RYGAssetUtils : NSObject

// Selection badge: checkmark when selected, hollow ring otherwise.
+ (nullable UIImage *)selectionCheckmarkSelected:(BOOL)selected pointSize:(CGFloat)pointSize;

+ (nullable UIImage *)instagramIconNamed:(NSString *)name;
+ (nullable UIImage *)instagramIconNamed:(NSString *)name pointSize:(CGFloat)pointSize;
+ (nullable UIImage *)instagramIconNamed:(NSString *)name pointSize:(CGFloat)pointSize renderingMode:(UIImageRenderingMode)renderingMode;
+ (nullable UIImage *)instagramIconNamed:(NSString *)name pointSize:(CGFloat)pointSize source:(RYGAssetCatalogSource)source;
+ (nullable UIImage *)instagramIconNamed:(NSString *)name
							   pointSize:(CGFloat)pointSize
								  source:(RYGAssetCatalogSource)source
						   renderingMode:(UIImageRenderingMode)renderingMode;

+ (nullable UIImage *)resolvedImageNamed:(NSString *)name
							   pointSize:(CGFloat)pointSize
								  weight:(UIImageSymbolWeight)weight
								  source:(RYGResolvedImageSource)source
						   renderingMode:(UIImageRenderingMode)renderingMode;

+ (nullable UIImage *)resolvedImageNamed:(nullable NSString *)name
					  fallbackSystemName:(nullable NSString *)fallbackSystemName
							   pointSize:(CGFloat)pointSize
								  weight:(UIImageSymbolWeight)weight
								  source:(RYGResolvedImageSource)source
						   renderingMode:(UIImageRenderingMode)renderingMode;

@end

NS_ASSUME_NONNULL_END
