#import "RYGCallGridCompositor.h"
#import "../../Utils.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>

static const int kOutW = 720, kOutH = 1280;
static const CFTimeInterval kStaleAfter = 1.2; // tile with no frame this long → dropped
static const double kFPS = 20.0;

@interface RYGGridTile : NSObject
@property (nonatomic, assign) CVPixelBufferRef buffer;   // retained
@property (nonatomic, assign) CFTimeInterval updated;
@property (nonatomic, assign) NSInteger order;
@property (nonatomic, assign) BOOL isSelf;
@property (nonatomic, assign) CGFloat aspect;   // locked w/h from the first frame — IG varies frame size, so we don't
@end

@implementation RYGGridTile
- (void)setBuffer:(CVPixelBufferRef)buffer {
	if (_buffer == buffer) return;
	if (buffer) CVBufferRetain(buffer);
	if (_buffer) CVBufferRelease(_buffer);
	_buffer = buffer;
}
- (void)dealloc { if (_buffer) CVBufferRelease(_buffer); }
@end

@implementation RYGCallGridCompositor

static dispatch_queue_t gQ;
static NSMutableDictionary<NSValue *, RYGGridTile *> *gTiles;
static NSInteger gOrder = 0;
static volatile int gActive = 0;
static AVAssetWriter *gWriter;
static AVAssetWriterInput *gInput;
static AVAssetWriterInputPixelBufferAdaptor *gAdaptor;
static BOOL gStarted;
static CFTimeInterval gStartTime;
static uint64_t gFrames;
static CIContext *gCtx;
static dispatch_source_t gTimer;

static CVPixelBufferRef rygCopy(CVPixelBufferRef src) {
	size_t w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src);
	OSType pf = CVPixelBufferGetPixelFormatType(src);
	CVPixelBufferRef dst = NULL;
	NSDictionary *attrs = @{ (id)kCVPixelBufferIOSurfacePropertiesKey: @{} };
	if (CVPixelBufferCreate(kCFAllocatorDefault, w, h, pf, (__bridge CFDictionaryRef)attrs, &dst) != kCVReturnSuccess || !dst) return NULL;
	CVPixelBufferLockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
	CVPixelBufferLockBaseAddress(dst, 0);
	size_t planes = CVPixelBufferGetPlaneCount(src);
	if (planes == 0) {
		size_t sb = CVPixelBufferGetBytesPerRow(src), db = CVPixelBufferGetBytesPerRow(dst), bpr = MIN(sb, db);
		uint8_t *s = CVPixelBufferGetBaseAddress(src), *d = CVPixelBufferGetBaseAddress(dst);
		for (size_t y = 0; y < h; y++) memcpy(d + y * db, s + y * sb, bpr);
	} else {
		for (size_t p = 0; p < planes; p++) {
			size_t ph = CVPixelBufferGetHeightOfPlane(src, p);
			size_t sb = CVPixelBufferGetBytesPerRowOfPlane(src, p), db = CVPixelBufferGetBytesPerRowOfPlane(dst, p), bpr = MIN(sb, db);
			uint8_t *s = CVPixelBufferGetBaseAddressOfPlane(src, p), *d = CVPixelBufferGetBaseAddressOfPlane(dst, p);
			for (size_t y = 0; y < ph; y++) memcpy(d + y * db, s + y * sb, bpr);
		}
	}
	CVPixelBufferUnlockBaseAddress(dst, 0);
	CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
	return dst;
}

+ (BOOL)isActive { return gActive != 0; }
+ (BOOL)sawFrames { return gFrames > 0; }
+ (double)firstFrameWallTime { return gStarted ? gStartTime : 0.0; }

