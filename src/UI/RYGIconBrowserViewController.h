// Unified icon browser — System (SF) + Instagram (ig_icon_/bcn_) tabs with
// search. Returns the picked raw name; the render layer keys off the prefix.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGIconBrowserViewController : UIViewController

// Optional leading "special" cell (System tab): shows specialIcon + specialTitle,
// returns specialValue when picked (e.g. clear-override / default).
- (instancetype)initWithTitle:(nullable NSString *)title
                  currentName:(nullable NSString *)currentName
                 specialTitle:(nullable NSString *)specialTitle
                  specialIcon:(nullable NSString *)specialIcon
                 specialValue:(nullable NSString *)specialValue
                   completion:(void (^)(NSString *pickedName))completion;

+ (NSArray<NSString *> *)systemIconNames;
+ (NSArray<NSString *> *)instagramIconNames;

@end

NS_ASSUME_NONNULL_END
