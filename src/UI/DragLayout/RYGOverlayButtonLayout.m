#import "RYGOverlayButtonLayout.h"
#import "../../Utils.h"

static const CGFloat kMarginXN = 0.07;
static const CGFloat kBottomN = 0.875;
static const CGFloat kTopN = 0.083;
static const CGFloat kDefaultGapPts = 6.0;
static const CGFloat kMinGapPts = 2.0;
static const CGFloat kMaxGapPts = 40.0;

// Defaults and the preview key off this canonical portrait card; real placement adapts to the live size.
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

#pragma mark - Spacing

+ (NSString *)spacingPrefKey {
	NSString *base = [self prefKey];
	return base.length ? [base stringByAppendingString:@"_spacing"] : nil;
}

+ (CGFloat)defaultSpacingPoints { return kDefaultGapPts; }
+ (CGFloat)minSpacingPoints { return kMinGapPts; }
+ (CGFloat)maxSpacingPoints { return kMaxGapPts; }

+ (CGFloat)spacingPoints {
	NSString *key = [self spacingPrefKey];
	if (!key) return kDefaultGapPts;
	CGFloat v = [RYGUtils getDoublePref:key];
	if (v <= 0.0) return kDefaultGapPts;
	return MIN(MAX(v, kMinGapPts), kMaxGapPts);
}

+ (CGFloat)slotMinStepPoints {
	CGFloat maxD = 0.0;
	for (NSString *bid in [self allIDs]) maxD = MAX(maxD, [self diameterForID:bid]);
	if (maxD <= 0.0) maxD = 36.0;
	return maxD + [self spacingPoints];
}

#pragma mark - Slot grid

static NSInteger rygColsForWidth(CGFloat width, CGFloat minStep) {
	CGFloat usable = width * (1.0 - 2.0 * kMarginXN);
	return MAX(2, (NSInteger)floor(usable / minStep) + 1);
}

static NSInteger rygRowsForHeight(CGFloat height, CGFloat minStep) {
	CGFloat span = height * (kBottomN - kTopN);
	return MAX(2, (NSInteger)floor(span / minStep) + 1);
}

// Exact pitch inward from the nearest edge keeps both edges anchored and the slack mid-grid;
// spreading evenly would inflate the gap past what was asked for.
static CGFloat rygAxisNorm(NSInteger idx, NSInteger count, CGFloat lowAnchor, CGFloat highAnchor, CGFloat stepN) {
	if (count < 2) return (lowAnchor + highAnchor) / 2.0;
	return (idx * 2 <= count - 1) ? lowAnchor + idx * stepN : highAnchor - (count - 1 - idx) * stepN;
}

static NSInteger rygAxisIndex(CGFloat value, NSInteger count, CGFloat lowAnchor, CGFloat highAnchor, CGFloat stepN) {
	NSInteger idx;
	if (stepN <= 0.0) {
		idx = 0;
	} else if (value <= (lowAnchor + highAnchor) / 2.0) {
		idx = (NSInteger)llround((value - lowAnchor) / stepN);
	} else {
		idx = count - 1 - (NSInteger)llround((highAnchor - value) / stepN);
	}
	return MIN(MAX(idx, 0), count - 1);
}

static CGPoint rygSlotNorm(NSInteger col, NSInteger row, NSInteger cols, NSInteger rows, CGSize size, CGFloat minStep) {
	CGFloat x = rygAxisNorm(col, cols, kMarginXN, 1.0 - kMarginXN, minStep / size.width);
	CGFloat y = rygAxisNorm(rows - 1 - row, rows, kTopN, kBottomN, minStep / size.height);
	return CGPointMake(x, y);
}

+ (NSInteger)slotColumns {
	return rygColsForWidth(rygOverlaySafeSize().width, [self slotMinStepPoints]);
}

+ (NSInteger)slotRows {
	return rygRowsForHeight(rygOverlaySafeSize().height, [self slotMinStepPoints]);
}

typedef struct { NSInteger col, row; } RYGSlotRef;

static RYGSlotRef rygDeriveRef(CGPoint norm, NSInteger cols, NSInteger rows, CGSize size, CGFloat minStep) {
	NSInteger col = rygAxisIndex(norm.x, cols, kMarginXN, 1.0 - kMarginXN, minStep / size.width);
	NSInteger flipped = rygAxisIndex(norm.y, rows, kTopN, kBottomN, minStep / size.height);
	RYGSlotRef ref = { col, rows - 1 - flipped };
	return ref;
}

// Far-half indices keep their distance to the far edge, so an edge cluster survives a resize.
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

#define RYG_MAX_LAYOUT_IDS 16

typedef struct {
	NSInteger col[RYG_MAX_LAYOUT_IDS];
	NSInteger row[RYG_MAX_LAYOUT_IDS];
	BOOL present[RYG_MAX_LAYOUT_IDS];
	NSUInteger count;
} RYGArrangement;

