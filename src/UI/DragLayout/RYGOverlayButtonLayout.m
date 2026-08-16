#import "RYGOverlayButtonLayout.h"
#import "../../Utils.h"

static const CGFloat kMarginXN = 0.07;
static const CGFloat kBottomN = 0.875;
static const CGFloat kTopN = 0.083;
static const CGFloat kSlotGapPts = 6.0;

// Stories render in a portrait phone-shaped card on every device, so the reference grid,
// defaults and preview key off this canonical size — real placement adapts to the live size.
static const CGFloat kRefW = 393.0;
static const CGFloat kRefH = 852.0;

static CGSize rygOverlaySafeSize(void) {
	return CGSizeMake(kRefW, kRefH);
}

@implementation RYGOverlayButtonLayout

+ (NSString *)prefKey { return nil; }
+ (NSArray<NSString *> *)allIDs { return @[]; }
+ (CGFloat)diameterForID:(NSString *)buttonID { return 36.0; }
+ (NSString *)iconForID:(NSString *)buttonID { return @"square"; }
+ (BOOL)idEnabled:(NSString *)buttonID { return YES; }
+ (CGPoint)defaultPositionForID:(NSString *)buttonID { return CGPointMake(0.5, 0.5); }

+ (UIEdgeInsets)placeableInsetsNormalized {
	return UIEdgeInsetsMake(0.06, 0.0, 0.10, 0.0);
}

+ (CGSize)referenceSize {
	return rygOverlaySafeSize();
}

+ (CGFloat)slotMinStepPoints {
	CGFloat maxD = 0.0;
	for (NSString *bid in [self allIDs]) maxD = MAX(maxD, [self diameterForID:bid]);
	if (maxD <= 0.0) maxD = 36.0;
	return maxD + kSlotGapPts;
}

static NSInteger rygColsForWidth(CGFloat width, CGFloat minStep) {
	CGFloat usable = width * (1.0 - 2.0 * kMarginXN);
	return MAX(2, (NSInteger)floor(usable / minStep) + 1);
}

static NSInteger rygRowsForHeight(CGFloat height, CGFloat minStep) {
	CGFloat span = height * (kBottomN - kTopN);
	return MAX(2, (NSInteger)floor(span / minStep) + 1);
}

static CGPoint rygSlotNorm(NSInteger col, NSInteger row, NSInteger cols, NSInteger rows) {
	CGFloat x = kMarginXN + (CGFloat)col * (1.0 - 2.0 * kMarginXN) / (CGFloat)(cols - 1);
	CGFloat y = kBottomN - (CGFloat)row * (kBottomN - kTopN) / (CGFloat)(rows - 1);
	return CGPointMake(x, y);
}

+ (NSInteger)slotColumns {
	return rygColsForWidth(rygOverlaySafeSize().width, [self slotMinStepPoints]);
}

+ (NSInteger)slotRows {
	return rygRowsForHeight(rygOverlaySafeSize().height, [self slotMinStepPoints]);
}

+ (NSInteger)slotColumnsForSize:(CGSize)size {
	return rygColsForWidth(size.width, [self slotMinStepPoints]);
}

+ (NSInteger)slotRowsForSize:(CGSize)size {
	return rygRowsForHeight(size.height, [self slotMinStepPoints]);
}

+ (CGPoint)normalizedSlotAtColumn:(NSInteger)col row:(NSInteger)row cols:(NSInteger)cols rows:(NSInteger)rows {
	return rygSlotNorm(col, row, cols, rows);
}

typedef struct { NSInteger col, row, cols, rows; } RYGSlotRef;

static RYGSlotRef rygDeriveRef(CGPoint norm, NSInteger cols, NSInteger rows) {
	NSInteger col = (NSInteger)llround((norm.x - kMarginXN) * (CGFloat)(cols - 1) / (1.0 - 2.0 * kMarginXN));
	NSInteger row = (NSInteger)llround((kBottomN - norm.y) * (CGFloat)(rows - 1) / (kBottomN - kTopN));
	RYGSlotRef ref = { MIN(MAX(col, 0), cols - 1), MIN(MAX(row, 0), rows - 1), cols, rows };
	return ref;
}

// Far-half indices keep their distance to the far edge, so an edge cluster stays a cluster
// on any grid size.
static NSInteger rygMapIndex(NSInteger idx, NSInteger fromCount, NSInteger toCount) {
	NSInteger mapped = (idx * 2 > fromCount - 1) ? toCount - 1 - (fromCount - 1 - idx) : idx;
	return MIN(MAX(mapped, 0), toCount - 1);
}

