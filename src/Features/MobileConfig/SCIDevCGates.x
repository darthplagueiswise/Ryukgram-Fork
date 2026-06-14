// SCIDevCGates.x — C-gate force overrides disabled by design.
//
// The previous implementation fishhooked imported MobileConfig / EasyGating /
// Sessioned / MCI C functions. Those functions are on IG/FBShared hot paths.
// Even with raw ABI-safe replacements, forcing them means every checked gate runs
// through RyukGram. That conflicts with the stability rule for this branch.
//
// Keep this file as a build-time tombstone so the tweak does not silently regain
// hot-path C hooks. Functional experimental surfaces must use confirmed ObjC/Swift
// hooks, confirmed exported symbols, or native dogfood/internal entry points.
// Dex/discovery output remains observe-only unless a non-hot-path method/gate is
// confirmed for a specific feature.

%ctor {
	// Intentionally no-op. Do not rebind_symbols() MobileConfig/EasyGating C gates here.
}
