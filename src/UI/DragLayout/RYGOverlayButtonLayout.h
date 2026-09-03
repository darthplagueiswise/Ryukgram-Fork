// Slot grid and normalized-position store for overlay buttons; subclasses declare the
// button set and pref key.

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
+ (CGPoint)slotAtColumn:(NSInteger)col row:(NSInteger)row;
+ (NSArray<NSValue *> *)slotPositions;
+ (CGPoint)nearestSlotTo:(CGPoint)point;
+ (UIEdgeInsets)placeableInsetsNormalized;
+ (NSDictionary<NSString *, NSValue *> *)resolvedPositionsForIDs:(NSArray<NSString *> *)ids inSize:(CGSize)size;
+ (CGPoint)positionForID:(NSString *)buttonID;
+ (void)setPosition:(CGPoint)position forID:(NSString *)buttonID;
+ (NSString *)spacingPrefKey;
+ (CGFloat)spacingPoints;
+ (void)setSpacingPoints:(CGFloat)points;
+ (CGFloat)defaultSpacingPoints;
+ (CGFloat)minSpacingPoints;
+ (CGFloat)maxSpacingPoints;
+ (NSString *)autoCompactPrefKey;
+ (BOOL)autoCompactEnabled;
+ (void)reset;

@end
