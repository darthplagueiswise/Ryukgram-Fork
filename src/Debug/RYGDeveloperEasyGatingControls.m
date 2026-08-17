#import "RYGEasyGatingRuntime.h"

// Intentionally empty compatibility translation unit.
//
// The former implementation exposed two EasyGating C symbols as if each symbol
// were one Boolean gate and forced the entire function return value. Analysis of
// the supplied Instagram executable shows that
// EasyGatingGetBoolean_Internal_DoNotUseOrMock is a dispatcher: concrete gate
// IDs are passed in w1 (for example 0x139 and 0x0f0 at verified call sites), so
// forcing the symbol globally changes unrelated gates.
//
// Easy Gating is now implemented by RYGEasyGatingRuntime / RYGEasyGatingViewController:
// the exact imported C entry point is pass-through hooked once, native returns
// are observed per numeric gate ID, and overrides are applied only to an
// explicitly selected gate ID. The auth-data-context variant remains untouched
// until its argument contract is traced with the same confidence.
