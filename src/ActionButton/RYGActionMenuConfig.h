// RYGActionMenuConfig — per-source persisted menu layout. Backed by a single
// NSDictionary pref key per source (see RYGActionCatalog +prefKeyForSource:).
// On first load for a given source, seeds defaults from RYGActionCatalog and
// migrates legacy `<src>_action_default` / `menu_date_<src>` keys.

#import <Foundation/Foundation.h>
#import "RYGActionCatalog.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const RYGActionMenuConfigDidChangeNotification; // userInfo: { @"source": @(src) }

@interface RYGActionMenuConfig : NSObject

@property (nonatomic, assign, readonly) RYGActionSource source;
@property (nonatomic, copy, readonly) NSArray<RYGActionConfigSection *> *sections;
@property (nonatomic, copy, readonly) NSSet<NSString *> *disabled;
@property (nonatomic, assign) BOOL showDate;
@property (nonatomic, copy) NSString *defaultTap;       // RYGAID_* or @"menu"
@property (nonatomic, copy) NSString *defaultCopyInfo;  // profile-only

+ (instancetype)configForSource:(RYGActionSource)source;
+ (void)reloadAll;

- (NSArray<RYGActionConfigSection *> *)mutableSections;
- (BOOL)isActionDisabled:(NSString *)actionID;
- (void)setAction:(NSString *)actionID disabled:(BOOL)disabled;

- (nullable RYGActionConfigSection *)sectionWithID:(NSString *)identifier;
- (nullable RYGActionConfigSection *)sectionContainingActionID:(NSString *)actionID;
- (NSArray<NSString *> *)assignedActionIDs;

- (void)moveSectionFromIndex:(NSInteger)src toIndex:(NSInteger)dst;
- (void)moveActionInSection:(RYGActionConfigSection *)section
                  fromIndex:(NSInteger)src
                    toIndex:(NSInteger)dst;
- (void)moveActionID:(NSString *)actionID
            toSection:(RYGActionConfigSection *)dstSection
                index:(NSInteger)dstIndex;
- (void)setSection:(RYGActionConfigSection *)section collapsible:(BOOL)collapsible;

- (void)save;
- (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
