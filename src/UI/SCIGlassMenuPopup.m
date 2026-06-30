#import "SCIGlassMenuPopup.h"
#import "SCIUIKit26LiquidGlass.h"
#import "../Utils.h"

static UIView *gSCIMenuOverlay = nil;
static void (^gSCIMenuOnPick)(UICommand *) = nil;

// Canvas fixo para todos os wordmarks: mesma convencao documentada em
// 01-liquidglass-uikit-ios26.md (RGWordmarkCanvasImage, 82x22pt). Cada PNG de
// origem tem padding transparente interno diferente, entao sem alpha-trim
// primeiro a imagem "encolhe" pra dentro do canvas com tamanhos visuais
// distintos (a 1a fica grande, a ultima pequena). Trim + fit-centralizado no
// MESMO canvas garante tamanho final identico pra todas.
static const CGFloat kSCIWordmarkCanvasW = 82.0;
static const CGFloat kSCIWordmarkCanvasH = 22.0;

static CGRect SCIMenuAlphaBounds(UIImage *image) {
	CGImageRef cg = image.CGImage;
	if (!cg) return CGRectZero;
	size_t width = CGImageGetWidth(cg);
	size_t height = CGImageGetHeight(cg);
	if (width == 0 || height == 0 || width > 4096 || height > 4096) return CGRectZero;
	size_t bpr = width * 4;
	NSMutableData *data = [NSMutableData dataWithLength:bpr * height];
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(data.mutableBytes, width, height, 8, bpr, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	if (cs) CGColorSpaceRelease(cs);
	if (!ctx) return CGRectZero;
	CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cg);
	CGContextRelease(ctx);
	const UInt8 *bytes = (const UInt8 *)data.bytes;
	size_t minX = width, minY = height, maxX = 0, maxY = 0;
	BOOL found = NO;
	for (size_t y = 0; y < height; y++) {
		const UInt8 *r = bytes + y * bpr;
		for (size_t x = 0; x < width; x++) {
			if (r[x * 4 + 3] <= 8) continue;
			found = YES;
			if (x < minX) minX = x;
			if (y < minY) minY = y;
			if (x > maxX) maxX = x;
			if (y > maxY) maxY = y;
		}
	}
	if (!found) return CGRectZero;
	return CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

// Recorta a margem transparente e desenha CENTRALIZADO num canvas fixo
// 82x22pt -- toda imagem resultante tem o MESMO CGSize final, entao todas as
// linhas do menu wordmark ficam com tamanho identico, sem sobra assimetrica.
static UIImage *SCIMenuWordmarkCanvasImage(UIImage *source) {
	if (!source) return nil;
	UIImage *trimmed = source;
	CGRect box = SCIMenuAlphaBounds(source);
	CGImageRef cg = source.CGImage;
	if (cg && !CGRectIsEmpty(box)) {
		CGImageRef cropped = CGImageCreateWithImageInRect(cg, box);
		if (cropped) {
			trimmed = [UIImage imageWithCGImage:cropped scale:source.scale orientation:source.imageOrientation];
			CGImageRelease(cropped);
		}
	}
	CGSize canvas = CGSizeMake(kSCIWordmarkCanvasW, kSCIWordmarkCanvasH);
	CGSize s2 = trimmed.size;
	if (s2.width <= 0 || s2.height <= 0) return [trimmed imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	CGFloat scale = MIN(canvas.width / s2.width, canvas.height / s2.height);
	CGSize target = CGSizeMake(floor(s2.width * scale), floor(s2.height * scale));
	CGRect rect = CGRectMake((canvas.width - target.width) / 2.0,
	                         (canvas.height - target.height) / 2.0,
	                         target.width, target.height);
	UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
	fmt.opaque = NO;
	fmt.scale = UIScreen.mainScreen.scale;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvas format:fmt];
	UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		[trimmed drawInRect:rect];
	}];
	return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#pragma mark - Wordmark: normaliza todas as imagens para a MESMA altura

