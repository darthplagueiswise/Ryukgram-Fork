// Shared store for overlay-button-placement features (story, DM); subclasses declare buttons + pref key, this owns the slot grid and normalized-position store.

#import <UIKit/UIKit.h>

@interface SCIOverlayButtonLayout : NSObject

#pragma mark - Subclass overrides
+ (NSString *)prefKey;
+ (NSArray<NSString *> *)allIDs;
+ (CGFloat)diameterForID:(NSString *)buttonID;
+ (NSString *)iconForID:(NSString *)buttonID;
+ (BOOL)idEnabled:(NSString *)buttonID;
+ (CGPoint)defaultPositionForID:(NSString *)buttonID;

#pragma mark - Shared
+ (CGPoint)slotAtColumn:(NSInteger)col row:(NSInteger)row;
+ (NSArray<NSValue *> *)slotPositions;
+ (CGPoint)nearestSlotTo:(CGPoint)point;
+ (UIEdgeInsets)placeableInsetsNormalized;
+ (CGPoint)positionForID:(NSString *)buttonID;
+ (void)setPosition:(CGPoint)position forID:(NSString *)buttonID;
+ (void)reset;

@end
