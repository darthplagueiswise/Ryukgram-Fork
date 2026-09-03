#import <Foundation/Foundation.h>

// * Tweak version *
extern NSString *RYGVersionString;

// * URLs — single source of truth, not localized *
static NSString *const RYGRepoSlug = @"faroukbmiled/RyukGram";
static NSString *const RYGRepoURL = @"https://github.com/faroukbmiled/RyukGram";
static NSString *const RYGRepoIssuesURL = @"https://github.com/faroukbmiled/RyukGram/issues";
static NSString *const RYGRepoReleasesURL = @"https://github.com/faroukbmiled/RyukGram/releases";
static NSString *const RYGRepoTranslateURL = @"https://github.com/faroukbmiled/RyukGram#translating-ryukgram";
static NSString *const RYGAuthorURL = @"https://github.com/faroukbmiled";
static NSString *const RYGTelegramURL = @"https://t.me/ryukgram";
static NSString *const RYGTelegramScheme = @"tg://resolve?domain=ryukgram";
static NSString *const RYGDonateURL = @"https://buymeacoffee.com/axryuk";
static NSString *const RYGSoCuulRepoURL = @"https://github.com/SoCuul/SCInsta";

// Variables that work across features
extern BOOL dmVisualMsgsViewedButtonEnabled; // Whether story dm unlimited views button is enabled
extern BOOL dmSeenToggleEnabled; // Whether read receipts toggle is active