// Chains of buttons that touch along one axis: same `key`, consecutive `idx`.
static void rygBuildRuns(const NSInteger *key, const NSInteger *idx, NSUInteger n, NSInteger *runOf, NSInteger *runLen) {
	for (NSUInteger i = 0; i < n; i++) runOf[i] = -1;

	NSInteger nextRun = 0;
	for (NSUInteger i = 0; i < n; i++) {
		if (runOf[i] >= 0) continue;

		NSInteger members[RYG_MAX_LAYOUT_IDS];
		NSInteger m = 0;
		for (NSUInteger j = 0; j < n; j++) {
			if (key[j] == key[i]) members[m++] = (NSInteger)j;
		}

		for (NSInteger a = 1; a < m; a++) {
			NSInteger v = members[a];
			NSInteger b = a - 1;
			while (b >= 0 && idx[members[b]] > idx[v]) { members[b + 1] = members[b]; b--; }
			members[b + 1] = v;
		}

		NSInteger start = 0;
		for (NSInteger a = 1; a <= m; a++) {
			if (a == m || idx[members[a]] != idx[members[a - 1]] + 1) {
				for (NSInteger b = start; b < a; b++) runOf[members[b]] = nextRun;
				runLen[nextRun] = a - start;
				nextRun++;
				start = a;
			}
		}
	}
}

static void rygCompactRun(RYGArrangement *arr, const NSInteger *members, NSInteger m, BOOL vertical, NSInteger limit) {
	NSInteger *axis = vertical ? arr->row : arr->col;

	NSInteger alive = 0;
	for (NSInteger a = 0; a < m; a++) {
		if (arr->present[members[a]]) alive++;
	}
	if (alive == 0 || alive == m) return;

	NSInteger lo = axis[members[0]];
	NSInteger hi = axis[members[m - 1]];
	BOOL anchorLow = lo <= (limit - 1 - hi);

	NSInteger cursor = anchorLow ? lo : hi;
	for (NSInteger a = 0; a < m; a++) {
		NSInteger i = members[anchorLow ? a : m - 1 - a];
		if (!arr->present[i]) continue;
		axis[i] = cursor;
		cursor += anchorLow ? 1 : -1;
	}
}

// Only touching buttons close a hidden neighbour's gap; anything further apart keeps its slot.
static void rygCompactArrangement(RYGArrangement *arr, NSInteger cols, NSInteger rows) {
	NSUInteger n = arr->count;
	NSInteger vRun[RYG_MAX_LAYOUT_IDS], hRun[RYG_MAX_LAYOUT_IDS];
	NSInteger vLen[RYG_MAX_LAYOUT_IDS], hLen[RYG_MAX_LAYOUT_IDS];

	rygBuildRuns(arr->col, arr->row, n, vRun, vLen);
	rygBuildRuns(arr->row, arr->col, n, hRun, hLen);

	for (NSInteger pass = 0; pass < 2; pass++) {
		BOOL vertical = (pass == 0);
		const NSInteger *runOf = vertical ? vRun : hRun;
		const NSInteger *runLen = vertical ? vLen : hLen;
		const NSInteger *idx = vertical ? arr->row : arr->col;

		for (NSInteger r = 0; r < (NSInteger)n; r++) {
			NSInteger members[RYG_MAX_LAYOUT_IDS];
			NSInteger m = 0;
			BOOL owned = YES;

			for (NSUInteger i = 0; i < n; i++) {
				if (runOf[i] != r) continue;
				NSInteger mine = runLen[r];
				NSInteger other = vertical ? hLen[hRun[i]] : vLen[vRun[i]];
				if (mine < 2 || (vertical ? mine < other : mine <= other)) owned = NO;
				members[m++] = (NSInteger)i;
			}
			if (m < 2 || !owned) continue;

			for (NSInteger a = 1; a < m; a++) {
				NSInteger v = members[a];
				NSInteger b = a - 1;
				while (b >= 0 && idx[members[b]] > idx[v]) { members[b + 1] = members[b]; b--; }
				members[b + 1] = v;
			}

			rygCompactRun(arr, members, m, vertical, vertical ? rows : cols);
		}
	}
}

