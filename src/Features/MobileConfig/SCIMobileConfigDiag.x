// SCIMobileConfigDiag.x — MobileConfig read inventory (diagnostic, opt-in).
//
// Goal: map which MobileConfig boolean reads gate which features, WITHOUT the
// risk of forcing the universal native reader. The universal adapter only ever
// receives a numeric param specifier (no name), and dereferencing that struct
// from a hook is fragile. So instead of dumping specifier bytes, this records
// the CALLER return address of every read — each call site corresponds to one
// specific param, the return address is always valid (arm64, no PAC on the app
// binary, confirmed via otool), and offline we resolve each offset → feature by
// disassembling Instagram at 0x100000000 + offset.
//
// Safety:
//   • fishhook only (GOT rebind in-process; binary on disk untouched; no signing
//     issue — baseline §5).
//   • Each replacement calls the ORIGINAL and returns its value unchanged, so app
//     behavior is identical to not being hooked — this never forces anything.
//   • 8-argument pass-through: the MobileConfig boolean getters take ≤8 args, all
//     in x0–x7 (no stack args), so forwarding 8 register slots is ABI-exact and
//     the extra slots are ignored by callees that take fewer. Return is BOOL in w0.
//   • Recording is pure C (open-addressing table under os_unfair_lock): after the
//     table warms up, each call is a hash + compare + counter bump. No Objective-C
//     in the hot path, no NSUserDefaults reads per call (baseline §5).
//
// Output: Documents/sci_mobileconfig_adapter_diag.csv, flushed every few seconds.
// Columns: function, caller_offset, static_addr, observed_value, hit_count.
// Pull it off the device and send it back; the static_addr maps 1:1 to the
// disassembly so each row can be resolved to a concrete param/feature.
//
// Enable with the "MobileConfig read inventory (diagnostic)" toggle, then exercise
// the app (open the screens whose [ig-only]/[internal-only] features you want).

#import <Foundation/Foundation.h>
#import "../../Utils.h"
#include "../../../modules/fishhook/fishhook.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <os/lock.h>
#import <os/log.h>

// ── Pure-C dedup table keyed by (caller offset, function tag) ────────────────
#define SCI_MC_CAP 16384
typedef struct {
	uint64_t off;   // caller return address - main image base (slide-independent)
	uint32_t cnt;   // observed call count
	uint8_t  fn;    // which function (see sci_mc_fnname)
	uint8_t  val;   // last observed BOOL return
	uint8_t  used;
} sci_mc_entry;

static sci_mc_entry sci_mc_tab[SCI_MC_CAP];
static os_unfair_lock sci_mc_lock = OS_UNFAIR_LOCK_INIT;
static uintptr_t sci_mc_base = 0;

static uintptr_t sci_mc_main_base(void) {
	uint32_t n = _dyld_image_count();
	for (uint32_t i = 0; i < n; i++) {
		const struct mach_header *h = _dyld_get_image_header(i);
		if (h && h->filetype == MH_EXECUTE) return (uintptr_t)h;
	}
	return (uintptr_t)_dyld_get_image_header(0);
}

static void sci_mc_record(uint8_t fn, void *ra, bool val) {
	uintptr_t base = sci_mc_base;
	if (!base) return;
	uint64_t off = (uint64_t)((uintptr_t)ra - base);
	uint32_t h = (uint32_t)((((off ^ ((uint64_t)fn << 40)) * 2654435761ull) >> 16)) & (SCI_MC_CAP - 1);
	os_unfair_lock_lock(&sci_mc_lock);
	for (uint32_t i = 0; i < SCI_MC_CAP; i++) {
		uint32_t idx = (h + i) & (SCI_MC_CAP - 1);
		sci_mc_entry *e = &sci_mc_tab[idx];
		if (e->used && e->off == off && e->fn == fn) {
			if (e->cnt != 0xFFFFFFFFu) e->cnt++;
			e->val = val ? 1 : 0;
			break;
		}
		if (!e->used) {
			e->used = 1; e->off = off; e->fn = fn; e->cnt = 1; e->val = val ? 1 : 0;
			break;
		}
	}
	os_unfair_lock_unlock(&sci_mc_lock);
}

static const char *sci_mc_fnname(uint8_t fn) {
	switch (fn) {
		case 0: return "MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter";
		case 1: return "IGMobileConfigBooleanValueForInternalUse";
		case 2: return "MCIExperimentCacheGetMobileConfigBoolean";
		case 3: return "MCIExtensionExperimentCacheGetMobileConfigBoolean";
		case 4: return "MSGCSessionedMobileConfigGetBoolean";
		default: return "unknown";
	}
}

static void sci_mc_flush(void) {
	NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *dir = dirs.firstObject;
	if (!dir) return;
	NSString *path = [dir stringByAppendingPathComponent:@"sci_mobileconfig_adapter_diag.csv"];
	NSMutableString *csv = [NSMutableString stringWithString:@"function,caller_offset,static_addr,observed_value,hit_count\n"];
	os_unfair_lock_lock(&sci_mc_lock);
	for (uint32_t i = 0; i < SCI_MC_CAP; i++) {
		sci_mc_entry *e = &sci_mc_tab[i];
		if (!e->used) continue;
		[csv appendFormat:@"%s,0x%llx,0x%llx,%d,%u\n",
			sci_mc_fnname(e->fn), (unsigned long long)e->off,
			(unsigned long long)(0x100000000ull + e->off), (int)e->val, e->cnt];
	}
	os_unfair_lock_unlock(&sci_mc_lock);
	[csv writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// ── 8-arg pass-through replacements (ABI-exact for ≤8-register-arg callees) ──
typedef bool (*mc_fn8)(void *, void *, void *, void *, void *, void *, void *, void *);

#define MC_DIAG(name, tag) \
	static mc_fn8 orig_##name = NULL; \
	static bool diag_##name(void *a0, void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7) { \
		bool r = orig_##name ? orig_##name(a0, a1, a2, a3, a4, a5, a6, a7) : false; \
		sci_mc_record(tag, __builtin_return_address(0), r); \
		return r; \
	}

MC_DIAG(adapter,     0)
MC_DIAG(internaluse, 1)
MC_DIAG(mciexp,      2)
MC_DIAG(mciext,      3)
MC_DIAG(msgc,        4)

%ctor {
	@autoreleasepool {
		if (![SCIUtils getBoolPref:@"sci_mc_adapter_diag"]) return;
		sci_mc_base = sci_mc_main_base();

		struct rebinding r[5] = {
			{"MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter",  (void *)diag_adapter,     (void **)&orig_adapter},
			{"IGMobileConfigBooleanValueForInternalUse",        (void *)diag_internaluse, (void **)&orig_internaluse},
			{"MCIExperimentCacheGetMobileConfigBoolean",        (void *)diag_mciexp,      (void **)&orig_mciexp},
			{"MCIExtensionExperimentCacheGetMobileConfigBoolean",(void *)diag_mciext,     (void **)&orig_mciext},
			{"MSGCSessionedMobileConfigGetBoolean",             (void *)diag_msgc,        (void **)&orig_msgc},
		};
		rebind_symbols(r, 5);

		// Periodic flush. This is a UI-side timer (not a hook install), so it does
		// not violate the no-dispatch_after-for-hooks rule.
		dispatch_async(dispatch_get_main_queue(), ^{
			[NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(__unused NSTimer *t) {
				sci_mc_flush();
			}];
		});
		os_log(OS_LOG_DEFAULT, "[SCI] MobileConfig read-inventory diagnostic ON → Documents/sci_mobileconfig_adapter_diag.csv");
	}
}