+ (BOOL)startToURL:(NSURL *)url {
	NSError *err = nil;
	AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:&err];
	if (!writer) { NSLog(@"[RyukGram][Grid] writer init failed: %@", err); return NO; }
	if (!gQ) gQ = dispatch_queue_create("com.ryukgram.callgrid", DISPATCH_QUEUE_SERIAL);

	dispatch_sync(gQ, ^{
		gWriter = writer; gTiles = [NSMutableDictionary dictionary]; gOrder = 0;
		gStarted = NO; gFrames = 0; gStartTime = 0;
		gCtx = [CIContext contextWithOptions:nil];
		gInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
			AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(kOutW), AVVideoHeightKey: @(kOutH),
		}];
		gInput.expectsMediaDataInRealTime = YES;
		gAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:gInput
																				  sourcePixelBufferAttributes:@{
			(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
			(id)kCVPixelBufferWidthKey: @(kOutW), (id)kCVPixelBufferHeightKey: @(kOutH),
		}];
		if ([gWriter canAddInput:gInput]) [gWriter addInput:gInput];
	});

	__atomic_store_n(&gActive, 1, __ATOMIC_SEQ_CST);

	gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQ);
	dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)(NSEC_PER_SEC / kFPS), NSEC_PER_SEC / 60);
	dispatch_source_set_event_handler(gTimer, ^{ [RYGCallGridCompositor tick]; });
	dispatch_resume(gTimer);
	return YES;
}

+ (void)addFrame:(CVImageBufferRef)image forKey:(void *)key isSelf:(BOOL)isSelf {
	if (!image || !__atomic_load_n(&gActive, __ATOMIC_RELAXED)) return;
	CVPixelBufferRef copy = rygCopy((CVPixelBufferRef)image);
	if (!copy) return;
	CFTimeInterval now = CACurrentMediaTime();
	NSValue *k = [NSValue valueWithPointer:key];
	dispatch_async(gQ, ^{
		if (!__atomic_load_n(&gActive, __ATOMIC_RELAXED)) { CVBufferRelease(copy); return; }
		RYGGridTile *tile = gTiles[k];
		if (!tile) { tile = [RYGGridTile new]; tile.order = isSelf ? -1 : gOrder++; tile.isSelf = isSelf; gTiles[k] = tile; }
		if (tile.aspect <= 0) {
			size_t w = CVPixelBufferGetWidth(copy), h = CVPixelBufferGetHeight(copy);
			if (h > 0) tile.aspect = (CGFloat)w / (CGFloat)h;   // lock once; ignore IG's per-frame resize after
		}
		tile.buffer = copy;   // retains
		tile.updated = now;
		CVBufferRelease(copy);
	});
}

static void rygFillGrid(CGRect *rects, const NSInteger *idxs, NSInteger count, CGRect area, NSInteger cols) {
	if (count <= 0) return;
	if (cols < 1) cols = 1;
	NSInteger rows = (NSInteger)ceil((double)count / cols);
	CGFloat cw = area.size.width / cols, ch = area.size.height / rows;
	for (NSInteger i = 0; i < count; i++) {
		NSInteger col = i % cols, row = i / cols;   // row 0 = top
		rects[idxs[i]] = CGRectMake(area.origin.x + col * cw,
									area.origin.y + area.size.height - (row + 1) * ch, cw, ch);
	}
}

