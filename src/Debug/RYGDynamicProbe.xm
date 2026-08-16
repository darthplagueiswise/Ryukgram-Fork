// RyukGram dynamic-coverage collector. PERMANENT MODULE, DO NOT DELETE.
// See RYGProbe.h. Compiles to an empty TU when RYG_PROBE=0.

#import "RYGDynamicProbe.h"

#if RYG_PROBE

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#if __has_include("RYGDynamicProbeManifest.h")
#import "RYGDynamicProbeManifest.h"
#else
// Fallback until scripts/gen_probe_manifest.py has run once.
static const char *kRYGProbeExpectedTags[] = { 0 };
static const char *kRYGProbeClasses[] = { 0 };
#endif

#pragma mark - Session registry

typedef struct { NSUInteger count; NSString *lastDetail; } RYGProbeRec;

static NSMutableDictionary<NSString *, NSValue *> *sTags;
static NSMutableDictionary<NSString *, NSString *> *sClasses;
static NSMutableSet<NSString *> *sEverResolved;
static NSLock *sLock;
static BOOL sSweepDone;

__attribute__((constructor)) static void rygProbeInit(void) {
	sTags = [NSMutableDictionary dictionary];
	sClasses = [NSMutableDictionary dictionary];
	sEverResolved = [NSMutableSet set];
	sLock = [NSLock new];
}

static void rygRecord(NSString *tag, NSString *detail) {
	if (!tag.length) return;
	[sLock lock];
	NSValue *box = sTags[tag];
	RYGProbeRec *r = box ? (RYGProbeRec *)box.pointerValue : NULL;
	if (!r) {
		r = (RYGProbeRec *)calloc(1, sizeof(RYGProbeRec));
		sTags[tag] = [NSValue valueWithPointer:r];
	}
	r->count++;
	r->lastDetail = detail ?: @"";
	[sLock unlock];
}

#pragma mark - Public macro sinks

void RYGProbeHitImpl(NSString *tag, NSString *detail) {
	rygRecord(tag, detail);
	NSString *line = detail.length ? [NSString stringWithFormat:@"HIT %@ — %@", tag, detail]
								   : [NSString stringWithFormat:@"HIT %@", tag];
	NSLog(@"[RyukGram][Probe] %@", line);
}

void RYGProbeClassImpl(NSString *tag, NSString *className) {
	if (!tag.length) return;
	[sLock lock];
	sClasses[tag] = className.length ? className : @"nil";
	[sLock unlock];
	RYGProbeHitImpl([@"class:" stringByAppendingString:tag], className ?: @"nil");
}

#pragma mark - Runtime class-resolution sweep

// _TtC<len><module><len><class> -> trailing <class> component.
static NSString *rygBareFromMangled(NSString *m) {
	if (![m hasPrefix:@"_TtC"]) return nil;
	NSScanner *sc = [NSScanner scannerWithString:[m substringFromIndex:4]];
	NSString *rest = sc.string; NSUInteger i = 0; NSString *last = nil;
	while (i < rest.length) {
		NSUInteger n = 0; BOOL got = NO;
		while (i < rest.length && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[rest characterAtIndex:i]]) {
			n = n * 10 + ([rest characterAtIndex:i] - '0'); i++; got = YES;
		}
		if (!got || i + n > rest.length) break;
		last = [rest substringWithRange:NSMakeRange(i, n)];
		i += n;
	}
	return last;
}

// Collapse bare / _TtC-mangled / Module.Class forms to one token so a bare
// fallback isn't flagged dead when the mangled form the feature uses resolved.
static NSString *rygClassToken(NSString *name) {
	NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
	if (dot.location != NSNotFound) return [name substringFromIndex:dot.location + 1];
	NSString *bare = rygBareFromMangled(name);
	return bare ?: name;
}

// Accumulates across the session — many Swift classes register lazily on first
// surface visit, so a class is only truly dead if it never resolves all session.
void RYGProbeRunClassSweep(void) {
	[sLock lock];
	NSUInteger total = 0, renamed = 0;
	for (int i = 0; kRYGProbeClasses[i] != 0; i++) {
		total++;
		NSString *name = [NSString stringWithUTF8String:kRYGProbeClasses[i]];
		if ([sEverResolved containsObject:name]) continue;
		if (NSClassFromString(name)) { [sEverResolved addObject:name]; continue; }
		NSString *bare = rygBareFromMangled(name);
		if (bare && NSClassFromString(bare)) {
			[sEverResolved addObject:name];
			renamed++;
			NSLog(@"[RyukGram][Probe] CLASS-RENAME %@ -> resolves as bare %@", name, bare);
		}
	}
	NSUInteger stillDead = total - sEverResolved.count;
	[sLock unlock];
	sSweepDone = YES;
	NSLog(@"[RyukGram][Probe] class sweep: %lu resolved so far, %lu still-nil, %lu renamed this pass (navigate more, then dump)",
		(unsigned long)sEverResolved.count, (unsigned long)stillDead, (unsigned long)renamed);
}

