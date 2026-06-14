// Shared source for the tweak's story-menu items, consumed by both the old IGDSMenu (3-dot) and
// the new IGActionListViewController sheet so they never drift. Add an item by writing a provider
// and appending it in sciStoryMenuEntries().

#import <Foundation/Foundation.h>

@interface SCIStoryMenuEntry : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;   // SF Symbol for the new sheet menu (nil = no icon)
@property (nonatomic, copy) void (^handler)(void);
+ (instancetype)entryWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(void (^)(void))handler;
@end

#ifdef __cplusplus
extern "C" {
#endif

// Per-feature providers (defined in each feature file; nil when the entry shouldn't appear now).
SCIStoryMenuEntry *sciStoryExcludeMenuEntry(void);
SCIStoryMenuEntry *sciStoryAudioMenuEntry(void);
SCIStoryMenuEntry *sciStoryMentionsMenuEntry(void);

// Ordered, gated list both menus consume.
NSArray<SCIStoryMenuEntry *> *sciStoryMenuEntries(void);

// Old IGDSMenu (3-dot) glue: detect the story menu, then append every entry as an IGDSMenuItem.
BOOL sciItemsLookLikeStoryMenu(NSArray *items);
NSArray *sciAppendStoryEntriesToIGDSMenu(NSArray *items);

#ifdef __cplusplus
}
#endif
