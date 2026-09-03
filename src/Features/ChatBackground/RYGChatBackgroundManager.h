#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Library / default / per-thread changes. Settings UI listens here.
extern NSString *const RYGChatBackgroundDidChangeNotification;

// Slider tweaks; separate from the asset signal so the settings sheet doesn't reload mid-drag.
extern NSString *const RYGChatBackgroundRenderDirtyNotification;

extern NSString *const RYGPrefChatBackgroundEnabled;
extern NSString *const RYGPrefChatBackgroundDefaultAsset;
extern NSString *const RYGPrefChatBackgroundThreadMap;
extern NSString *const RYGPrefChatBackgroundLibrary;
extern NSString *const RYGPrefChatBackgroundPerImage;
extern NSString *const RYGPrefChatBackgroundThreadMeta;

// Which message bubbles auto-color tints. Incoming = the other party (legacy default).
typedef NS_ENUM(NSInteger, RYGBubbleSides) {
	RYGBubbleSidesIncoming = 0,
	RYGBubbleSidesOutgoing = 1,
	RYGBubbleSidesBoth = 2,
};

typedef NS_ENUM(NSInteger, RYGBubbleGradientDirection) {
	RYGBubbleGradientDirectionVertical = 0,
	RYGBubbleGradientDirectionHorizontal = 1,
	RYGBubbleGradientDirectionDiagonal = 2,
};

@interface RYGChatBackgroundManager : NSObject

+ (instancetype)shared;

+ (BOOL)isVideoExtension:(NSString *)ext;
+ (BOOL)isVideoAsset:(NSString *_Nullable)relPath;

- (BOOL)isEnabled;

// Asset paths are stored relative to Documents/RyukGram/ChatBackgrounds/.
- (NSString *_Nullable)defaultAsset;
- (void)setDefaultAsset:(NSString *_Nullable)relPath;

// Library — ordered list of imported assets (newest last).
- (NSArray<NSString *> *)libraryAssets;
- (void)deleteLibraryAsset:(NSString *)relPath;
- (void)replaceAsset:(NSString *)oldRel withAsset:(NSString *)newRel;

// Per-thread assignments (account-scoped via RYGAccountScopedDefaults).
- (NSString *_Nullable)assetForThreadID:(NSString *)threadID;
- (void)setAsset:(NSString *_Nullable)relPath forThreadID:(NSString *)threadID;
- (void)clearAssetForThreadID:(NSString *)threadID;
- (NSDictionary<NSString *, NSString *> *)allThreadAssets;

// Captured at apply time so the chats list needn't refetch from IG.
- (NSDictionary *_Nullable)metadataForThreadID:(NSString *)threadID;
- (void)setMetadata:(NSDictionary *_Nullable)meta forThreadID:(NSString *)threadID;

// Resolution: per-thread → default → nil.
- (NSString *_Nullable)resolvedAssetForThreadID:(NSString *_Nullable)threadID;
- (UIImage *_Nullable)resolvedImageForThreadID:(NSString *_Nullable)threadID;

// Raw asset image — a decoded still, or the first-frame poster for a video asset.
- (UIImage *_Nullable)imageForAsset:(NSString *_Nullable)asset;

// Resolved image with effective blur + dark-mode dim applied.
- (UIImage *_Nullable)processedImageForThreadID:(NSString *_Nullable)threadID darkAppearance:(BOOL)isDark;
- (UIImage *_Nullable)processedImageForAsset:(NSString *)asset darkAppearance:(BOOL)isDark;

// Effective per-image values fall back to defaults (1.0 / 0 / 0) when no override.
- (double)effectiveOpacityForAsset:(NSString *_Nullable)asset;
- (double)effectiveBlurForAsset:(NSString *_Nullable)asset;
- (double)effectiveDimForAsset:(NSString *_Nullable)asset;

- (void)setOpacity:(double)value forAsset:(NSString *)asset;
- (void)setBlur:(double)value forAsset:(NSString *)asset;
- (void)setDim:(double)value forAsset:(NSString *)asset;
- (void)resetSettingsForAsset:(NSString *)asset;

// Tint bubbles for this background's chats; 1 solid or 2 gradient colors, else auto-derived from the image.
- (BOOL)autoBubbleEnabledForAsset:(NSString *_Nullable)asset;
- (void)setAutoBubble:(BOOL)on forAsset:(NSString *)asset;
- (UIColor *_Nullable)autoBubbleColorForAsset:(NSString *_Nullable)asset;
- (NSArray<UIColor *> *)bubbleColorsForAsset:(NSString *_Nullable)asset;
- (UIColor *_Nullable)autoBubbleTextColorForAsset:(NSString *_Nullable)asset;
- (NSArray<UIColor *> *_Nullable)bubbleColorOverrideForAsset:(NSString *_Nullable)asset;
- (void)setBubbleColorOverride:(NSArray<UIColor *> *_Nullable)colors forAsset:(NSString *)asset;
- (BOOL)hasCustomSettingsForAsset:(NSString *_Nullable)asset;

// Which sides get tinted (default: incoming / other party).
- (RYGBubbleSides)bubbleSidesForAsset:(NSString *_Nullable)asset;
- (void)setBubbleSides:(RYGBubbleSides)sides forAsset:(NSString *)asset;

// Gradient = override holds 2 colors. Toggling seeds/collapses the second color.
- (BOOL)bubbleGradientForAsset:(NSString *_Nullable)asset;
- (void)setBubbleGradient:(BOOL)on forAsset:(NSString *)asset;
- (RYGBubbleGradientDirection)bubbleGradientDirectionForAsset:(NSString *_Nullable)asset;
- (void)setBubbleGradientDirection:(RYGBubbleGradientDirection)direction forAsset:(NSString *)asset;

// Manual text color override; nil falls back to auto contrast.
- (UIColor *_Nullable)bubbleTextColorOverrideForAsset:(NSString *_Nullable)asset;
- (void)setBubbleTextColorOverride:(UIColor *_Nullable)color forAsset:(NSString *)asset;

// Import a UIImage or file URL — copies into the assets dir, dedup by sha1.
- (NSString *_Nullable)importImage:(UIImage *)image;
- (NSString *_Nullable)importFileURL:(NSURL *)src;

- (NSURL *_Nullable)assetsDirectoryURL;
- (NSURL *_Nullable)urlForRelativeAsset:(NSString *_Nullable)relPath;

- (void)resetAll;

@end

NS_ASSUME_NONNULL_END