#pragma mark - Coverage report

NSString *RYGProbeDumpReport(void) {
	if (!sSweepDone) RYGProbeRunClassSweep();
	NSMutableString *o = [NSMutableString string];
	[o appendString:@"\n===== RyukGram dynamic-probe coverage =====\n"];

	[sLock lock];
	NSMutableSet *fired = [NSMutableSet setWithArray:sTags.allKeys];

	[o appendFormat:@"-- fired probes (%lu) --\n", (unsigned long)fired.count];
	NSArray *keys = [sTags.allKeys sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *k in keys) {
		RYGProbeRec *r = (RYGProbeRec *)sTags[k].pointerValue;
		[o appendFormat:@"  ✔ %-32@ x%-4lu last=%@\n", k, (unsigned long)r->count, r->lastDetail ?: @""];
	}

	NSMutableArray *never = [NSMutableArray array];
	for (int i = 0; kRYGProbeExpectedTags[i] != 0; i++) {
		NSString *t = [NSString stringWithUTF8String:kRYGProbeExpectedTags[i]];
		if (![fired containsObject:t]) [never addObject:t];
	}
	[never sortUsingSelector:@selector(compare:)];
	[o appendFormat:@"-- EXPECTED but never fired on this account (%lu) — the interesting column --\n", (unsigned long)never.count];
	for (NSString *t in never) [o appendFormat:@"  ✗ %@\n", t];
	if (!never.count) [o appendString:@"  (none — every known probe fired)\n"];

	// A class token counts as resolved if ANY of its forms (bare/mangled/dotted)
	// resolved — so a redundant bare fallback isn't reported as dead.
	NSMutableSet *resolvedTokens = [NSMutableSet set];
	for (NSString *r in sEverResolved) [resolvedTokens addObject:rygClassToken(r)];
	NSMutableArray *neverResolved = [NSMutableArray array];
	for (int i = 0; kRYGProbeClasses[i] != 0; i++) {
		NSString *name = [NSString stringWithUTF8String:kRYGProbeClasses[i]];
		if ([sEverResolved containsObject:name]) continue;
		if ([resolvedTokens containsObject:rygClassToken(name)]) continue;
		[neverResolved addObject:name];
	}
	[neverResolved sortUsingSelector:@selector(compare:)];
	[o appendFormat:@"-- classes with NO resolving form this session (%lu) — real breakage if you visited their surface --\n", (unsigned long)neverResolved.count];
	for (NSString *name in neverResolved) [o appendFormat:@"  ✗ %@\n", name];
	[o appendString:@"  (lazily-registered classes appear here until their screen is visited — navigate everywhere before trusting this list)\n"];

	[o appendFormat:@"-- resolved classes noted via RYGProbeClass this session (%lu) --\n", (unsigned long)sClasses.count];
	for (NSString *k in [sClasses.allKeys sortedArrayUsingSelector:@selector(compare:)])
		[o appendFormat:@"  %-28@ -> %@\n", k, sClasses[k]];
	[sLock unlock];

	[o appendString:@"===== end coverage =====\n"];
	NSLog(@"[RyukGram][Probe]%@", o);
	return o;
}

void RYGProbeResetSession(void) {
	[sLock lock];
	for (NSValue *v in sTags.allValues) { RYGProbeRec *r = (RYGProbeRec *)v.pointerValue; if (r) free(r); }
	[sTags removeAllObjects];
	[sClasses removeAllObjects];
	[sLock unlock];
}

#pragma mark - Auto triggers

__attribute__((constructor)) static void rygProbeSchedule(void) {
	// Re-sweep so lazily-registered classes drop off the dead list as you navigate.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
		RYGProbeRunClassSweep();
		static NSTimer *t;
		t = [NSTimer scheduledTimerWithTimeInterval:12.0 repeats:YES block:^(NSTimer *tm) { RYGProbeRunClassSweep(); }];
		(void)t;
	});
	[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
		object:nil queue:nil usingBlock:^(NSNotification *n) { RYGProbeDumpReport(); }];
}

#endif // RYG_PROBE
