#import "SCISetting.h"

@interface SCISetting ()

@property (nonatomic, readwrite) SCITableCell type;

- (instancetype)initWithType:(SCITableCell)type NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

static BOOL SCIIsWordmarkMenuCommand(NSDictionary *props) {
	return [props[@"defaultsKey"] isEqualToString:@"sci_ig_wordmark_variant"];
}

static NSString *SCIWordmarkDisplayTitleForValue(NSString *value, NSString *fallback) {
	if ([value isEqualToString:@"off"]) return SCILocalized(@"Default");
	if ([value isEqualToString:@"1a"]) return SCILocalized(@"Wordmark 1");
	if ([value isEqualToString:@"1a_alt"]) return SCILocalized(@"Wordmark 1A");
	if ([value isEqualToString:@"1b"]) return SCILocalized(@"Wordmark 2");
	if ([value isEqualToString:@"1b_alt"]) return SCILocalized(@"Wordmark 2A");
	return fallback ?: @"";
}

///

@implementation SCISetting

// MARK: - - initWithType

- (instancetype)initWithType:(SCITableCell)type {
	self = [super init];

	if (self) {
		self.type = type;
	}

	return self;
}


// MARK: - + staticCellWithTitle

+ (instancetype)staticCellWithTitle:(NSString *)title
						   subtitle:(NSString *)subtitle
							   icon:(nullable SCISymbol *)icon
{
	SCISetting *setting = [[self alloc] initWithType:SCITableCellStatic];

	setting.title = title;
	setting.subtitle = subtitle;
	setting.icon = icon;

	return setting;
}

// truncated content intentionally replaced only selector occurrence
