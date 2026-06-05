#import "SCIColorPicker.h"
#import "../Features/Theme/SCITheme.h"
#import <objc/runtime.h>

static const void *kSCIColorPickerKeyAssoc = &kSCIColorPickerKeyAssoc;
static const void *kSCIColorPickerOnChange = &kSCIColorPickerOnChange;

@interface SCIColorPickerProxy : NSObject <UIColorPickerViewControllerDelegate>
+ (instancetype)shared;
@end

@implementation SCIColorPickerProxy

+ (instancetype)shared {
	static SCIColorPickerProxy *p;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		p = [SCIColorPickerProxy new];
	});
	return p;
}

- (void)colorPickerViewController:(UIColorPickerViewController *)vc
				   didSelectColor:(UIColor *)color
					 continuously:(BOOL)continuously {
	NSString *key = objc_getAssociatedObject(vc, kSCIColorPickerKeyAssoc);
	if (key.length)
		[[NSUserDefaults standardUserDefaults] setObject:[SCITheme hexFromColor:color] forKey:key];

	void (^cb)(UIColor *) = objc_getAssociatedObject(vc, kSCIColorPickerOnChange);
	if (cb) cb([color colorWithAlphaComponent:1.0]);
}

@end

@implementation SCIColorPicker

+ (void)configureSheetForPicker:(UIColorPickerViewController *)vc {
	vc.modalPresentationStyle = UIModalPresentationPageSheet;
	vc.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	UISheetPresentationController *sheet = vc.sheetPresentationController;
	if (!sheet) return;

	UISheetPresentationControllerDetent *fit =
		[UISheetPresentationControllerDetent customDetentWithIdentifier:@"sci_color_picker_fit"
															   resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
		return context.maximumDetentValue * 0.62;
	}];

	sheet.detents = @[ fit, UISheetPresentationControllerDetent.largeDetent ];
	sheet.selectedDetentIdentifier = @"sci_color_picker_fit";
	sheet.prefersGrabberVisible = YES;
	sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
	sheet.preferredCornerRadius = 24.0;
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
	vc.delegate = [SCIColorPickerProxy shared];

	UIColor *saved = [SCITheme colorFromHex:[[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey]];
	vc.selectedColor = saved ?: defaultColor ?: UIColor.systemPinkColor;

	objc_setAssociatedObject(vc, kSCIColorPickerKeyAssoc, defaultsKey, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	if (onChange)
		objc_setAssociatedObject(vc, kSCIColorPickerOnChange, [onChange copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	[self configureSheetForPicker:vc];

	[presenter presentViewController:vc animated:YES completion:nil];
}

+ (UIView *)swatchViewForKey:(NSString *)defaultsKey defaultColor:(UIColor *)defaultColor {
	UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 28.0, 28.0)];
	swatch.layer.cornerRadius = 14.0;
	swatch.layer.masksToBounds = YES;
	swatch.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
	swatch.layer.borderColor = [UIColor colorWithWhite:0.55 alpha:0.45].CGColor;

	UIColor *saved = [SCITheme colorFromHex:[[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey]];
	swatch.backgroundColor = saved ?: defaultColor ?: UIColor.systemPinkColor;

	return swatch;
}

@end