#import "SCIOverlayButtonLayout.h"
#import "../../Utils.h"

static const NSInteger kSlotCols = 10;
static const NSInteger kSlotRows = 12;

@implementation SCIOverlayButtonLayout

+ (NSString *)prefKey { return nil; }
+ (NSArray<NSString *> *)allIDs { return @[]; }
+ (CGFloat)diameterForID:(NSString *)buttonID { return 36.0; }
+ (NSString *)iconForID:(NSString *)buttonID { return @"square"; }
+ (BOOL)idEnabled:(NSString *)buttonID { return YES; }
+ (CGPoint)defaultPositionForID:(NSString *)buttonID { return CGPointMake(0.5, 0.5); }

+ (UIEdgeInsets)placeableInsetsNormalized {
	return UIEdgeInsetsMake(0.0, 0.0, 0.10, 0.0);
}

+ (CGPoint)slotAtColumn:(NSInteger)col row:(NSInteger)row {
	CGFloat marginX = 0.07;
	CGFloat yBottom = 0.875;
	CGFloat yStep = 0.0495;
	CGFloat x = marginX + (CGFloat)col * (1.0 - 2.0 * marginX) / (CGFloat)(kSlotCols - 1);
	CGFloat y = yBottom - (CGFloat)row * yStep;
	return CGPointMake(x, y);
}

+ (NSArray<NSValue *> *)slotPositions {
	NSMutableArray *out = NSMutableArray.array;
	for (NSInteger row = 0; row < kSlotRows; row++) {
		for (NSInteger col = 0; col < kSlotCols; col++) {
			[out addObject:[NSValue valueWithCGPoint:[self slotAtColumn:col row:row]]];
		}
	}
	return out;
}

+ (CGPoint)nearestSlotTo:(CGPoint)point {
	CGPoint best = CGPointMake(0.5, 0.5);
	CGFloat bestDist = CGFLOAT_MAX;
	for (NSValue *v in [self slotPositions]) {
		CGPoint s = v.CGPointValue;
		CGFloat dd = hypot(point.x - s.x, point.y - s.y);
		if (dd < bestDist) { bestDist = dd; best = s; }
	}
	return best;
}

+ (CGPoint)positionForID:(NSString *)buttonID {
	NSDictionary *all = [SCIUtils getDictPref:[self prefKey]];
	NSDictionary *p = all[buttonID];

	if ([p isKindOfClass:NSDictionary.class] && p[@"x"] && p[@"y"]) {
		return CGPointMake([p[@"x"] doubleValue], [p[@"y"] doubleValue]);
	}
	return [self defaultPositionForID:buttonID];
}

+ (void)setPosition:(CGPoint)position forID:(NSString *)buttonID {
	NSMutableDictionary *all = [[SCIUtils getDictPref:[self prefKey]] mutableCopy] ?: NSMutableDictionary.dictionary;
	all[buttonID] = @{ @"x": @(position.x), @"y": @(position.y) };
	[SCIUtils setPref:all forKey:[self prefKey]];
}

+ (void)reset {
	[SCIUtils setPref:@{} forKey:[self prefKey]];
}

@end
