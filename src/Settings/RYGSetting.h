#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "RYGSymbol.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGTableCell) {
        RYGTableCellStatic,
        RYGTableCellLink,
        RYGTableCellSwitch,
        RYGTableCellStepper,
        RYGTableCellButton,
        RYGTableCellMenu,
        RYGTableCellNavigation,
        RYGTableCellColor,
        RYGTableCellCustom,
};

@interface RYGSetting : NSObject

@property (nonatomic, readonly) RYGTableCell type;

@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong, nullable) NSString *subtitle;

@property (nonatomic, strong, nullable) RYGSymbol *icon;
@property (nonatomic, strong) NSString *defaultsKey;

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSURL *imageUrl;
@property (nonatomic, copy, nullable) NSString *bundleImageName;

@property (nonatomic) BOOL requiresRestart;
@property (nonatomic) BOOL disabled;

@property (nonatomic, copy, nullable) BOOL (^lockedOnProvider)(void);
@property (nonatomic, copy, nullable) NSString *whatsNewID;

@property (nonatomic) double min;
@property (nonatomic) double max;
@property (nonatomic) double step;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *singularLabel;

@property (nonatomic, copy) void (^action)(void);
@property (nonatomic, strong, nullable) UIColor *defaultColor;
@property (nonatomic, strong) UIMenu *baseMenu;
@property (nonatomic, copy, nullable) NSString *(^dynamicTitle)(void);
@property (nonatomic, copy, nullable) NSString *(^dynamicSubtitle)(void);
@property (nonatomic, strong, nullable) UIImage *iconImage;
@property (nonatomic) BOOL hidesDisclosureIndicator;
@property (nonatomic, copy, nullable) BOOL (^switchValueProvider)(void);
@property (nonatomic, copy, nullable) void (^switchAction)(BOOL on);
@property (nonatomic) CGFloat customHeight;
@property (nonatomic, copy, nullable) UITableViewCell *(^customCellProvider)(UITableView *tableView, NSIndexPath *indexPath);
@property (nonatomic, copy, nullable) NSString *valueText;
@property (nonatomic, copy, nullable) NSString *(^dynamicValueText)(void);
@property (nonatomic, strong, nullable) UIColor *titleColor;
@property (nonatomic) BOOL centeredTitle;
@property (nonatomic, copy, nullable) NSInteger (^badgeCount)(void);

@property (nonatomic, strong) NSArray *navSections;
@property (nonatomic, strong) UIViewController *navViewController;
@property (nonatomic) BOOL localSearch;

+ (instancetype)staticCellWithTitle:(NSString *)title
                           subtitle:(nullable NSString *)subtitle
                               icon:(nullable RYGSymbol *)icon;

+ (instancetype)linkCellWithTitle:(NSString *)title
                         subtitle:(nullable NSString *)subtitle
                             icon:(nullable RYGSymbol *)icon
                              url:(NSString *)url;

+ (instancetype)linkCellWithTitle:(NSString *)title
                         subtitle:(nullable NSString *)subtitle
                         imageUrl:(NSString *)imageUrl
                              url:(NSString *)url;

+ (instancetype)switchCellWithTitle:(NSString *)title
                           subtitle:(nullable NSString *)subtitle
                        defaultsKey:(NSString *)defaultsKey;

+ (instancetype)switchCellWithTitle:(NSString *)title
                           subtitle:(nullable NSString *)subtitle
                        defaultsKey:(NSString *)defaultsKey
                    requiresRestart:(BOOL)requiresRestart;

+ (instancetype)switchCellWithTitle:(NSString *)title
                           subtitle:(nullable NSString *)subtitle
                              value:(BOOL (^)(void))value
                             action:(void (^)(BOOL on))action;

+ (instancetype)customCellWithHeight:(CGFloat)height
                            provider:(UITableViewCell *(^)(UITableView *tableView, NSIndexPath *indexPath))provider;

+ (instancetype)stepperCellWithTitle:(NSString *)title
                            subtitle:(nullable NSString *)subtitle
                         defaultsKey:(NSString *)defaultsKey
                                 min:(double)min
                                 max:(double)max
                                step:(double)step
                               label:(NSString *)label
                       singularLabel:(NSString *)singularLabel;

+ (instancetype)buttonCellWithTitle:(NSString *)title
                           subtitle:(nullable NSString *)subtitle
                               icon:(nullable RYGSymbol *)icon
                             action:(void (^)(void))action;

+ (instancetype)actionCellWithTitle:(NSString *)title
                              color:(UIColor *)color
                             action:(void (^)(void))action;

+ (instancetype)menuCellWithTitle:(NSString *)title
                         subtitle:(nullable NSString *)subtitle
                             menu:(UIMenu *)menu;

+ (instancetype)colorCellWithTitle:(NSString *)title
                          subtitle:(nullable NSString *)subtitle
                       defaultsKey:(NSString *)defaultsKey
                      defaultColor:(nullable UIColor *)defaultColor;

+ (instancetype)navigationCellWithTitle:(NSString *)title
                               subtitle:(nullable NSString *)subtitle
                                   icon:(nullable RYGSymbol *)icon
                            navSections:(NSArray *)navSections;

+ (instancetype)navigationCellWithTitle:(NSString *)title
                               subtitle:(nullable NSString *)subtitle
                                   icon:(nullable RYGSymbol *)icon
                         viewController:(UIViewController *)viewController;

- (UIMenu *)menuForButton:(UIButton *)button;

@end

NS_ASSUME_NONNULL_END
