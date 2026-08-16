// Shared helpers for StoryOverlayButtons.xm and DMOverlayButtons.xm.

#import "StoryHelpers.h"
#import "../../Gallery/RYGGallerySaveMetadata.h"

// Disjoint tag spaces so viewWithTag: can't cross-hit between surfaces.
#define RYG_STORY_EYE_TAG       1339
#define RYG_STORY_ACTION_TAG    1340
#define RYG_STORY_AUDIO_TAG     1341
#define RYG_DM_ACTION_TAG       1342
#define RYG_DM_EYE_TAG          1343
#define RYG_DM_AUDIO_TAG        1344
#define RYG_STORY_MENTIONS_TAG  1345

#ifdef __cplusplus
extern "C" {
#endif

// From StoryAudioToggle.xm.
void rygToggleStoryAudio(void);
BOOL rygIsStoryAudioEnabled(void);
void rygInitStoryAudioState(void);

#ifdef __cplusplus
}
#endif
extern BOOL dmVisualMsgsViewedButtonEnabled;
#ifdef __cplusplus
extern "C" {
#endif

// Context detection / view lookup.
BOOL rygOverlayIsInDMContext(UIView *overlay);
UIView * _Nullable rygFindOverlayInView(UIView *root);

// DM disappearing-media actions.
NSURL * _Nullable rygDMMediaURL(UIViewController *dmVC, BOOL *outIsVideo);
void rygDMExpandMedia(UIViewController *dmVC);
void rygDMShareMedia(UIViewController *dmVC);
void rygDMDownloadMedia(UIViewController *dmVC);
void rygDMDownloadMediaToGallery(UIViewController *dmVC);
void rygDMMarkCurrentAsViewed(UIViewController *dmVC);

// DM message → save metadata (sender PK + username + profile pic via the
// shared user resolver).
RYGGallerySaveMetadata *rygDMMetadataFromMessage(id msg);
RYGGallerySaveMetadata *rygDMMetadataForVC(UIViewController *dmVC);

// Opens RyukGram settings on the Messages tab.
void rygOpenMessagesSettings(UIView *source);

// Story mentions sheet (StoryMentions.x).
void rygShowStoryMentions(UIViewController *presenter, UIView *anchor);
BOOL rygStoryHasMentionsOrShares(UIView *anchor);
NSInteger rygStoryMentionsCount(UIView *anchor);

#ifdef __cplusplus
}
#endif
