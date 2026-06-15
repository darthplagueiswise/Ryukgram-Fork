#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface SCIInternalMenusLauncher : NSObject

// ── Reliable openers (work without a captured config) ──────────────────────
// Calls +[IGDirectNotesDogfoodingSettingsStaticFuncs
//         notesDogfoodingSettingsOpenOnViewController:userSession:].
// Always opens the native Notes/Dogfooding Settings surface.
+ (NSString *)openDogfoodingNotesSettings;

// Walks through a cascade of IG-internal openers (Notes → Dogfooding VC if
// config was captured → Autofill internal settings → URL handler fallback).
// Returns a human-readable result string suitable for a toast.
+ (NSString *)openBestAvailableInternalMenu;

// ── Openers that need a live user session ──────────────────────────────────
// Opens IGDogfoodingSettingsViewController via openWithConfig:onViewController:userSession:
// or initWithConfig:userSession:. Only works if a config was captured by the
// runtime observer (i.e., IG's employee gate was on at some point this session).
+ (NSString *)openDogfoodingSettingsVC;

// Opens the autofill-internal-settings debug surface (validates that
// IGAutofillTokenizationInternalSettingsPlugin / IGAutofillInternalSettings
// exist and can be instantiated without a full employee session).
+ (NSString *)openAutofillInternalSettings;

// Opens the internal search-debug settings surface:
// _TtC21IGSearchDebugSettings35IGSearchDebugSettingsViewController
+ (NSString *)openSearchDebugSettings;

// Opens the story-store debug settings surface:
// _TtC26IGStoryStoresDebugSettings39IGStoryStoreDebugSettingsViewController
+ (NSString *)openStoryStoreDebugSettings;

// Tries several known internal-URL schemes through IGURLHandler. The urlString
// may be e.g. @"instagram://internal_settings" or any known ig:// deep link.
+ (NSString *)openInternalURLString:(NSString *)urlString;

@end
NS_ASSUME_NONNULL_END
