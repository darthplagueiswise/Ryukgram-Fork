#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "TweakSettings.h"
#import "RYGSetting.h"
#import "RYGSymbol.h"
#import "../Utils.h"

NS_ASSUME_NONNULL_BEGIN

/// A page that contributes rows to the settings search index. Settings-list pages
/// adopt it via RYGSettingsViewController; bespoke pages implement it by hand.
/// Entry keys: title, subtitle, section, optional target (VC to open on tap).
@protocol RYGSettingsSearchable <NSObject>
- (NSArray<NSDictionary *> *)rygSearchableSettingsEntries;
@end

@interface RYGSettingsViewController : UIViewController <RYGSettingsSearchable>

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray *)sections reduceMargin:(BOOL)reduceMargin;
- (instancetype)init;

// scrolls to this section on first appear
@property (nonatomic, copy, nullable) NSString *scrollToSectionHeader;

#pragma mark - Subclassing

/// Exposed so subclasses can register custom cell classes.
@property (nonatomic, strong, readonly) UITableView *tableView;

/// Non-root list initializer for subclasses (no search / nav chrome).
- (instancetype)initWithTitle:(NSString *)title;

/// Sets the displayed rows (section dicts) and reloads.
- (void)applySettingSections:(NSArray *)sections;

/// Subclass hook: build sections and call applySettingSections:. Default no-op.
- (void)rebuildSections;

/// Builds a section dict, omitting nil header/footer.
+ (NSDictionary *)sectionWithHeader:(nullable NSString *)header
                             footer:(nullable NSString *)footer
                               rows:(NSArray<RYGSetting *> *)rows;

@end

NS_ASSUME_NONNULL_END
