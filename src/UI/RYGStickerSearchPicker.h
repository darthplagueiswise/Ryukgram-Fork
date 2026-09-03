#import <UIKit/UIKit.h>

// Sticker picker sheet: Instagram tray stickers + iOS keyboard stickers.
// Downloads/decodes the chosen sticker to a UIImage and returns it.
@interface RYGStickerSearchPicker : NSObject
+ (void)presentFrom:(UIViewController *)presenter onPick:(void (^)(UIImage *image))onPick;
@end
