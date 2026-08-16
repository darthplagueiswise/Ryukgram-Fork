// RyukGram dynamic-coverage probe — macro surface. PERMANENT MODULE, DO NOT DELETE.
// Runtime analog of scripts/ig_symbol_diff.py: proves a hook path was actually
// taken on a live account (catches A/B gating / per-account rollouts the static
// diff can't). Gated by RYG_PROBE — off compiles every macro to nothing. Tags:
// "<feature>.<point>", scraped by gen_probe_manifest.py for the coverage report.
// Auto-imported via RYGPrefix.h.

#ifndef RYG_PROBE
#define RYG_PROBE 0
#endif

#import <Foundation/Foundation.h>

#if RYG_PROBE

#ifdef __cplusplus
extern "C" {
#endif

void RYGProbeHitImpl(NSString *tag, NSString * _Nullable detail);
void RYGProbeClassImpl(NSString *tag, NSString * _Nullable className);

#ifdef __cplusplus
}
#endif

#define RYGProbeHit(tag, ...)  RYGProbeHitImpl((tag), ([NSString stringWithFormat:__VA_ARGS__]))
#define RYGProbeOnce(tag, ...) do { static BOOL _rygProbeFired = NO; if (!_rygProbeFired) { _rygProbeFired = YES; RYGProbeHit((tag), __VA_ARGS__); } } while (0)
#define RYGProbeClass(tag, name) RYGProbeClassImpl((tag), (name))

#else

#define RYGProbeHit(tag, ...)  do {} while (0)
#define RYGProbeOnce(tag, ...) do {} while (0)
#define RYGProbeClass(tag, name) do {} while (0)

#endif
