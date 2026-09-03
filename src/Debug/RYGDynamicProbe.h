// RyukGram dynamic-coverage collector. PERMANENT MODULE, DO NOT DELETE.
// See RYGProbe.h for the macro surface and rationale.

#import <Foundation/Foundation.h>
#import "RYGProbe.h"

#if RYG_PROBE

#ifdef __cplusplus
extern "C" {
#endif

// Build the coverage report, NSLog it, and return the text. Auto-called ~8s
// after launch and on background.
NSString *RYGProbeDumpReport(void);
void RYGProbeRunClassSweep(void);
void RYGProbeResetSession(void);

#ifdef __cplusplus
}
#endif

#endif