static CGRect SCIMenuAlphaBounds(UIImage *image) {
	CGImageRef cg = image.CGImage;
	if (!cg) return CGRectZero;
	size_t width = CGImageGetWidth(cg);
	size_t height = CGImageGetHeight(cg);
	if (width == 0 || height == 0 || width > 4096 || height > 4096) return CGRectZero;
	size_t bpr = width * 4;
	NSMutableData *data = [NSMutableData dataWithLength:bpr * height];
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(data.mutableBytes, width, height, 8, bpr, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	if (cs) CGColorSpaceRelease(cs);
	if (!ctx) return CGRectZero;
	CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cg);
	CGContextRelease(ctx);
	const UInt8 *bytes = (const UInt8 *)data.bytes;
	size_t minX = width, minY = height, maxX = 0, maxY = 0;
	BOOL found = NO;
	for (size_t y = 0; y < height; y++) {
		const UInt8 *r = bytes + y * bpr;
		for (size_t x = 0; x < width; x++) {
			if (r[x * 4 + 3] <= 8) continue;
			found = YES;
			if (x < minX) minX = x;
			if (y < minY) minY = y;
			if (x > maxX) maxX = x;
			if (y > maxY) maxY = y;
		}
	}
	if (!found) return CGRectZero;
	return CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

// Recorta a margem transparente e escala para `targetH` de altura, preservando
// proporção. Assim todos os wordmarks ficam com a MESMA altura visual — o default
// não fica minúsculo nem o último gigante.
static UIImage *SCIMenuWordmarkImage(UIImage *src, CGFloat targetH) {
	if (!src) return nil;
	UIImage *trimmed = src;
	CGRect box = SCIMenuAlphaBounds(src);
	CGImageRef cg = src.CGImage;
	if (cg && !CGRectIsEmpty(box)) {
		CGImageRef cropped = CGImageCreateWithImageInRect(cg, box);
		if (cropped) {
			trimmed = [UIImage imageWithCGImage:cropped scale:src.scale orientation:src.imageOrientation];
			CGImageRelease(cropped);
		}
	}
	CGSize s = trimmed.size;
	if (s.height <= 0.0 || s.width <= 0.0) return [trimmed imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	CGFloat scale = targetH / s.height;
	CGSize tgt = CGSizeMake(ceil(s.width * scale), ceil(s.height * scale));
	UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
	fmt.opaque = NO;
	fmt.scale = UIScreen.mainScreen.scale;
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:tgt format:fmt];
	UIImage *out = [r imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull c) {
		[trimmed drawInRect:CGRectMake(0, 0, tgt.width, tgt.height)];
	}];
	return [out imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#pragma mark - Linha

@interface SCIGlassMenuRow : UIControl
@property (nonatomic, strong) UICommand *command;
@end

@implementation SCIGlassMenuRow
@end

#pragma mark - Overlay (sabe descartar ao tocar fora do painel)

@interface SCIGlassMenuOverlay : UIView
@property (nonatomic, weak) UIView *panel;
@end

@implementation SCIGlassMenuOverlay
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	UITouch *t = touches.anyObject;
	CGPoint p = [t locationInView:self];
	if (self.panel && CGRectContainsPoint(self.panel.frame, p)) return; // toque no painel: ignora
	[SCIGlassMenuPopup dismiss];
}
@end

@implementation SCIGlassMenuPopup

#pragma mark Flatten

+ (NSArray<UICommand *> *)flattenMenu:(UIMenu *)menu {
	NSMutableArray<UICommand *> *out = [NSMutableArray array];
	for (UIMenuElement *el in menu.children) {
		if ([el isKindOfClass:UIMenu.class]) {
			[out addObjectsFromArray:[self flattenMenu:(UIMenu *)el]];
		} else if ([el isKindOfClass:UICommand.class]) {
			[out addObject:(UICommand *)el];
		}
	}
	return out;
}

+ (NSString *)valueForCommand:(UICommand *)cmd {
	NSDictionary *props = [cmd.propertyList isKindOfClass:NSDictionary.class] ? cmd.propertyList : nil;
	NSString *v = [props[@"value"] isKindOfClass:NSString.class] ? props[@"value"] : nil;
	return v ?: (cmd.title ?: @"");
}

#pragma mark Window

+ (UIWindow *)resolveWindowForView:(UIView *)view {
	UIWindow *window = view.window;
	if (window) return window;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;
		if (scene.activationState != UISceneActivationStateForegroundActive) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) return w;
		}
	}
	return nil;
}

#pragma mark Present

