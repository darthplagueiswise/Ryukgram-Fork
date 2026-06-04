#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIBaseSettingsRowStyle) {
	SCIBaseSettingsRowStyleNormal,
	SCIBaseSettingsRowStyleDestructive,
	SCIBaseSettingsRowStyleSwitch,
	SCIBaseSettingsRowStyleCustom
};

@interface SCIBaseSettingsRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, copy, nullable) NSString *(^dynamicTitle)(void);
@property (nonatomic, copy, nullable) NSString *(^dynamicSubtitle)(void);
@property (nonatomic, strong, nullable) UIColor *titleColor;
@property (nonatomic, strong, nullable) UIImage *icon;
@property (nonatomic) SCIBaseSettingsRowStyle style;
@property (nonatomic) UITableViewCellAccessoryType accessoryType;
@property (nonatomic) CGFloat customHeight;
@property (nonatomic, copy, nullable) UIView *(^accessoryProvider)(void);
@property (nonatomic, copy, nullable) UITableViewCell *(^customCellProvider)(UITableView *tableView, NSIndexPath *indexPath);
@property (nonatomic, copy, nullable) void(^action)(UIViewController *vc);
@property (nonatomic, copy, nullable) void(^switchAction)(BOOL enabled, UIViewController *vc);
@property (nonatomic, copy, nullable) BOOL(^switchValue)(void);

+ (instancetype)rowWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle action:(nullable void(^)(UIViewController *vc))action;
+ (instancetype)destructiveRowWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle action:(nullable void(^)(UIViewController *vc))action;
+ (instancetype)switchRowWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle value:(BOOL(^)(void))value action:(void(^)(BOOL enabled, UIViewController *vc))action;
+ (instancetype)customRowWithHeight:(CGFloat)height provider:(UITableViewCell *(^)(UITableView *tableView, NSIndexPath *indexPath))provider;

@end

@interface SCIBaseSettingsSection : NSObject
@property (nonatomic, copy, nullable) NSString *header;
@property (nonatomic, copy, nullable) NSString *footer;
@property (nonatomic, copy) NSArray<SCIBaseSettingsRow *> *rows;

+ (instancetype)sectionWithHeader:(nullable NSString *)header footer:(nullable NSString *)footer rows:(NSArray<SCIBaseSettingsRow *> *)rows;
@end

@interface SCIBaseSettingsListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong, readonly) UITableView *tableView;
@property (nonatomic, copy) NSArray<SCIBaseSettingsSection *> *sections;
@property (nonatomic) BOOL reduceTopInset;

- (instancetype)initWithTitle:(NSString *)title;
- (void)reloadSettings;
@end

NS_ASSUME_NONNULL_END