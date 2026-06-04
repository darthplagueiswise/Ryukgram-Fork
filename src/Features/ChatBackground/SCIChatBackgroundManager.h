#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Library / default / per-thread changes. Settings UI listens here.
extern NSString *const SCIChatBackgroundDidChangeNotification;

// Slider tweaks. Render hook listens here. Kept separate from the asset-change
// signal so the settings sheet doesn't reload mid-drag.
extern NSString *const SCIChatBackgroundRenderDirtyNotification;

extern NSString *const SCIPrefChatBackgroundEnabled;
extern NSString *const SCIPrefChatBackgroundDefaultAsset;
extern NSString *const SCIPrefChatBackgroundThreadMap;
extern NSString *const SCIPrefChatBackgroundLibrary;
extern NSString *const SCIPrefChatBackgroundPerImage;
extern NSString *const SCIPrefChatBackgroundThreadMeta;

@interface SCIChatBackgroundManager : NSObject

+ (instancetype)shared;

- (BOOL)isEnabled;

// Asset paths are stored relative to Documents/RyukGram/ChatBackgrounds/.
- (NSString *_Nullable)defaultAsset;
- (void)setDefaultAsset:(NSString *_Nullable)relPath;

// Library — ordered list of imported assets (newest last).
- (NSArray<NSString *> *)libraryAssets;
- (void)deleteLibraryAsset:(NSString *)relPath;

// Per-thread assignments (account-scoped via SCIAccountScopedDefaults).
- (NSString *_Nullable)assetForThreadID:(NSString *)threadID;
- (void)setAsset:(NSString *_Nullable)relPath forThreadID:(NSString *)threadID;
- (void)clearAssetForThreadID:(NSString *)threadID;
- (NSDictionary<NSString *, NSString *> *)allThreadAssets;

// Thread metadata captured at apply time. Lets the chats list show usernames
// without re-fetching from IG.
- (NSDictionary *_Nullable)metadataForThreadID:(NSString *)threadID;
- (void)setMetadata:(NSDictionary *_Nullable)meta forThreadID:(NSString *)threadID;

// Resolution: per-thread → default → nil.
- (NSString *_Nullable)resolvedAssetForThreadID:(NSString *_Nullable)threadID;
- (UIImage *_Nullable)resolvedImageForThreadID:(NSString *_Nullable)threadID;

// Resolved image with effective blur + dark-mode dim applied. Cached by
// (asset, blur, dim).
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
- (BOOL)hasCustomSettingsForAsset:(NSString *_Nullable)asset;

// Import a UIImage or file URL — copies into the assets dir, dedup by sha1.
- (NSString *_Nullable)importImage:(UIImage *)image;
- (NSString *_Nullable)importFileURL:(NSURL *)src;

- (NSURL *_Nullable)assetsDirectoryURL;
- (NSURL *_Nullable)urlForRelativeAsset:(NSString *_Nullable)relPath;

- (void)resetAll;

@end

NS_ASSUME_NONNULL_END