static BOOL rygSlotTaken(const NSInteger *taken, NSUInteger count, NSInteger slot) {
	for (NSUInteger i = 0; i < count; i++) {
		if (taken[i] == slot) return YES;
	}
	return NO;
}

+ (NSDictionary<NSString *, NSValue *> *)resolvedPositionsForIDs:(NSArray<NSString *> *)ids inSize:(CGSize)size {
	if (size.width <= 0 || size.height <= 0 || !ids.count) return @{};

	CGFloat minStep = [self slotMinStepPoints];
	NSInteger colsR = rygColsForWidth(size.width, minStep);
	NSInteger rowsR = rygRowsForHeight(size.height, minStep);

	CGSize home = rygOverlaySafeSize();
	NSInteger colsE = rygColsForWidth(home.width, minStep);
	NSInteger rowsE = rygRowsForHeight(home.height, minStep);

	NSInteger taken[16];
	NSUInteger takenCount = 0;
	NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:ids.count];

	for (NSString *bid in ids) {
		RYGSlotRef ref = rygDeriveRef([self positionForID:bid], colsE, rowsE);

		NSInteger col = rygMapIndex(ref.col, ref.cols, colsR);
		NSInteger row = rygMapIndex(ref.row, ref.rows, rowsR);

		if (rygSlotTaken(taken, takenCount, row * colsR + col)) {
			NSInteger dir = (ref.col * 2 > ref.cols - 1) ? -1 : 1;
			NSInteger foundCol = -1, foundRow = -1;

			for (NSInteger rOff = 0; rOff < rowsR && foundCol < 0; rOff++) {
				NSInteger rTry[2] = { row + rOff, row - rOff };
				for (NSInteger ri = 0; ri < (rOff ? 2 : 1) && foundCol < 0; ri++) {
					NSInteger r = rTry[ri];
					if (r < 0 || r >= rowsR) continue;
					for (NSInteger cOff = 0; cOff < colsR && foundCol < 0; cOff++) {
						NSInteger cTry[2] = { col + dir * cOff, col - dir * cOff };
						for (NSInteger ci = 0; ci < (cOff ? 2 : 1); ci++) {
							NSInteger c = cTry[ci];
							if (c < 0 || c >= colsR) continue;
							if (!rygSlotTaken(taken, takenCount, r * colsR + c)) { foundCol = c; foundRow = r; break; }
						}
					}
				}
			}

			if (foundCol >= 0) { col = foundCol; row = foundRow; }
		}

		if (takenCount < 16) taken[takenCount++] = row * colsR + col;
		out[bid] = [NSValue valueWithCGPoint:rygSlotNorm(col, row, colsR, rowsR)];
	}

	return out;
}

+ (CGPoint)slotAtColumn:(NSInteger)col row:(NSInteger)row {
	NSInteger cols = [self slotColumns];
	NSInteger rows = [self slotRows];
	col = MIN(MAX(col, 0), cols - 1);
	row = MIN(MAX(row, 0), rows - 1);
	return rygSlotNorm(col, row, cols, rows);
}

+ (NSArray<NSValue *> *)slotPositions {
	NSInteger cols = [self slotColumns];
	NSInteger rows = [self slotRows];
	NSMutableArray *out = NSMutableArray.array;
	for (NSInteger row = 0; row < rows; row++) {
		for (NSInteger col = 0; col < cols; col++) {
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
	NSDictionary *all = [RYGUtils getDictPref:[self prefKey]];
	NSDictionary *p = all[buttonID];

	if ([p isKindOfClass:NSDictionary.class] && p[@"x"] && p[@"y"]) {
		return CGPointMake([p[@"x"] doubleValue], [p[@"y"] doubleValue]);
	}
	return [self defaultPositionForID:buttonID];
}

+ (void)setPosition:(CGPoint)position forID:(NSString *)buttonID {
	NSMutableDictionary *all = [[RYGUtils getDictPref:[self prefKey]] mutableCopy] ?: NSMutableDictionary.dictionary;
	all[buttonID] = @{ @"x": @(position.x), @"y": @(position.y) };
	[RYGUtils setPref:all forKey:[self prefKey]];
}

+ (void)reset {
	[RYGUtils setPref:@{} forKey:[self prefKey]];
}

@end
