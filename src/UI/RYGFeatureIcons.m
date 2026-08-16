#import "RYGFeatureIcons.h"

// igNames are verified against FBSharedFramework's catalog — an unknown one
// silently falls back to SF.
@implementation RYGFeatureIcons

+ (RYGSymbol *)deletedMessages { return [RYGSymbol symbolWithIGName:@"ig_icon_delete_outline_24" fallback:@"tray.full"]; }
+ (RYGSymbol *)readReceipts { return [RYGSymbol symbolWithIGName:@"ig_icon_eye_outline_24" fallback:@"eye"]; }
+ (RYGSymbol *)callRecordings { return [RYGSymbol symbolWithIGName:@"ig_icon_call_outline_24" fallback:@"phone.badge.waveform"]; }
+ (RYGSymbol *)followRequests { return [RYGSymbol symbolWithIGName:@"bcn_users-add_outline_24" fallback:@"person.crop.circle.badge.plus"]; }
+ (RYGSymbol *)gallery { return [RYGSymbol symbolWithIGName:@"ig_icon_photo_gallery_outline_24" fallback:@"photo.on.rectangle.angled"]; }
+ (RYGSymbol *)chatBackgrounds { return [RYGSymbol symbolWithIGName:@"bcn_image_outline_24" fallback:@"photo.artframe"]; }
+ (RYGSymbol *)profileAnalyzer { return [RYGSymbol symbolWithIGName:@"green_screen" fallback:@"person.fill.viewfinder"]; }
+ (RYGSymbol *)storiesArchive { return [RYGSymbol symbolWithIGName:@"ig_icon_story_highlight_pano_outline_24" fallback:@"clock.arrow.circlepath"]; }
// The burst glyph ships filled only, so the outline set uses its plain sibling.
+ (RYGSymbol *)instants { return [RYGSymbol symbolWithIGName:@"ig_icon_app_instants_outline_24" fallback:@"bolt"]; }
+ (RYGSymbol *)settings { return [RYGSymbol symbolWithIGName:@"settings" fallback:@"gear"]; }
+ (RYGSymbol *)downloads { return [RYGSymbol symbolWithIGName:@"download_filled" fallback:@"arrow.down.circle"]; }
+ (RYGSymbol *)hiddenLockedChats { return [RYGSymbol symbolWithIGName:@"ig_icon_lock_pano_outline_24" fallback:@"lock.shield"]; }
+ (RYGSymbol *)revealHidden { return [RYGSymbol symbolWithIGName:@"ig_icon_eye_off_outline_24" fallback:@"eye.slash"]; }
+ (RYGSymbol *)filters { return [RYGSymbol symbolWithIGName:@"ig_icon_edit_list_outline_24" fallback:@"list.bullet.rectangle"]; }
+ (RYGSymbol *)featureData { return [RYGSymbol symbolWithName:@"shippingbox.fill"]; }
+ (RYGSymbol *)storage { return [RYGSymbol symbolWithName:@"internaldrive"]; }

+ (RYGSymbol *)deletedMessagesFilled { return [RYGSymbol symbolWithIGName:@"ig_icon_delete_filled_24" fallback:@"tray.full.fill"]; }
+ (RYGSymbol *)readReceiptsFilled { return [RYGSymbol symbolWithIGName:@"ig_icon_eye_filled_24" fallback:@"eye.fill"]; }
+ (RYGSymbol *)callRecordingsFilled { return [RYGSymbol symbolWithIGName:@"ig_icon_call_filled_24" fallback:@"phone.fill"]; }
+ (RYGSymbol *)chatBackgroundsFilled { return [RYGSymbol symbolWithIGName:@"bcn_image_filled_24" fallback:@"photo.artframe"]; }
+ (RYGSymbol *)hiddenLockedChatsFilled { return [RYGSymbol symbolWithIGName:@"ig_icon_lock_filled_24" fallback:@"lock.fill"]; }
+ (RYGSymbol *)instantsFilled { return [RYGSymbol symbolWithIGName:@"ig_icon_app_instants_burst_filled_24" fallback:@"bolt.fill"]; }
+ (RYGSymbol *)downloadsFilled { return [RYGSymbol symbolWithIGName:@"download_filled" fallback:@"arrow.down.circle.fill"]; }

@end