+ (void)presentMenu:(UIMenu *)menu
       currentValue:(NSString *)currentValue
           wordmark:(BOOL)wordmark
         sourceView:(UIView *)sourceView
             onPick:(void (^)(UICommand *))onPick {
	if (!menu || !sourceView) return;
	UIWindow *window = [self resolveWindowForView:sourceView];
	if (!window) return;

	NSArray<UICommand *> *commands = [self flattenMenu:menu];
	if (commands.count == 0) return;

	[self dismiss];
	gSCIMenuOnPick = [onPick copy];

	NSString *current = currentValue.length ? [currentValue copy] : nil;
	if (current.length == 0) {
		NSString *dkey = nil;
		for (UICommand *cmd in commands) {
			NSDictionary *props = [cmd.propertyList isKindOfClass:NSDictionary.class] ? cmd.propertyList : nil;
			NSString *k = [props[@"defaultsKey"] isKindOfClass:NSString.class] ? props[@"defaultsKey"] : nil;
			if (k.length) { dkey = k; break; }
		}
		if (dkey.length) current = [[NSUserDefaults standardUserDefaults] stringForKey:dkey];
	}
	if (current.length == 0) current = wordmark ? @"off" : @"";

	const CGFloat hPad = 16.0;
	const CGFloat checkW = 28.0;
	const CGFloat rowH = wordmark ? 58.0 : 46.0;
	const CGFloat hair = 1.0 / MAX(UIScreen.mainScreen.scale, 1.0);

	// Largura do painel.
	CGFloat panelW;
	if (wordmark) {
		panelW = hPad + checkW + kSCIWordmarkCanvasW + hPad;
	} else {
		CGFloat maxTitle = 0.0;
		UIFont *f = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
		for (UICommand *cmd in commands) {
			NSString *title = cmd.title ?: @"";
			CGFloat w = [title sizeWithAttributes:@{NSFontAttributeName:f}].width;
			if (w > maxTitle) maxTitle = w;
		}
		panelW = ceil(maxTitle) + checkW + hPad * 2.0 + 6.0;
		panelW = MAX(208.0, MIN(panelW, 300.0));
	}

	// Conteúdo (rows) num scroll view.
	CGFloat contentH = rowH * commands.count;
	UIView *content = [[UIView alloc] initWithFrame:CGRectMake(0, 0, panelW, contentH)];
	content.backgroundColor = UIColor.clearColor;

	for (NSUInteger i = 0; i < commands.count; i++) {
		UICommand *cmd = commands[i];
		NSString *value = [self valueForCommand:cmd];
		BOOL selected = [value isEqualToString:current];
		CGFloat y = rowH * i;

		SCIGlassMenuRow *row = [[SCIGlassMenuRow alloc] initWithFrame:CGRectMake(0, y, panelW, rowH)];
		row.command = cmd;
		row.backgroundColor = selected ? [UIColor colorWithWhite:1.0 alpha:0.12] : UIColor.clearColor;
		[row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];

		// Checkmark (coluna leading).
		if (selected) {
			UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]];
			check.tintColor = [SCIUtils SCIColor_Primary] ?: UIColor.labelColor;
			check.contentMode = UIViewContentModeScaleAspectFit;
			check.frame = CGRectMake(hPad, (rowH - 15.0) / 2.0, checkW - 8.0, 15.0);
			[row addSubview:check];
		}

		CGFloat bodyX = hPad + checkW;
		CGFloat bodyW = panelW - bodyX - hPad;

		if (wordmark && cmd.image) {
			UIImage *img = SCIMenuWordmarkImage(cmd.image, 24.0);
			CGSize tgt = img.size;
			CGFloat w = tgt.width, h = tgt.height;
			if (w > bodyW && w > 0) { CGFloat sc = bodyW / w; w = bodyW; h = h * sc; }
			UIImageView *iv = [[UIImageView alloc] initWithImage:img];
			iv.tintColor = UIColor.labelColor;
			iv.contentMode = UIViewContentModeScaleAspectFit;
			iv.frame = CGRectMake(bodyX, (rowH - h) / 2.0, w, h);
			[row addSubview:iv];
		} else {
			UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(bodyX, 0, bodyW, rowH)];
			label.text = cmd.title ?: @"";
			label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
			label.textColor = UIColor.labelColor;
			label.lineBreakMode = NSLineBreakByTruncatingTail;
			[row addSubview:label];
		}

		// Separador (entre linhas, alinhado ao conteúdo).
		if (i + 1 < commands.count) {
			UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(bodyX, rowH - hair, panelW - bodyX, hair)];
			sep.backgroundColor = [UIColor.separatorColor colorWithAlphaComponent:0.45];
			sep.userInteractionEnabled = NO;
			[row addSubview:sep];
		}

		[content addSubview:row];
	}

	// Painel SÓLIDO (sem glass/blur). O IG roda em UIDesignRequiresCompatibility,
	// então UIGlassEffect real não renderiza aqui e o que sobra é uma máscara cinza
	// translúcida que deixa o conteúdo de trás (toggles azuis) vazar. Fundo sólido
	// = limpo, sem vazamento.
	CGFloat maxPanelH = MIN(window.bounds.size.height * 0.6, 440.0);
	CGFloat panelH = MIN(contentH, maxPanelH);

	UIView *panel = [[UIView alloc] init];
	panel.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
		return tc.userInterfaceStyle == UIUserInterfaceStyleDark
			? [UIColor colorWithRed:0.17 green:0.17 blue:0.18 alpha:1.0]
			: [UIColor colorWithRed:0.96 green:0.96 blue:0.97 alpha:1.0];
	}];
	panel.layer.cornerRadius = 13.0;
	if ([panel.layer respondsToSelector:@selector(setCornerCurve:)]) panel.layer.cornerCurve = kCACornerCurveContinuous;
	panel.layer.masksToBounds = YES;
	panel.layer.borderWidth = 1.0 / MAX(UIScreen.mainScreen.scale, 1.0);
	panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;

	UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, panelW, panelH)];
	scroll.contentSize = CGSizeMake(panelW, contentH);
	scroll.showsVerticalScrollIndicator = (contentH > panelH);
	scroll.alwaysBounceVertical = (contentH > panelH);
	scroll.backgroundColor = UIColor.clearColor;
	[scroll addSubview:content];
	[panel addSubview:scroll];

	// Posicionamento ancorado ao sourceView.
	CGRect src = [sourceView convertRect:sourceView.bounds toView:window];
	UIEdgeInsets safe = window.safeAreaInsets;
	const CGFloat margin = 8.0;

	CGFloat px = src.origin.x + src.size.width - panelW; // alinha borda direita ao botão
	px = MAX(safe.left + margin, MIN(px, window.bounds.size.width - safe.right - margin - panelW));

	CGFloat belowY = CGRectGetMaxY(src) + 6.0;
	CGFloat py;
	if (belowY + panelH <= window.bounds.size.height - safe.bottom - margin) {
		py = belowY; // abaixo do botão
	} else {
		CGFloat aboveY = src.origin.y - 6.0 - panelH;
		if (aboveY >= safe.top + margin) {
			py = aboveY; // acima do botão
		} else {
			py = safe.top + margin; // não cabe: cola no topo seguro
			panelH = MIN(panelH, window.bounds.size.height - safe.bottom - margin - py);
			scroll.frame = CGRectMake(0, 0, panelW, panelH);
			scroll.showsVerticalScrollIndicator = YES;
			scroll.alwaysBounceVertical = YES;
		}
	}
	panel.frame = CGRectMake(floor(px), floor(py), panelW, panelH);

	// Overlay.
	SCIGlassMenuOverlay *overlay = [[SCIGlassMenuOverlay alloc] initWithFrame:window.bounds];
	overlay.backgroundColor = UIColor.clearColor;
	overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	overlay.panel = panel;
	[overlay addSubview:panel];
	[window addSubview:overlay];
	gSCIMenuOverlay = overlay;

	// Animação de entrada.
	overlay.alpha = 0.0;
	panel.transform = CGAffineTransformMakeScale(0.96, 0.96);
	[UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
		overlay.alpha = 1.0;
		panel.transform = CGAffineTransformIdentity;
	} completion:nil];

	UISelectionFeedbackGenerator *fb = [UISelectionFeedbackGenerator new];
	[fb selectionChanged];
}

+ (void)rowTapped:(SCIGlassMenuRow *)row {
	UICommand *cmd = row.command;
	void (^cb)(UICommand *) = gSCIMenuOnPick;
	UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[fb impactOccurred];
	[self dismiss];
	if (cb && cmd) cb(cmd);
}

+ (void)dismiss {
	UIView *overlay = gSCIMenuOverlay;
	gSCIMenuOverlay = nil;
	gSCIMenuOnPick = nil;
	if (!overlay) return;
	[UIView animateWithDuration:0.14 animations:^{
		overlay.alpha = 0.0;
	} completion:^(BOOL finished) {
		[overlay removeFromSuperview];
	}];
}

@end
