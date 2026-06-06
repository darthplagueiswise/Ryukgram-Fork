#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

BOOL SCIIsIOS26OrNewer(void);
UIVisualEffect *_Nullable SCIRealLiquidGlassEffect(BOOL clearStyle, BOOL interactive, UIColor *_Nullable tintColor);
UIColor *SCIGlassBaseSurfaceColor(void);
UIColor *SCIGlassBackdropColor(void);
void SCIApplyOfficialContainerGlassToViewController(UIViewController *vc);
void SCIApplyGlassBackdropToViewController(UIViewController *vc);
void SCIApplyGlassToView(UIView *view, CGFloat radius, BOOL interactive);
void SCIApplyGlassToButton(UIButton *button);
void SCIApplyGlassToSearchBar(UISearchBar *searchBar);
void SCIApplyGlassToSegmentedControl(UISegmentedControl *control);
void SCIApplyGlassToTabBar(UITabBar *tabBar);
void SCIApplyLiquidGlassToViewTree(UIView *root);
void SCIStyleSearchBarForGlass(UISearchBar *searchBar);
void SCIStyleSegmentedControlForGlass(UISegmentedControl *control);
void SCIStyleTableViewForGlass(UITableView *tableView);
void SCIStyleCollectionViewForGlass(UICollectionView *collectionView);
void SCIStyleCellForGlass(UITableViewCell *cell);

@interface SCIAdaptiveGlassPanelView : UIVisualEffectView
@property (nonatomic, assign) CGFloat sciCornerRadius;
@property (nonatomic, assign) BOOL sciGlassInteractive;
@property (nonatomic, assign) BOOL sciGlassClearStyle;
@property (nonatomic, strong, nullable) UIColor *sciGlassTintColor;
- (instancetype)initWithRadius:(CGFloat)radius;
- (void)applyReadableGlassStyle;
@end

@interface SCIGlassSectionHeaderView : UITableViewHeaderFooterView
- (void)configureWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle;
@end

@interface SCIGlassParamCell : UITableViewCell
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle badge:(nullable NSString *)badge emphasized:(BOOL)emphasized;
@end

@interface SCIGlassFloatingToolbar : SCIAdaptiveGlassPanelView
- (instancetype)initWithTarget:(id)target refresh:(SEL)refresh clear:(SEL)clear export:(SEL)export toggleCapture:(SEL)toggleCapture;
- (void)setCaptureEnabled:(BOOL)enabled;
@end

@interface SCIGlassSearchBar : SCIAdaptiveGlassPanelView
@property (nonatomic, strong, readonly) UISearchBar *searchBar;
@end

NS_ASSUME_NONNULL_END
