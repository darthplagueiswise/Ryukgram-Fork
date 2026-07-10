// Persistent per-account list of DM thread ids filtered out of the inbox.
// Added via the inbox long-press menu, managed under S&P → Hidden chats.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class UIViewController;

// Posted whenever the reveal state flips (gesture, banner tap, background re-hide).
extern NSString *const SCIHiddenChatsRevealDidChangeNotification;

@interface SCIHiddenChats : NSObject

+ (NSArray<NSDictionary *> *)allEntries;
+ (NSArray<NSString *> *)allThreadIDs;
+ (BOOL)isHidden:(NSString *)threadId;

+ (void)addEntry:(NSDictionary *)entry;
+ (void)removeThreadId:(NSString *)threadId;
+ (void)setAllEntries:(NSArray<NSDictionary *> *)entries;

// In-memory reveal override. Not persisted — a reveal never outlives the session.
+ (BOOL)revealed;
+ (void)setRevealed:(BOOL)revealed;

// Flip the reveal state through the "hidden_reveal" passcode lock, refresh, toast
// and post the change notification. No-op when nothing is hidden.
+ (void)toggleRevealFrom:(nullable UIViewController *)presenter;

+ (void)handleAppBackground;

// In-place ListKit re-diff of the inbox — never the network refresh that wipes
// preserved deleted messages.
+ (void)refreshInboxInPlace;

@end

NS_ASSUME_NONNULL_END
