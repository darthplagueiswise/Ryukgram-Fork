// Compatibility translation unit retained so older build manifests still find
// this path. SCICSymbolStub now feature-detects the reader and each DATA
// descriptor at the moment it is used. That is required for Instagram 376,
// where IGMobileConfigBooleanValueForInternalUse is present, while remaining a
// clean no-op on later builds where the reader was removed.
#import "SCICSymbolStub.h"
