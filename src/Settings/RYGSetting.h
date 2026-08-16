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
@property (nonatomic, strong) NSString *subtitle;

@property (nonatomic, strong, nullable) RYGSymbol *icon;
@property (nonatomic, strong) NSString *defaultsKey;

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSURL *imageUrl;
@property (nonatomic, copy, nullable) NSString *bundleImageName;

@property (nonatomic) BOOL requiresRestart;
@property (nonatomic) BOOL disabled;

/// Switch rows: when it returns YES the toggle is forced on and greyed out.
@property (nonatomic, copy, nullable) BOOL (^lockedOnProvider)(void);

/// What's-new dot identifier for keyless rows; pref rows derive it from defaultsKey.
@property (nonatomic, copy, nullable) NSString *whatsNewID;

@property (nonatomic) double min;
@property (nonatomic) double max;
@property (nonatomic) double step;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *singularLabel;

@property (nonatomic, copy) void (^action)(void);

/// Color cell fallback when the defaults key is unset/invalid.
@property (nonatomic, strong, nullable) UIColor *defaultColor;

@property (nonatomic, strong) UIMenu *baseMenu;

@property (nonatomic, copy, nullable) NSString *(^dynamicTitle)(void);

/// Dynamic subtitle, re-evaluated per render. Overrides `subtitle` when set.
@property (nonatomic, copy, nullable) NSString *(^dynamicSubtitle)(void);

/// Pre-rendered icon, used instead of `icon` (RYGSymbol) when set.
@property (nonatomic, strong, nullable) UIImage *iconImage;

@property (nonatomic) BOOL hidesDisclosureIndicator;

/// Block-backed switch: reads/writes through these instead of `defaultsKey`.
@property (nonatomic, copy, nullable) BOOL (^switchValueProvider)(void);
@property (nonatomic, copy, nullable) void (^switchAction)(BOOL on);

/// Custom cell: provider builds it; `customHeight` (>0) fixes the row height.
@property (nonatomic) CGFloat customHeight;
@property (nonatomic, copy, nullable) UITableViewCell *(^customCellProvider)(UITableView *tableView, NSIndexPath *indexPath);

/// Optional trailing label for a static cell. Rendered right-aligned; pairs
/// with `subtitle` (which still renders beneath the title) when both are set.
@property (nonatomic, copy, nullable) NSString *valueText;

/// Dynamic valueText resolver — re-evaluated per cell render so the displayed
/// value stays in sync with prefs that change mid-screen.
@property (nonatomic, copy, nullable) NSString *(^dynamicValueText)(void);

/// Optional override for the title text color. Primarily useful for giving
/// action-style button cells the same tint as link cells.
@property (nonatomic, strong, nullable) UIColor *titleColor;

/// Centered, icon-less, subtitle-less button — the Apply / Reset footer look.
@property (nonatomic) BOOL centeredTitle;

/// Red trailing count badge, re-evaluated per render; hidden when it returns 0.
@property (nonatomic, copy, nullable) NSInteger (^badgeCount)(void);

@property (nonatomic, strong) NSArray *navSections;
@property (nonatomic, strong) UIViewController *navViewController;
@property (nonatomic) BOOL localSearch;

+ (instancetype)staticCellWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                               icon:(nullable RYGSymbol *)icon;

+ (instancetype)linkCellWithTitle:(NSString *)title
                         subtitle:(NSString *)subtitle
                             icon:(nullable RYGSymbol *)icon
                              url:(NSString *)url;

+ (instancetype)linkCellWithTitle:(NSString *)title
                         subtitle:(NSString *)subtitle
                         imageUrl:(NSString *)imageUrl
                              url:(NSString *)url;

+ (instancetype)switchCellWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                        defaultsKey:(NSString *)defaultsKey;

+ (instancetype)switchCellWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                        defaultsKey:(NSString *)defaultsKey
                    requiresRestart:(BOOL)requiresRestart;

+ (instancetype)switchCellWithTitle:(NSString *)title
                           subtitle:(nullable NSString *)subtitle
                              value:(BOOL (^)(void))value
                             action:(void (^)(BOOL on))action;

+ (instancetype)customCellWithHeight:(CGFloat)height
                            provider:(UITableViewCell *(^)(UITableView *tableView, NSIndexPath *indexPath))provider;

+ (instancetype)stepperCellWithTitle:(NSString *)title
                            subtitle:(NSString *)subtitle
                         defaultsKey:(NSString *)defaultsKey
                                 min:(double)min
                                 max:(double)max
                                step:(double)step
                               label:(NSString *)label
                       singularLabel:(NSString *)singularLabel;

+ (instancetype)buttonCellWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                               icon:(nullable RYGSymbol *)icon
                             action:(void (^)(void))action;

+ (instancetype)actionCellWithTitle:(NSString *)title
                              color:(UIColor *)color
                             action:(void (^)(void))action;

+ (instancetype)menuCellWithTitle:(NSString *)title
                         subtitle:(NSString *)subtitle
                             menu:(UIMenu *)menu;

+ (instancetype)colorCellWithTitle:(NSString *)title
                          subtitle:(NSString *)subtitle
                       defaultsKey:(NSString *)defaultsKey
                      defaultColor:(nullable UIColor *)defaultColor;

+ (instancetype)navigationCellWithTitle:(NSString *)title
                               subtitle:(NSString *)subtitle
                                   icon:(nullable RYGSymbol *)icon
                            navSections:(NSArray *)navSections;

+ (instancetype)navigationCellWithTitle:(NSString *)title
                               subtitle:(NSString *)subtitle
                                   icon:(nullable RYGSymbol *)icon
                         viewController:(UIViewController *)viewController;


# pragma mark - Instance methods

- (UIMenu *)menuForButton:(UIButton *)button;

@end

NS_ASSUME_NONNULL_END
