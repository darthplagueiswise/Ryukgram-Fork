#import <Foundation/Foundation.h>

// Absolute string for one format key ("short"/"medium"/…/"custom:<id>"). nil for "default"/unknown.
NSString *RYGDateStringForKey(NSDate *date, NSString *fmtKey, BOOL showSeconds);

// Compact relative ("now"/"5h"/"3d"/"2w"), no threshold gating.
NSString *RYGCompactRelativeDateString(NSDate *date);

// General date-format engine: honours feed_date_format + relative threshold / compact / combine.
// nil when the user left the format on "default" and no relative window applies.
NSString *RYGGeneralDateString(NSDate *date);