+ (NSDictionary<NSString *, NSValue *> *)resolvedPositionsForIDs:(NSArray<NSString *> *)ids inSize:(CGSize)size {
	if (size.width <= 0 || size.height <= 0 || !ids.count) return @{};

	CGFloat minStep = [self slotMinStepPoints];
	NSInteger colsR = rygColsForWidth(size.width, minStep);
	NSInteger rowsR = rygRowsForHeight(size.height, minStep);

	CGSize home = rygOverlaySafeSize();
	NSInteger colsE = rygColsForWidth(home.width, minStep);
	NSInteger rowsE = rygRowsForHeight(home.height, minStep);

	NSArray<NSString *> *allIDs = [self allIDs];
	RYGArrangement arr;
	arr.count = MIN(allIDs.count, (NSUInteger)RYG_MAX_LAYOUT_IDS);

	BOOL anyHidden = NO;
	for (NSUInteger i = 0; i < arr.count; i++) {
		RYGSlotRef ref = rygDeriveRef([self positionForID:allIDs[i]], colsE, rowsE, home, minStep);
		arr.col[i] = rygMapIndex(ref.col, colsE, colsR);
		arr.row[i] = rygMapIndex(ref.row, rowsE, rowsR);
		arr.present[i] = [ids containsObject:allIDs[i]];
		if (!arr.present[i]) anyHidden = YES;
	}

	if (anyHidden && [self autoCompactEnabled]) rygCompactArrangement(&arr, colsR, rowsR);

	NSInteger taken[RYG_MAX_LAYOUT_IDS];
	NSUInteger takenCount = 0;
	NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:ids.count];

	for (NSString *bid in ids) {
		NSUInteger slot = [allIDs indexOfObject:bid];
		NSInteger col, row;

		if (slot != NSNotFound && slot < arr.count) {
			col = arr.col[slot];
			row = arr.row[slot];
		} else {
			RYGSlotRef ref = rygDeriveRef([self positionForID:bid], colsE, rowsE, home, minStep);
			col = rygMapIndex(ref.col, colsE, colsR);
			row = rygMapIndex(ref.row, rowsE, rowsR);
		}

		if (rygSlotTaken(taken, takenCount, row * colsR + col)) {
			NSInteger dir = (col * 2 > colsR - 1) ? -1 : 1;
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

		if (takenCount < RYG_MAX_LAYOUT_IDS) taken[takenCount++] = row * colsR + col;
		out[bid] = [NSValue valueWithCGPoint:rygSlotNorm(col, row, colsR, rowsR, size, minStep)];
	}

	return out;
}

+ (CGPoint)slotAtColumn:(NSInteger)col row:(NSInteger)row {
	CGSize home = rygOverlaySafeSize();
	CGFloat minStep = [self slotMinStepPoints];
	NSInteger cols = rygColsForWidth(home.width, minStep);
	NSInteger rows = rygRowsForHeight(home.height, minStep);
	col = MIN(MAX(col, 0), cols - 1);
	row = MIN(MAX(row, 0), rows - 1);
	return rygSlotNorm(col, row, cols, rows, home, minStep);
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

// Re-anchor by slot index: on a coarser grid two stored positions would round onto one slot.
+ (void)setSpacingPoints:(CGFloat)points {
	NSString *key = [self spacingPrefKey];
	if (!key) return;

	points = MIN(MAX(points, kMinGapPts), kMaxGapPts);
	if (fabs(points - [self spacingPoints]) < 0.01) return;

	CGSize home = rygOverlaySafeSize();
	NSArray<NSString *> *ids = [self allIDs];
	NSUInteger n = MIN(ids.count, (NSUInteger)RYG_MAX_LAYOUT_IDS);

	CGFloat oldStep = [self slotMinStepPoints];
	NSInteger oldCols = rygColsForWidth(home.width, oldStep);
	NSInteger oldRows = rygRowsForHeight(home.height, oldStep);

	RYGSlotRef refs[RYG_MAX_LAYOUT_IDS];
	for (NSUInteger i = 0; i < n; i++) {
		refs[i] = rygDeriveRef([self positionForID:ids[i]], oldCols, oldRows, home, oldStep);
	}

	[RYGUtils setPref:@(points) forKey:key];

	CGFloat newStep = [self slotMinStepPoints];
	NSInteger cols = rygColsForWidth(home.width, newStep);
	NSInteger rows = rygRowsForHeight(home.height, newStep);

	for (NSUInteger i = 0; i < n; i++) {
		NSInteger col = rygMapIndex(refs[i].col, oldCols, cols);
		NSInteger row = rygMapIndex(refs[i].row, oldRows, rows);
		[self setPosition:rygSlotNorm(col, row, cols, rows, home, newStep) forID:ids[i]];
	}
}

+ (NSString *)autoCompactPrefKey {
	NSString *base = [self prefKey];
	return base.length ? [base stringByAppendingString:@"_auto_compact"] : nil;
}

+ (BOOL)autoCompactEnabled {
	NSString *key = [self autoCompactPrefKey];
	return key ? [RYGUtils getBoolPref:key] : NO;
}

+ (void)reset {
	[RYGUtils setPref:@{} forKey:[self prefKey]];
	NSString *spacing = [self spacingPrefKey];
	if (spacing) [RYGUtils setPref:@(kDefaultGapPts) forKey:spacing];
}

@end
