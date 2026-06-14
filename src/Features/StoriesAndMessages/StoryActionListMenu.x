// Mirrors the shared story-menu items (sciStoryMenuEntries) into IG's new story overflow menu —
// an IGActionListViewController inside a partial-modal sheet that some accounts get instead of
// the old IGDSMenu dropdown.
//
// Uses our own SCIMenuSection, not IG's IGActionListCustomViewSection: IG uses that class for its
// own rows and IGListKit keys sections by -diffIdentifier, so sharing the class collides and
// blanks IG's cell. Card metrics mirror the native IGActionListVerticalSectionActionCell.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "../../Utils.h"
#import "StoryMenuItems.h"

extern __weak UIViewController *sciActiveStoryViewerVC;

static const char kSCICachedSection = 0;
static const char kCtrlSection = 0;
static const CGFloat kRowHeight = 53;

static UIColor *sciGroupColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.17 green:0.19 blue:0.21 alpha:1.0]
            : [UIColor colorWithRed:0.95 green:0.95 blue:0.96 alpha:1.0];
    }];
}

// ---- one tappable row: leading icon + title ----
@interface SCIStoryMenuRow : UIControl
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@end

@implementation SCIStoryMenuRow
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 320, kRowHeight)])) {
        self.icon = [[UIImageView alloc] init];
        self.icon.translatesAutoresizingMaskIntoConstraints = NO;
        self.icon.contentMode = UIViewContentModeScaleAspectFit;
        self.icon.tintColor = UIColor.labelColor;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
        self.icon.image = [[UIImage systemImageNamed:symbol withConfiguration:cfg] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [self addSubview:self.icon];

        self.label = [[UILabel alloc] init];
        self.label.translatesAutoresizingMaskIntoConstraints = NO;
        self.label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        self.label.textColor = UIColor.labelColor;
        self.label.text = title;
        [self addSubview:self.label];

        [NSLayoutConstraint activateConstraints:@[
            [self.icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [self.icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.icon.widthAnchor constraintEqualToConstant:24],
            [self.icon.heightAnchor constraintEqualToConstant:24],
            [self.label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:60],
            [self.label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],
        ]];
        [self addTarget:self action:@selector(_tapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
- (void)_tapped { if (self.onTap) self.onTap(); }
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    self.backgroundColor = h ? [UIColor colorWithWhite:0.5 alpha:0.2] : UIColor.clearColor;
}
@end

// ---- grouped grey card holding the rows ----
@interface SCIGroupedMenuView : UIView
@property (nonatomic, strong) NSArray<SCIStoryMenuRow *> *rows;
@property (nonatomic, strong) NSMutableArray<UIView *> *seps;
@end

@implementation SCIGroupedMenuView
- (instancetype)initWithRows:(NSArray<SCIStoryMenuRow *> *)rows {
    if ((self = [super init])) {
        _rows = rows;
        _seps = [NSMutableArray array];
        self.backgroundColor = sciGroupColor();
        self.layer.cornerRadius = 12;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        for (NSUInteger i = 0; i < rows.count; i++) {
            [self addSubview:rows[i]];
            if (i < rows.count - 1) {
                UIView *sep = [[UIView alloc] init];
                sep.backgroundColor = UIColor.separatorColor;
                [self addSubview:sep];
                [_seps addObject:sep];
            }
        }
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    for (NSUInteger i = 0; i < _rows.count; i++) {
        _rows[i].frame = CGRectMake(0, i * kRowHeight, w, kRowHeight);
        if (i < _seps.count)
            _seps[i].frame = CGRectMake(20, (i + 1) * kRowHeight - 0.5, w - 20, 0.5);
    }
}
- (CGFloat)contentHeight { return _rows.count * kRowHeight; }
@end

// ---- our diffable section + runtime section controller ----
@interface SCIMenuSection : NSObject
@property (nonatomic, strong) SCIGroupedMenuView *card;
@property (nonatomic, strong) id controller;   // cached for a stable per-section controller
@end
@implementation SCIMenuSection
- (id<NSObject>)diffIdentifier { return @"sci_story_menu_section"; }
- (BOOL)isEqualToDiffableObject:(id)object { return [object isKindOfClass:[SCIMenuSection class]]; }
@end

// Built at runtime — IGListSectionController is in the IG binary, can't be subclassed at link time.
static SCIMenuSection *sciCtrlSection(id self) { return objc_getAssociatedObject(self, &kCtrlSection); }

static NSInteger sci_numberOfItems(id self, SEL _cmd) { return 1; }

static CGSize sci_sizeForItemAtIndex(id self, SEL _cmd, NSInteger index) {
    id ctx = ((id(*)(id, SEL))objc_msgSend)(self, @selector(collectionContext));
    // insetContainerSize = width minus the collection's content insets, matching native rows.
    CGFloat w = 0;
    if ([ctx respondsToSelector:@selector(insetContainerSize)])
        w = ((CGSize(*)(id, SEL))objc_msgSend)(ctx, @selector(insetContainerSize)).width;
    if (w <= 0)
        w = ((CGSize(*)(id, SEL))objc_msgSend)(ctx, @selector(containerSize)).width;
    return CGSizeMake(w, sciCtrlSection(self).card.contentHeight);
}

static id sci_cellForItemAtIndex(id self, SEL _cmd, NSInteger index) {
    id ctx = ((id(*)(id, SEL))objc_msgSend)(self, @selector(collectionContext));
    UICollectionViewCell *cell = ((id(*)(id, SEL, Class, id, NSInteger))objc_msgSend)(
        ctx, @selector(dequeueReusableCellOfClass:forSectionController:atIndex:),
        [UICollectionViewCell class], self, index);
    SCIGroupedMenuView *card = sciCtrlSection(self).card;
    if (card && card.superview != cell.contentView) {
        [card removeFromSuperview];
        card.frame = cell.contentView.bounds;
        card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [cell.contentView addSubview:card];
    }
    return cell;
}

static void sci_didUpdateToObject(id self, SEL _cmd, id object) {
    objc_setAssociatedObject(self, &kCtrlSection, object, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static Class sciSectionControllerClass(void) {
    static Class cls = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class base = NSClassFromString(@"IGListSectionController");
        if (!base) return;
        cls = objc_allocateClassPair(base, "SCIMenuSectionController", 0);
        class_addMethod(cls, @selector(numberOfItems), (IMP)sci_numberOfItems, "q@:");
        class_addMethod(cls, @selector(sizeForItemAtIndex:), (IMP)sci_sizeForItemAtIndex, "{CGSize=dd}@:q");
        class_addMethod(cls, @selector(cellForItemAtIndex:), (IMP)sci_cellForItemAtIndex, "@@:q");
        class_addMethod(cls, @selector(didUpdateToObject:), (IMP)sci_didUpdateToObject, "v@:@");
        objc_registerClassPair(cls);
    });
    return cls;
}

// Dismiss the partial-modal sheet hosting `vc`, then run `after`.
static void sciDismissSheetThen(UIViewController *vc, void (^after)(void)) {
    UIViewController *root = vc;
    while (root.parentViewController) root = root.parentViewController;
    UIViewController *toDismiss = root.presentingViewController ? root : vc;
    [toDismiss dismissViewControllerAnimated:YES completion:^{ if (after) after(); }];
}

static SCIStoryMenuRow *sciBuildRow(NSString *symbol, NSString *title, UIViewController *vc, void (^action)(void)) {
    SCIStoryMenuRow *row = [[SCIStoryMenuRow alloc] initWithSymbol:symbol title:title];
    __weak UIViewController *weakVC = vc;
    row.onTap = ^{ sciDismissSheetThen(weakVC, action); };
    return row;
}

// ---------------- hooks ----------------

static id (*orig_objects)(id, SEL, id);
static id new_objects(UIViewController *self, SEL _cmd, id adapter) {
    id objs = orig_objects(self, _cmd, adapter);
    UIViewController *storyVC = sciActiveStoryViewerVC;
    if (!storyVC || ![objs isKindOfClass:[NSArray class]]) return objs;

    // Build once per VC and reuse — IGListKit diffs sections by identity. Items come from the
    // shared sciStoryMenuEntries(), so this menu always matches the old 3-dot menu.
    SCIMenuSection *section = objc_getAssociatedObject(self, &kSCICachedSection);
    if (!section) {
        NSMutableArray<SCIStoryMenuRow *> *rows = [NSMutableArray array];
        for (SCIStoryMenuEntry *entry in sciStoryMenuEntries())
            [rows addObject:sciBuildRow(entry.symbol, entry.title, self, entry.handler)];
        if (rows.count == 0) return objs;
        section = [[SCIMenuSection alloc] init];
        section.card = [[SCIGroupedMenuView alloc] initWithRows:rows];
        objc_setAssociatedObject(self, &kSCICachedSection, section, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSMutableArray *out = [objs mutableCopy];
    [out addObject:section];
    return [out copy];
}

static id (*orig_secForObj)(id, SEL, id, id);
static id new_secForObj(UIViewController *self, SEL _cmd, id adapter, id object) {
    if ([object isKindOfClass:[SCIMenuSection class]]) {
        SCIMenuSection *s = object;
        if (!s.controller) {
            Class cc = sciSectionControllerClass();
            if (cc) s.controller = [[cc alloc] init];
        }
        if (s.controller) return s.controller;
    }
    return orig_secForObj(self, _cmd, adapter, object);
}

%ctor {
    Protocol *diffable = objc_getProtocol("IGListDiffable");
    if (diffable) class_addProtocol([SCIMenuSection class], diffable);

    Class cls = NSClassFromString(@"IGActionListViewController");
    if (!cls) return;
    SEL sObjs = @selector(objectsForListAdapter:);
    if (class_getInstanceMethod(cls, sObjs))
        MSHookMessageEx(cls, sObjs, (IMP)new_objects, (IMP *)&orig_objects);
    SEL sSec = @selector(listAdapter:sectionControllerForObject:);
    if (class_getInstanceMethod(cls, sSec))
        MSHookMessageEx(cls, sSec, (IMP)new_secForObj, (IMP *)&orig_secForObj);
}
