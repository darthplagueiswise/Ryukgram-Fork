#import "RYGIcon.h"
#import "../Localization/RYGLocalization.h"

#import <math.h>

// MARK: - Friendly map

// Friendly keys + SF aliases → FB catalog candidates (first hit wins).
static NSDictionary<NSString *, NSArray<NSString *> *> *RYGIconFriendlyMap(void) {
    static NSDictionary *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            // Friendly keys
            @"feed":         @[@"ig_icon_feeds_outline_24"],
            @"feed_filled":  @[@"ig_icon_feeds_filled_24"],
            @"story":        @[@"ig_icon_story_pano_outline_24", @"ig_icon_story_outline_24"],
            @"reels":        @[@"ig_icon_reels_pano_prism_outline_24", @"ig_icon_reels_prism_outline_24", @"ig_icon_reels_outline_24"],
            @"messages":     @[@"ig_icon_direct_prism_outline_24", @"ig_icon_direct_pano_outline_24", @"ig_icon_direct_outline_24"],
            @"profile":      @[@"ig_icon_user_circle_prism_outline_24", @"ig_icon_user_circle_pano_outline_24"],
            @"settings":     @[@"ig_icon_settings_pano_outline_24", @"ig_icon_settings_outline_24"],
            @"settings_filled": @[@"ig_icon_settings_filled_24"],
            @"info":         @[@"ig_icon_info_pano_outline_24", @"ig_icon_info_outline_24"],
            @"check":        @[@"ig_icon_check_outline_24"],
            @"download":     @[@"ig_icon_download_outline_24"],
            @"download_filled": @[@"ig_icon_download_filled_24"],
            @"eye":          @[@"ig_icon_eye_outline_24"],
            @"eye_filled":   @[@"ig_icon_eye_filled_24"],
            @"eye_off":      @[@"ig_icon_eye_off_pano_outline_24"],
            @"eye_off_filled": @[@"ig_icon_eye_off_filled_24"],
            @"green_screen": @[@"ig_icon_green_screen_outline_24"],
            @"moon":         @[@"ig_icon_moon_outline_24"],
            @"instagram":    @[@"bcn_instagram_outline_24"],
            @"layout":       @[@"ig_icon_layout_outline_24"],
            @"location_arrow": @[@"ig_icon_location_arrow_approximate_filled_24", @"ig_icon_location_arrow_filled_24"],
            @"share":        @[@"ig_icon_share_pano_outline_24"],
            @"users":        @[@"ig_icon_users_prism_outline_24"],
            @"heart":        @[@"ig_icon_heart_pano_outline_24", @"ig_icon_heart_outline_24"],
            @"heart_filled": @[@"ig_icon_heart_filled_24"],
            @"home":         @[@"ig_icon_home_pano_prism_outline_24", @"ig_icon_home_prism_outline_24"],
            @"search":       @[@"ig_icon_search_pano_outline_24", @"ig_icon_search_outline_24"],
            @"camera":       @[@"ig_icon_camera_outline_24"],
            @"trash":        @[@"bcn_trash-can_outline_24"],
            @"edit":         @[@"ig_icon_edit_outline_24"],
            @"copy":         @[@"bcn_copy_outline_24"],
            @"link":         @[@"ig_icon_link_outline_24"],
            @"lock":         @[@"ig_icon_lock_filled_24"],
            @"unlock":       @[@"ig_icon_unlock_prism_outline_24", @"ig_icon_unlock_filled_24"],
            @"more":         @[@"ig_icon_more_horizontal_outline_24"],
            @"plus":         @[@"ig_icon_add_pano_outline_24", @"ig_icon_add_outline_24"],
            @"xmark":        @[@"ig_icon_x_pano_outline_24"],
            @"sort":         @[@"ig_icon_sort_pano_outline_24"],
            @"calendar":     @[@"ig_icon_calendar_outline_24"],
            @"toolbox":      @[@"ig_icon_toolbox_outline_24"],
            @"key":          @[@"ig_icon_key_outline_24"],
            @"interface":    @[@"ig_icon_device_phone_pano_outline_24", @"ig_icon_device_phone_prism_outline_24"],
            @"circle_check": @[@"ig_icon_circle_check_outline_24"],
            @"circle_check_filled": @[@"ig_icon_circle_check_pano_filled_24", @"ig_icon_circle_check_filled_24"],
            @"save":         @[@"ig_icon_save_outline_24"],
            @"save_filled":  @[@"ig_icon_save_filled_24"],
            @"scan_nametag": @[@"ig_icon_scan_nametag_pano_outline_24"],
            @"location":     @[@"ig_icon_location_map_outline_24", @"ig_icon_location_outline_24"],
            @"cloud":        @[@"ig_icon_app_icloud_outline_24"],
            @"sliders":      @[@"ig_icon_sliders_pano_outline_24", @"ig_icon_sliders_outline_24"],
            @"insights":     @[@"ig_icon_insights_pano_outline_24", @"ig_icon_insights_outline_24"],
            @"shield":       @[@"ig_icon_shield_pano_outline_24", @"ig_icon_shield_outline_24"],
            @"history":      @[@"ig_icon_history_pano_outline_24", @"ig_icon_history_outline_24"],
            @"globe":        @[@"bcn_globe_outline_24"],
            @"action_button": @[@"ig_icon_app_instants_archive_outline_24"],
            @"hashtag":      @[@"bcn_hashtag_outline_24"],
            @"magnifyingglass": @[@"bcn_magnifying-glass-heavy_outline_24"],
            @"document":     @[@"ig_icon_document_lined_prism_outline_24"],
            @"photo":        @[@"ig_icon_photo_outline_24"],
            @"photo_filled": @[@"ig_icon_photo_filled_24"],
            @"photo_gen_ai": @[@"ig_icon_photo_gen_ai_outline_24"],
            @"photo_gallery": @[@"ig_icon_photo_gallery_outline_24"],
            @"mention":      @[@"ig_icon_story_mention_pano_outline_24"],
            @"arrow_up":     @[@"ig_icon_arrow_up_outline_24"],
            @"arrow_down":   @[@"ig_icon_arrow_down_outline_24"],
            @"arrow_left":   @[@"ig_icon_arrow_left_outline_24"],
            @"arrow_right":  @[@"ig_icon_arrow_right_outline_24"],
            @"arrow_cw":     @[@"ig_icon_arrow_cw_outline_24"],
            @"arrow_ccw":    @[@"ig_icon_arrow_ccw_outline_24"],
            @"expand":       @[@"ig_icon_fit_outline_24"],

            // SF-symbol-name aliases (auto-substitute at unmapped call sites)
            @"gear":         @[@"ig_icon_settings_pano_outline_24", @"ig_icon_settings_outline_24"],
            @"gearshape":    @[@"ig_icon_settings_pano_outline_24", @"ig_icon_settings_outline_24"],
            @"gearshape.fill": @[@"ig_icon_settings_filled_24"],
            @"gearshape.2":  @[@"ig_icon_toolbox_outline_24"],
            @"square.and.arrow.up":   @[@"ig_icon_share_pano_outline_24"],
            @"square.and.arrow.down": @[@"ig_icon_download_outline_24"],
            @"arrow.down.circle":     @[@"ig_icon_download_outline_24"],
            @"arrow.up.circle":       @[@"ig_icon_share_pano_outline_24"],
            @"doc.on.doc":   @[@"bcn_copy_outline_24"],
            // `at` deliberately absent — keeps mention button + action menu on SF.
            @"checkmark":    @[@"ig_icon_check_outline_24"],
            @"checkmark.circle":       @[@"ig_icon_circle_check_outline_24"],
            @"checkmark.circle.fill":  @[@"ig_icon_circle_check_pano_filled_24", @"ig_icon_circle_check_filled_24"],
            @"info.circle":  @[@"ig_icon_info_pano_outline_24", @"ig_icon_info_outline_24"],
            @"lock.fill":    @[@"ig_icon_lock_filled_24"],
            @"lock.open.fill": @[@"ig_icon_unlock_prism_outline_24", @"ig_icon_unlock_filled_24"],
            @"person.crop.circle": @[@"ig_icon_user_circle_prism_outline_24"],
            @"person.circle.fill": @[@"ig_icon_user_circle_prism_filled_24", @"ig_icon_user_circle_filled_24"],
            @"arrow.counterclockwise":        @[@"ig_icon_arrow_ccw_outline_24"],
            @"arrow.counterclockwise.circle": @[@"ig_icon_history_pano_outline_24", @"ig_icon_history_outline_24"],
            @"arrow.clockwise":               @[@"ig_icon_arrow_cw_outline_24"],
            @"arrow.clockwise.circle.fill":   @[@"ig_icon_history_pano_outline_24", @"ig_icon_history_outline_24"],
            @"clock.arrow.circlepath":        @[@"ig_icon_history_pano_outline_24", @"ig_icon_history_outline_24"],
            @"archivebox":   @[@"ig_icon_document_lined_prism_outline_24"],
            @"arrow.up.arrow.down": @[@"ig_icon_sort_pano_outline_24"],
            @"arrow.up":     @[@"ig_icon_arrow_up_outline_24"],
            @"arrow.down":   @[@"ig_icon_arrow_down_outline_24"],
            @"trash.fill":   @[@"bcn_trash-can_outline_24"],
            @"number":       @[@"bcn_hashtag_outline_24"],
            @"photo.on.rectangle.angled": @[@"ig_icon_photo_gallery_outline_24"],
            @"photo.badge.checkmark":      @[@"ig_icon_photo_gen_ai_outline_24"],
            @"photo.badge.checkmark.fill": @[@"ig_icon_photo_gen_ai_outline_24"],
            @"heart.fill":   @[@"ig_icon_heart_filled_24"],
            @"hand.draw.fill": @[@"ig_icon_layout_outline_24"],
            @"rectangle.stack": @[@"ig_icon_feeds_outline_24"],
            @"film.stack":   @[@"ig_icon_reels_pano_prism_outline_24", @"ig_icon_reels_outline_24"],
            @"bubble.left.and.bubble.right": @[@"ig_icon_direct_prism_outline_24"],
            @"circle.dashed": @[@"ig_icon_story_pano_outline_24", @"ig_icon_story_outline_24"],
            @"tray.and.arrow.down": @[@"ig_icon_download_filled_24"],
            @"arrow.up.left.and.arrow.down.right": @[@"ig_icon_fit_outline_24"],
            @"list.bullet.rectangle": @[@"ig_icon_app_instants_archive_outline_24"],
            @"eye.fill":     @[@"ig_icon_eye_filled_24"],
            @"eye.slash":    @[@"ig_icon_eye_off_pano_outline_24"],
            @"eye.slash.fill": @[@"ig_icon_eye_off_filled_24"],
        };
    });
    return map;
}

