// SCIMobileConfigEmployeeGate.x
//
// Compatibility translation unit. The former constructor hooked several
// unvalidated `getBool:` implementations before UIApplication became active,
// cached the master state forever and guessed that descriptor word 0 was an
// ObjC argument. Instagram 376 instead calls
// IGMobileConfigBooleanValueForInternalUse with the raw descriptor in x3.
//
// SCIEmployeeConsumers.x + SCICSymbolStub.m now own the single version-adaptive
// implementation: they resolve the reader and exact employee DATA descriptors
// from the running process, preserve x0-x7 when calling the original, and can
// clear persisted forces when the master is disabled or the ABI is absent.

#import <Foundation/Foundation.h>
