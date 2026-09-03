#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

BOOL rygGifFavContains(NSString *giphyId);
// Returns YES if now favorited.
BOOL rygGifFavToggleId(NSString *giphyId);

#ifdef __cplusplus
}
#endif