// MARK: - Internals

static NSBundle *RYGIconFBBundle(void) {
    static NSBundle *bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework"];
        bundle = [NSBundle bundleWithPath:path];
    });
    return bundle;
}

// Colour pet sprites live in the main app bundle; other FB assets are template.
static BOOL RYGIsPetName(NSString *name) {
    static NSArray<NSString *> *prefixes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ prefixes = @[@"Dino-", @"Fire-", @"Heart-", @"Skull-", @"Star-"]; });
    for (NSString *p in prefixes) if ([name hasPrefix:p]) return YES;
    return NO;
}

// Fit the glyph's larger side to pointSize (scales up or down).
static UIImage *RYGIconFitMode(UIImage *image, CGFloat pointSize, UIImageRenderingMode mode) {
    if (!image) return image;
    CGFloat maxDim = MAX(image.size.width, image.size.height);
    if (pointSize <= 0 || maxDim <= 0) return [image imageWithRenderingMode:mode];

    CGFloat ratio = pointSize / maxDim;
    CGSize newSize = CGSizeMake(round(image.size.width * ratio), round(image.size.height * ratio));
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:newSize
                                                                               format:[UIGraphicsImageRendererFormat defaultFormat]];
    UIImage *scaled = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
        [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    }];
    return [scaled imageWithRenderingMode:mode];
}

