#import "RYGCallVideoTap.h"
#import <VideoToolbox/VideoToolbox.h>
#import "../../../modules/fishhook/fishhook.h"
#import "RYGCallGridCompositor.h"
#import "RYGCallRecordingGate.h"

typedef struct { VTDecompressionOutputCallback cb; void *ref; } RYGVTWrap;

static OSStatus (*orig_VTDecompressionSessionCreate)(CFAllocatorRef, CMVideoFormatDescriptionRef, CFDictionaryRef,
													 CFDictionaryRef, const VTDecompressionOutputCallbackRecord *, VTDecompressionSessionRef *);

static volatile int gGroupMode = 0;

static void ryg_vtOutput(void *ref, void *src, OSStatus status, VTDecodeInfoFlags flags,
						 CVImageBufferRef image, CMTime pts, CMTime dur) {
	RYGVTWrap *w = (RYGVTWrap *)ref;
	if (w && w->cb) w->cb(w->ref, src, status, flags, image, pts, dur);
	if (status == noErr && image && __atomic_load_n(&gGroupMode, __ATOMIC_RELAXED))
		[RYGCallGridCompositor addFrame:image forKey:w isSelf:NO];   // key by session → one tile per participant
}

static OSStatus ryg_VTDecompressionSessionCreate(CFAllocatorRef allocator, CMVideoFormatDescriptionRef fmt,
												 CFDictionaryRef spec, CFDictionaryRef bufAttrs,
												 const VTDecompressionOutputCallbackRecord *outputCallback,
												 VTDecompressionSessionRef *sessionOut) {
	if (outputCallback && outputCallback->decompressionOutputCallback) {
		RYGVTWrap *w = (RYGVTWrap *)malloc(sizeof(RYGVTWrap));
		w->cb = outputCallback->decompressionOutputCallback;
		w->ref = outputCallback->decompressionOutputRefCon;
		VTDecompressionOutputCallbackRecord rec = { ryg_vtOutput, w };
		return orig_VTDecompressionSessionCreate(allocator, fmt, spec, bufAttrs, &rec, sessionOut);
	}
	return orig_VTDecompressionSessionCreate(allocator, fmt, spec, bufAttrs, outputCallback, sessionOut);
}

@implementation RYGCallVideoTap

+ (void)load {
	if (!RYGCallRecordingEnabled()) return;
	struct rebinding r[] = {
		{ "VTDecompressionSessionCreate", (void *)ryg_VTDecompressionSessionCreate, (void **)&orig_VTDecompressionSessionCreate },
	};
	rebind_symbols(r, 1);
}

+ (void)setGroupMode:(BOOL)on { __atomic_store_n(&gGroupMode, on ? 1 : 0, __ATOMIC_SEQ_CST); }

@end
