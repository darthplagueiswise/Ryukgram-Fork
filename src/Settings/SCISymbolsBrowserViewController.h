#import <UIKit/UIKit.h>
// Mach-O LC_SYMTAB browser — shows ALL exported C symbols from the selected
// binary image at runtime. FLEX cannot show these (it only reads ObjC runtime
// tables). This VC reads __LINKEDIT directly via _dyld_get_image_header().
@interface SCISymbolsBrowserViewController : UIViewController
@end
