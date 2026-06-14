#import <Foundation/Foundation.h>

@class SCISetting;

NS_ASSUME_NONNULL_BEGIN

// Drives the "new this release" leading dot in settings: a row is dotted while
// its identifier is in newIDs and unseen, and clears once viewed.
@interface SCIWhatsNew : NSObject

// Curated identifiers new this release — the one list to update each release.
+ (NSSet<NSString *> *)newIDs;

+ (BOOL)isUnseen:(nullable NSString *)identifier;
+ (void)markSeen:(nullable NSString *)identifier;

// whatsNewID, else defaultsKey, else (menu cells) the key in the menu's actions.
+ (nullable NSString *)identifierForRow:(SCISetting *)row;

// YES if any descendant row of navSections is unseen (powers parent-tab dots).
+ (BOOL)sectionsHaveUnseen:(nullable NSArray *)sections;

@end

NS_ASSUME_NONNULL_END
