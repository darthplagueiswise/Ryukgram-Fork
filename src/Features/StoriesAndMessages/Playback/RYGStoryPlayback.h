#import "../../Playback/RYGPlaybackMenu.h"

#ifdef __cplusplus
extern "C" {
#endif

extern __weak UIViewController *rygActiveStoryViewerVC;

id rygStoryMediaController(void);
id rygStoryVideoView(void);
void rygInstallStoryPlaybackLongPress(UIView *view);

#ifdef __cplusplus
}
#endif
