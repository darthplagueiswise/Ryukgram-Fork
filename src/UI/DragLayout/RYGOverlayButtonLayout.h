// Shared store for overlay-button-placement features (story, DM); subclasses declare buttons + pref key, this owns the slot grid and normalized-position store.

#import <UIKit/UIKit.h>

@interface RYGOverlayButtonLayout : NSObject

#pragma mark - Subclass overrides
+ (NSString *)prefKey;
+ (NSArray<NSString *> *)allIDs;
+ (CGFloat)diameterForID:(NSString *)buttonID;
+ (NSString *)iconForID:(NSString *)buttonID;
+ (BOOL)idEnabled:(NSString *)buttonID;
+ (CGPoint)defaultPositionForID:(NSString *)buttonID;

#pragma mark - Shared
+ (CGSize)referenceSize;
+ (NSInteger)slotColumns;
+ (NSInteger)slotRows;
+ (NSInteger)slotColumnsForSize:(CGSize)size;
+ (NSInteger)slotRowsForSize:(CGSize)size;
+ (CGPoint)normalizedSlotAtColumn:(NSInteger)col row:(NSInteger)row cols:(NSInteger)cols rows:(NSInteger)rows;
+ (CGPoint)slotAtColumn:(NSInteger)col row:(NSInteger)row;
+ (NSArray<NSValue *> *)slotPositions;
+ (CGPoint)nearestSlotTo:(CGPoint)point;
+ (UIEdgeInsets)placeableInsetsNormalized;
+ (NSDictionary<NSString *, NSValue *> *)resolvedPositionsForIDs:(NSArray<NSString *> *)ids inSize:(CGSize)size;
+ (CGPoint)positionForID:(NSString *)buttonID;
+ (void)setPosition:(CGPoint)position forID:(NSString *)buttonID;
+ (void)reset;

@end