static UIImage *RYGIconResolveFB(NSString *name) {
    if (name.length == 0) return nil;
    BOOL pet = RYGIsPetName(name);
    UIImageRenderingMode mode = pet ? UIImageRenderingModeAlwaysOriginal : UIImageRenderingModeAlwaysTemplate;
    NSArray<NSString *> *candidates = pet ? @[name] : (RYGIconFriendlyMap()[name.lowercaseString] ?: @[name]);
    NSBundle *fb = RYGIconFBBundle();

    for (NSString *raw in candidates) {
        UIImage *img = fb ? [UIImage imageNamed:raw inBundle:fb compatibleWithTraitCollection:nil] : nil;
        if (!img) img = [UIImage imageNamed:raw inBundle:[NSBundle mainBundle] compatibleWithTraitCollection:nil];
        if (img) return [img imageWithRenderingMode:mode];
    }
    return nil;
}

static UIImage *RYGIconResolveSF(NSString *name, UIImageSymbolConfiguration *cfg) {
    if (name.length == 0) return nil;
    return cfg ? [UIImage systemImageNamed:name withConfiguration:cfg]
               : [UIImage systemImageNamed:name];
}

static UIImage *RYGIconResolveBundlePNG(NSString *name) {
    NSBundle *bundle = RYGLocalizationBundle();
    if (!bundle) return nil;
    UIImage *img = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIImageSymbolConfiguration *RYGIconConfig(CGFloat pointSize, UIImageSymbolWeight weight) {
    if (pointSize > 0) return [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    if (weight != UIImageSymbolWeightUnspecified && weight != UIImageSymbolWeightRegular)
        return [UIImageSymbolConfiguration configurationWithWeight:weight];
    return nil;
}

// Crop to opaque bounds so a padded IG glyph fills its box like an SF symbol.
static UIImage *RYGIconTrimPadding(UIImage *image) {
    if (!image) return nil;
    CGImageRef cg = image.CGImage;
    UIImage *rendered = image;
    if (!cg) {
        UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
        fmt.scale = image.scale > 0 ? image.scale : UIScreen.mainScreen.scale;
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:image.size format:fmt];
        rendered = [r imageWithActions:^(UIGraphicsImageRendererContext *_) {
            [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
        }];
        cg = rendered.CGImage;
    }
    if (!cg) return image;

    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    if (w == 0 || h == 0) return image;

    uint8_t *buf = calloc(w * h * 4, 1);
    if (!buf) return image;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, w * 4, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(buf); return image; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);

    size_t minX = w, minY = h, maxX = 0, maxY = 0;
    BOOL any = NO;
    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            if (buf[(y * w + x) * 4 + 3] > 12) {
                any = YES;
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
    }
    free(buf);
    if (!any) return image;

    CGRect crop = CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1);
    CGImageRef cropped = CGImageCreateWithImageInRect(cg, crop);
    if (!cropped) return image;
    UIImage *out = [UIImage imageWithCGImage:cropped scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(cropped);
    return [out imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// MARK: - Public

@implementation RYGIcon

+ (UIImage *)imageNamed:(NSString *)name {
    return [self imageNamed:name configuration:nil];
}

+ (UIImage *)imageNamed:(NSString *)name pointSize:(CGFloat)pointSize {
    return [self imageNamed:name pointSize:pointSize weight:UIImageSymbolWeightRegular];
}

+ (UIImage *)imageNamed:(NSString *)name pointSize:(CGFloat)pointSize weight:(UIImageSymbolWeight)weight {
    UIImage *fb = RYGIconResolveFB(name);
    if (fb) return RYGIconFitMode(fb, pointSize, RYGIsPetName(name) ? UIImageRenderingModeAlwaysOriginal : UIImageRenderingModeAlwaysTemplate);

    UIImage *sf = RYGIconResolveSF(name, RYGIconConfig(pointSize, weight));
    return sf ?: RYGIconResolveBundlePNG(name);
}

+ (UIImage *)imageNamed:(NSString *)name configuration:(UIImageSymbolConfiguration *)config {
    UIImage *fb = RYGIconResolveFB(name);
    if (fb) return fb;

    UIImage *sf = RYGIconResolveSF(name, config);
    return sf ?: RYGIconResolveBundlePNG(name);
}

+ (UIImage *)fbImageNamed:(NSString *)name {
    return RYGIconResolveFB(name);
}

+ (UIImage *)fbImageNamed:(NSString *)name pointSize:(CGFloat)pointSize {
    return RYGIconFitMode(RYGIconResolveFB(name), pointSize, RYGIsPetName(name) ? UIImageRenderingModeAlwaysOriginal : UIImageRenderingModeAlwaysTemplate);
}

+ (BOOL)isIGAssetName:(NSString *)name {
    return [name hasPrefix:@"ig_icon_"] || [name hasPrefix:@"bcn_"] || RYGIsPetName(name);
}

+ (BOOL)isPetAssetName:(NSString *)name {
    return RYGIsPetName(name);
}

+ (UIImage *)menuImageNamed:(NSString *)name pointSize:(CGFloat)pointSize {
    if ([self isIGAssetName:name]) {
        UIImage *fb = RYGIconResolveFB(name);
        if (fb) {
            // Pets keep colour + full frame; template glyphs get trimmed.
            if (RYGIsPetName(name)) return RYGIconFitMode(fb, pointSize, UIImageRenderingModeAlwaysOriginal);
            return RYGIconFitMode(RYGIconTrimPadding(fb), pointSize, UIImageRenderingModeAlwaysTemplate);
        }
    }
    return RYGIconResolveSF(name, RYGIconConfig(pointSize, UIImageSymbolWeightRegular)) ?: RYGIconResolveBundlePNG(name);
}

+ (UIImage *)sfImageNamed:(NSString *)name {
    return RYGIconResolveSF(name, nil);
}

+ (UIImage *)sfImageNamed:(NSString *)name pointSize:(CGFloat)pointSize {
    return [self sfImageNamed:name pointSize:pointSize weight:UIImageSymbolWeightRegular];
}

+ (UIImage *)sfImageNamed:(NSString *)name pointSize:(CGFloat)pointSize weight:(UIImageSymbolWeight)weight {
    return RYGIconResolveSF(name, RYGIconConfig(pointSize, weight));
}

+ (UIImage *)sfImageNamed:(NSString *)name configuration:(UIImageSymbolConfiguration *)config {
    return RYGIconResolveSF(name, config);
}

@end
