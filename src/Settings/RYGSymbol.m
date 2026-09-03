#import "RYGSymbol.h"
#import "../UI/RYGIcon.h"
#import "../Localization/RYGLocalization.h"

@interface RYGSymbol ()

@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite, nullable) NSString *igName;
@property (nonatomic, copy, readwrite) UIColor *color;
@property (nonatomic, readwrite) CGFloat size;
@property (nonatomic, readwrite) UIImageSymbolWeight weight;

+ (instancetype)ryg_symbolWithName:(NSString *)name
                            igName:(nullable NSString *)igName
                             color:(nullable UIColor *)color
                              size:(CGFloat)size
                            weight:(UIImageSymbolWeight)weight;

@end

@implementation RYGSymbol

- (instancetype)init {
	self = [super init];
	if (self) {
		self.name = @"";
		self.color = [UIColor labelColor];
		self.weight = UIImageSymbolWeightRegular;
		self.size = 15.0;
	}
	return self;
}

- (UIImage *)image {
	// FB asset (explicit igName, else friendly map for self.name) sized
	// slightly larger than text so it reads at parity with SF symbols.
	NSString *fbName = self.igName.length ? self.igName : self.name;
	UIImage *fb = [RYGIcon fbImageNamed:fbName pointSize:(self.size > 0 ? self.size + 6.0 : 0)];
	if (fb) return fb;

	// SF with Dynamic-Type-aware config (settings cells scale with text size).
	UIImage *sym = [RYGIcon sfImageNamed:self.name];
	if (sym && self.size > 0) {
		UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleTitle1];
		cfg = [cfg configurationByApplyingConfiguration:
			   [UIImageSymbolConfiguration configurationWithPointSize:self.size weight:self.weight]];
		return [sym imageWithConfiguration:cfg];
	}
	if (sym) return sym;

	NSBundle *bundle = RYGLocalizationBundle();
	UIImage *bundled = bundle ? [UIImage imageNamed:self.name inBundle:bundle compatibleWithTraitCollection:nil] : nil;
	return [bundled imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// MARK: - Factories

+ (instancetype)ryg_symbolWithName:(NSString *)name
                            igName:(NSString *)igName
                             color:(UIColor *)color
                              size:(CGFloat)size
                            weight:(UIImageSymbolWeight)weight {
	RYGSymbol *s = [self new];
	s.name = name ?: @"";
	if (igName) s.igName = igName;
	if (color) s.color = color;
	if (size >= 0) s.size = size;
	s.weight = weight;
	return s;
}

+ (instancetype)symbolWithName:(NSString *)name {
	return [self ryg_symbolWithName:name igName:nil color:nil size:-1 weight:UIImageSymbolWeightRegular];
}

+ (instancetype)symbolWithName:(NSString *)name color:(UIColor *)color {
	return [self ryg_symbolWithName:name igName:nil color:color size:-1 weight:UIImageSymbolWeightRegular];
}

+ (instancetype)symbolWithName:(NSString *)name color:(UIColor *)color size:(CGFloat)size {
	return [self ryg_symbolWithName:name igName:nil color:color size:size weight:UIImageSymbolWeightRegular];
}

+ (instancetype)symbolWithName:(NSString *)name color:(UIColor *)color size:(CGFloat)size weight:(UIImageSymbolWeight)weight {
	return [self ryg_symbolWithName:name igName:nil color:color size:size weight:weight];
}

+ (instancetype)symbolWithIGName:(NSString *)igName fallback:(NSString *)name {
	return [self ryg_symbolWithName:name igName:igName color:nil size:-1 weight:UIImageSymbolWeightRegular];
}

+ (instancetype)symbolWithIGName:(NSString *)igName fallback:(NSString *)name color:(UIColor *)color {
	return [self ryg_symbolWithName:name igName:igName color:color size:-1 weight:UIImageSymbolWeightRegular];
}

+ (instancetype)symbolWithIGName:(NSString *)igName fallback:(NSString *)name color:(UIColor *)color size:(CGFloat)size {
	return [self ryg_symbolWithName:name igName:igName color:color size:size weight:UIImageSymbolWeightRegular];
}

@end
