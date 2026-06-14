// SCIFFmpeg — runtime FFmpegKit wrapper (loads dynamically via dlopen).

#import <Foundation/Foundation.h>

@interface SCIFFmpeg : NSObject

+ (BOOL)isAvailable;

// Cancel any in-flight downloads and running FFmpeg sessions.
+ (void)cancelAll;
+ (BOOL)isCancelled;

+ (void)executeCommand:(NSString *)command
            completion:(void(^)(BOOL success, NSString *output))completion;

+ (void)probeCommand:(NSString *)command
          completion:(void(^)(BOOL success, NSString *output))completion;

+ (void)muxVideoURL:(NSURL *)videoURL
            audioURL:(NSURL *)audioURL
              preset:(NSString *)preset
            progress:(void(^)(float progress, NSString *stage))progressBlock
          completion:(void(^)(NSURL *outputURL, NSError *error))completion;

// Same as above but publishes a per-session cancel block via cancelOut (called once,
// synchronously or on main, before the mux starts). Tapping the pill's ticket cancel
// invokes this — cancels only THIS mux, not other in-flight downloads.
+ (void)muxVideoURL:(NSURL *)videoURL
            audioURL:(NSURL *)audioURL
              preset:(NSString *)preset
            progress:(void(^)(float progress, NSString *stage))progressBlock
          completion:(void(^)(NSURL *outputURL, NSError *error))completion
           cancelOut:(void(^)(void (^cancelBlock)(void)))cancelOut;

// Still photo + a trimmed slice of an audio track → video (music-on-photo posts).
+ (void)muxPhotoURL:(NSURL *)photoURL
           audioURL:(NSURL *)audioURL
       audioStartMs:(double)audioStartMs
         durationMs:(double)durationMs
           progress:(void(^)(float progress, NSString *stage))progressBlock
         completion:(void(^)(NSURL *outputURL, NSError *error))completion
          cancelOut:(void(^)(void (^cancelBlock)(void)))cancelOut;

+ (void)convertAudioAtPath:(NSString *)inputPath
                  toFormat:(NSString *)format
                   bitrate:(NSString *)bitrate
                completion:(void(^)(NSURL *outputURL, NSError *error))completion;

// ffmpeg argv fragments, keyed @"video"/@"audio"/@"container"/@"filter".
// adv_encoding_enabled=NO uses fallbackPreset; YES reads adv_* prefs.
+ (NSDictionary<NSString *, NSString *> *)encodingArgsForFallbackPreset:(NSString *)fallbackPreset;

// Returns YES if the loaded ffmpeg-kit binary ships the given encoder
// (e.g. "libx264", "h264_videotoolbox"). Result cached after first probe.
+ (BOOL)hasEncoder:(NSString *)encoderName;

@end
