// SCIQualityPicker — quality selection bottom sheet for HD downloads.

#import <UIKit/UIKit.h>
#import "SCIDashParser.h"
#import "Downloader/Download.h"

@interface SCIQualityPicker : NSObject

/// Show quality picker or auto-pick based on prefs. Returns NO if enhanced
/// downloads are off or no DASH manifest is found (calls fallback). URL-form
/// manifests resolve async — fallback may still fire after returning YES.
/// `action` is passed through to the Audio / Photo rows inside the sheet.
+ (BOOL)pickQualityForMedia:(id)media
                   fromView:(UIView *)sourceView
                     action:(DownloadAction)action
                     picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked
                   fallback:(void(^)(void))fallback;

/// Same as above but driven by a raw inline DASH manifest + the progressive
/// "standard" URL — for media that carry the manifest directly (DM
/// disappearing media) rather than via an IGMedia fieldCache.
+ (BOOL)pickQualityWithManifestXML:(NSString *)manifestXML
                       standardURL:(NSURL *)standardURL
                          fromView:(UIView *)sourceView
                            action:(DownloadAction)action
                            picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked
                          fallback:(void(^)(void))fallback;

@end