+ (void)tick {
	if (!gWriter || !__atomic_load_n(&gActive, __ATOMIC_RELAXED)) return;
	CFTimeInterval now = CACurrentMediaTime();

	NSMutableArray<RYGGridTile *> *live = [NSMutableArray array];
	NSArray<NSValue *> *keys = gTiles.allKeys;
	for (NSValue *k in keys) {
		RYGGridTile *t = gTiles[k];
		if (now - t.updated > kStaleAfter) { [gTiles removeObjectForKey:k]; continue; }
		if (t.buffer) [live addObject:t];
	}
	if (live.count == 0) return;
	[live sortUsingComparator:^NSComparisonResult(RYGGridTile *a, RYGGridTile *b) {
		return a.order < b.order ? NSOrderedAscending : NSOrderedDescending;
	}];

	if (!gStarted) {
		if (![gWriter startWriting]) { NSLog(@"[RyukGram][Grid] startWriting failed: %@", gWriter.error); return; }
		[gWriter startSessionAtSourceTime:kCMTimeZero];
		gStartTime = now;
		gStarted = YES;
	}
	if (gWriter.status != AVAssetWriterStatusWriting || !gInput.isReadyForMoreMediaData) return;

	CVPixelBufferRef out = NULL;
	if (!gAdaptor.pixelBufferPool || CVPixelBufferPoolCreatePixelBuffer(NULL, gAdaptor.pixelBufferPool, &out) != kCVReturnSuccess || !out) return;

	NSInteger n = live.count;
	if (n > 16) n = 16;
	NSInteger selfIdx = -1;
	for (NSInteger i = 0; i < n; i++) if (live[i].isSelf) selfIdx = i;

	// Classify by shape: a wide tile (landscape / shared screen) reads best big on
	// top with everyone else in a strip below; all-portrait ("phone") tiles tile evenly.
	NSInteger wideIdx[16], normIdx[16], wc = 0, nc = 0;
	for (NSInteger i = 0; i < n; i++) {
		if (live[i].aspect >= 1.2) wideIdx[wc++] = i; else normIdx[nc++] = i;   // locked aspect — no wobble across the 1.2 threshold
	}

	CGRect rects[16];
	NSInteger drawOrder[16];
	for (NSInteger i = 0; i < n && i < 16; i++) drawOrder[i] = i;

	if (n == 1) {
		rects[0] = CGRectMake(0, 0, kOutW, kOutH);
	} else if (wc > 0) {
		// Wide screen(s) present → big top band, the rest along the bottom.
		if (nc == 0) {
			rygFillGrid(rects, wideIdx, wc, CGRectMake(0, 0, kOutW, kOutH), wc <= 1 ? 1 : 2);
		} else {
			CGFloat topH = kOutH * 0.62;
			rygFillGrid(rects, wideIdx, wc, CGRectMake(0, kOutH - topH, kOutW, topH), wc <= 1 ? 1 : 2);
			NSInteger bcols = nc <= 4 ? nc : (NSInteger)ceil(nc / 2.0);
			rygFillGrid(rects, normIdx, nc, CGRectMake(0, 0, kOutW, kOutH - topH), bcols);
		}
	} else if (n == 2 && selfIdx >= 0) {
		// One remote + you → PiP, driven by the same layout prefs as 1:1.
		BOOL selfMain = [[RYGUtils getStringPref:@"call_recordings_pip_full"] isEqualToString:@"self"];
		NSInteger other = selfIdx == 0 ? 1 : 0;
		NSInteger mainIdx = selfMain ? selfIdx : other;
		NSInteger pipIdx = selfMain ? other : selfIdx;
		rects[mainIdx] = CGRectMake(0, 0, kOutW, kOutH);
		double px = [RYGUtils getDoublePref:@"call_recordings_pip_x"]; if (px <= 0) px = 0.82;
		double py = [RYGUtils getDoublePref:@"call_recordings_pip_y"]; if (py <= 0) py = 0.82;
		NSString *sz = [RYGUtils getStringPref:@"call_recordings_pip_size"];
		double frac = [sz isEqualToString:@"small"] ? 0.24 : ([sz isEqualToString:@"large"] ? 0.42 : 0.33);
		CGFloat pw = frac * kOutW, ph = pw * ((CGFloat)kOutH / kOutW), m = kOutW * 0.02;
		CGFloat x = px * kOutW - pw / 2, yTop = py * kOutH - ph / 2;
		x = MAX(m, MIN(x, kOutW - pw - m));
		yTop = MAX(m, MIN(yTop, kOutH - ph - m));
		rects[pipIdx] = CGRectMake(x, kOutH - yTop - ph, pw, ph);
		drawOrder[0] = mainIdx; drawOrder[1] = pipIdx;   // PiP on top
	} else {
		// Wider cells suit call video better than a square grid: stack 2, 2-across up to 6, then 3.
		NSInteger cols = n <= 2 ? 1 : (n <= 6 ? 2 : 3);
		NSInteger rows = (NSInteger)ceil((double)n / cols);
		CGFloat cw = (CGFloat)kOutW / cols, ch = (CGFloat)kOutH / rows;
		for (NSInteger i = 0; i < n && i < 16; i++) {
			NSInteger col = i % cols, row = i / cols;
			rects[i] = CGRectMake(col * cw, kOutH - (row + 1) * ch, cw, ch);
		}
	}

	CIImage *acc = [CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0]];
	acc = [acc imageByCroppingToRect:CGRectMake(0, 0, kOutW, kOutH)];

	for (NSInteger j = 0; j < n && j < 16; j++) {
		NSInteger i = drawOrder[j];
		RYGGridTile *t = live[i];
		CGRect r = rects[i];
		CIImage *ci = [CIImage imageWithCVPixelBuffer:t.buffer];
		CGSize src = ci.extent.size;
		if (src.width < 1 || src.height < 1) continue;

		// Fixed display rect from the LOCKED aspect (never the wobbling frame size), so
		// the tile stays the same size every frame. Aspect-fit that box into the cell.
		CGFloat aspect = t.aspect > 0 ? t.aspect : src.width / src.height;
		CGFloat drW, drH;
		if (aspect >= r.size.width / r.size.height) { drW = r.size.width; drH = drW / aspect; }
		else { drH = r.size.height; drW = drH * aspect; }
		CGRect dr = CGRectMake(r.origin.x + (r.size.width - drW) / 2, r.origin.y + (r.size.height - drH) / 2, drW, drH);

		// Fill the fixed rect with the current frame (aspect-fill, center-crop overflow) —
		// resolution ramps just change crop, never the tile's size.
		CGFloat scale = MAX(dr.size.width / src.width, dr.size.height / src.height);
		ci = [ci imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
		CGFloat sw = src.width * scale, sh = src.height * scale;
		CGFloat tx = dr.origin.x + (dr.size.width - sw) / 2 - ci.extent.origin.x;
		CGFloat ty = dr.origin.y + (dr.size.height - sh) / 2 - ci.extent.origin.y;
		ci = [ci imageByApplyingTransform:CGAffineTransformMakeTranslation(tx, ty)];
		ci = [ci imageByCroppingToRect:dr];
		acc = [ci imageByCompositingOverImage:acc];
	}

	[gCtx render:acc toCVPixelBuffer:out];
	CMTime pts = CMTimeMakeWithSeconds(MAX(0.0, now - gStartTime), 1000);
	[gAdaptor appendPixelBuffer:out withPresentationTime:pts];
	gFrames++;
	CVBufferRelease(out);
}

+ (void)stopWithCompletion:(void (^)(BOOL))completion {
	__atomic_store_n(&gActive, 0, __ATOMIC_SEQ_CST);
	dispatch_async(gQ, ^{
		if (gTimer) { dispatch_source_cancel(gTimer); gTimer = nil; }
		AVAssetWriter *writer = gWriter;
		[gTiles removeAllObjects];
		if (!writer || !gStarted || writer.status != AVAssetWriterStatusWriting) {
			gWriter = nil; gInput = nil; gAdaptor = nil; completion(NO); return;
		}
		[gInput markAsFinished];
		[writer finishWritingWithCompletionHandler:^{
			BOOL ok = writer.status == AVAssetWriterStatusCompleted;
			if (!ok) NSLog(@"[RyukGram][Grid] finish failed: %@", writer.error);
			gWriter = nil; gInput = nil; gAdaptor = nil; completion(ok);
		}];
	});
}

@end
