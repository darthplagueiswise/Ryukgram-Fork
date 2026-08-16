#import "RYGColorPicker.h"
#import "../Features/Theme/RYGTheme.h"
#import "RYGSheetDetent.h"
#import <objc/runtime.h>

static const void *kRYGColorPickerKeyAssoc = &kRYGColorPickerKeyAssoc;
static const void *kRYGColorPickerOnChange = &kRYGColorPickerOnChange;

@interface RYGColorPickerProxy : NSObject <UIColorPickerViewControllerDelegate>
+ (instancetype)shared;
@end

@implementation RYGColorPickerProxy

+ (instancetype)shared {
	static RYGColorPickerProxy *p;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		p = [RYGColorPickerProxy new];
	});
	return p;
}

- (void)colorPickerViewController:(UIColorPickerViewController *)vc
				   didSelectColor:(UIColor *)color
					 continuously:(BOOL)continuously {
	NSString *key = objc_getAssociatedObject(vc, kRYGColorPickerKeyAssoc);
	if (key.length)
		[[NSUserDefaults standardUserDefaults] setObject:[RYGTheme hexFromColor:color] forKey:key];

	void (^cb)(UIColor *) = objc_getAssociatedObject(vc, kRYGColorPickerOnChange);
	if (cb) cb([color colorWithAlphaComponent:1.0]);
}

@end

@implementation RYGColorPicker

+ (void)configureSheetForPicker:(UIColorPickerViewController *)vc {
	vc.modalPresentationStyle = UIModalPresentationPageSheet;

	// An opaque root view renders as a grey slab over the sheet; the sheet paints itself.
	vc.view.backgroundColor = UIColor.clearColor;

	UISheetPresentationController *sheet = vc.sheetPresentationController;
	if (!sheet) return;

	UISheetPresentationControllerDetent *fit =
		RYGCustomSheetDetent(@"ryg_color_picker_fit", ^CGFloat(CGFloat max) {
			CGFloat wanted = max * 0.65 + 5.0;
			return MIN(MAX(wanted, MIN(570.0, max * 0.79)), max * 0.79);
		});

	if (fit) {
		sheet.detents = @[ fit, UISheetPresentationControllerDetent.largeDetent ];
		sheet.selectedDetentIdentifier = @"ryg_color_picker_fit";
		sheet.largestUndimmedDetentIdentifier = @"ryg_color_picker_fit";
	} else {
		sheet.detents = @[
			UISheetPresentationControllerDetent.mediumDetent,
			UISheetPresentationControllerDetent.largeDetent
		];
		sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
		sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
	}

	sheet.prefersGrabberVisible = YES;
	sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;

	if ([sheet respondsToSelector:@selector(setPreferredCornerRadius:)]) {
		sheet.preferredCornerRadius = 42.0;
	}
}

+ (void)presentFrom:(UIViewController *)presenter
			  title:(NSString *)title
		defaultsKey:(NSString *)defaultsKey
	   defaultColor:(UIColor *)defaultColor
		   onChange:(void (^)(UIColor *))onChange {
	if (!presenter) return;

	UIColorPickerViewController *vc = [UIColorPickerViewController new];
	vc.title = title ?: @"";
	vc.supportsAlpha = NO;
	vc.delegate = [RYGColorPickerProxy shared];

	UIColor *saved = [RYGTheme colorFromHex:[[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey]];
	vc.selectedColor = saved ?: defaultColor ?: UIColor.systemPinkColor;

	objc_setAssociatedObject(vc, kRYGColorPickerKeyAssoc, defaultsKey, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	if (onChange)
		objc_setAssociatedObject(vc, kRYGColorPickerOnChange, [onChange copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	[self configureSheetForPicker:vc];

	[presenter presentViewController:vc animated:YES completion:nil];
}

+ (UIView *)swatchViewForKey:(NSString *)defaultsKey defaultColor:(UIColor *)defaultColor {
	UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 28.0, 28.0)];
	swatch.layer.cornerRadius = 14.0;
	swatch.layer.masksToBounds = YES;
	swatch.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
	swatch.layer.borderColor = [UIColor colorWithWhite:0.55 alpha:0.45].CGColor;

	UIColor *saved = [RYGTheme colorFromHex:[[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey]];
	swatch.backgroundColor = saved ?: defaultColor ?: UIColor.systemPinkColor;

	return swatch;
}

@end