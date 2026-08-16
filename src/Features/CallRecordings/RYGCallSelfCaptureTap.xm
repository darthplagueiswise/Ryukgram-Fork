#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "RYGCallSelfCaptureTap.h"
#import "RYGCallSelfVideoTap.h"
#import "RYGCallGridCompositor.h"
#import "RYGCallRecordingGate.h"
#import "../../Utils.h"

// Self-camera capture for the grid. IG stops VT-encoding your camera in group calls,
// but its AVCapture session keeps delivering. The webrtc capturer class name is
// stripped, so we find it behaviourally via -setSampleBufferDelegate:queue: (stable
// Apple API) and hook only the active capturer's captureOutput, passing through.

static SEL gOutSel;   // captureOutput:didOutputSampleBuffer:fromConnection:
static NSMutableDictionary<NSNumber *, NSValue *> *gOrig;   // hooked capturer Class -> original IMP
static NSMutableArray<Class> *gRecent;   // recent non-nil video-delegate classes, newest first
static const NSUInteger kRecentMax = 4;

static IMP origFor(id obj) {
	for (Class c = object_getClass(obj); c; c = class_getSuperclass(c)) {
		NSValue *v = gOrig[@((uintptr_t)(__bridge void *)c)];
		if (v) return (IMP)[v pointerValue];
	}
	return NULL;
}

static void ryg_didOutput(id self, SEL _cmd, id output, CMSampleBufferRef sample, id connection) {
	// Feed from whichever capturer is live — IG switches camera pipelines mid-call.
	if (sample && [RYGCallSelfVideoTap groupModeActive] && [RYGCallGridCompositor isActive]) {
		CVImageBufferRef pb = CMSampleBufferGetImageBuffer(sample);
		if (pb) [RYGCallGridCompositor addFrame:pb forKey:[RYGCallSelfVideoTap selfTileKey] isSelf:YES];
	}
	IMP orig = origFor(self);
	if (orig) ((void (*)(id, SEL, id, CMSampleBufferRef, id))orig)(self, _cmd, output, sample, connection);
}

static void hookCapturer(Class c) {
	if (!c) return;
	NSNumber *k = @((uintptr_t)(__bridge void *)c);
	if (gOrig[k]) return;
	if (![c instancesRespondToSelector:gOutSel]) return;
	IMP old = NULL;
	MSHookMessageEx(c, gOutSel, (IMP)ryg_didOutput, &old);
	gOrig[k] = [NSValue valueWithPointer:(const void *)(old ?: NULL)];
}

static void (*orig_setDelegate)(id, SEL, id, dispatch_queue_t);
static void ryg_setDelegate(id self, SEL _cmd, id delegate, dispatch_queue_t queue) {
	if (delegate) {
		Class c = object_getClass(delegate);
		@synchronized (gRecent) {
			[gRecent removeObject:c];
			[gRecent insertObject:c atIndex:0];
			while (gRecent.count > kRecentMax) [gRecent removeLastObject];
		}
		if ([RYGCallGridCompositor isActive]) hookCapturer(c);   // camera came up mid-recording
	}
	orig_setDelegate(self, _cmd, delegate, queue);
}

@implementation RYGCallSelfCaptureTap
+ (void)armForCall {
	@synchronized (gRecent) { for (Class c in gRecent) hookCapturer(c); }   // whichever camera pipeline is live when recording begins
}
@end

%ctor {
	if (!RYGCallRecordingEnabled()) return;
	gOutSel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
	gOrig = [NSMutableDictionary dictionary];
	gRecent = [NSMutableArray array];
	MSHookMessageEx([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:),
					(IMP)ryg_setDelegate, (IMP *)&orig_setDelegate);
}
