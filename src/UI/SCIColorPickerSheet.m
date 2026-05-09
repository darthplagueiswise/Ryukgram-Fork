#import "SCIColorPickerSheet.h"
#import "../Localization/SCILocalization.h"

@interface SCIColorPickerSheet () <UIColorPickerViewControllerDelegate>
@property (nonatomic, assign) SCIColorPickerSheetMode mode;
@property (nonatomic, strong) UIColor *startColor;
@property (nonatomic, strong, nullable) UIColor *endColor;
@property (nonatomic, copy) SCIColorPickerSheetApplyHandler applyHandler;

@property (nonatomic, assign) BOOL editingEndSlot;
@property (nonatomic, strong) UIColorPickerViewController *picker;
@property (nonatomic, strong) UIStackView *swatchRow;
@property (nonatomic, strong) UIButton *startSwatch;
@property (nonatomic, strong) UIButton *endSwatch;
@property (nonatomic, assign) CFTimeInterval lastApply;
@end

@implementation SCIColorPickerSheet

+ (instancetype)sheetWithMode:(SCIColorPickerSheetMode)mode
                   startColor:(UIColor *)start
                     endColor:(UIColor *)end
                 applyHandler:(SCIColorPickerSheetApplyHandler)handler {
    SCIColorPickerSheet *vc = [SCIColorPickerSheet new];
    vc.mode = mode;
    vc.startColor = start ?: [UIColor systemPinkColor];
    vc.endColor = end ?: [UIColor systemPurpleColor];
    vc.applyHandler = handler;
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self buildSwatchRow];
    [self buildPicker];
    [self layout];
    [self refreshSwatches];
    [self fireApply];
}

- (UIButton *)makeSwatch {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.layer.cornerRadius = 18;
    b.layer.masksToBounds = YES;
    b.layer.borderColor = UIColor.separatorColor.CGColor;
    b.layer.borderWidth = 2;
    [b.widthAnchor constraintEqualToConstant:36].active = YES;
    [b.heightAnchor constraintEqualToConstant:36].active = YES;
    return b;
}

- (UILabel *)makeLabel:(NSString *)t {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    l.textColor = UIColor.secondaryLabelColor;
    return l;
}

- (void)buildSwatchRow {
    _startSwatch = [self makeSwatch];
    _endSwatch = [self makeSwatch];
    [_startSwatch addTarget:self action:@selector(selectStartSlot) forControlEvents:UIControlEventTouchUpInside];
    [_endSwatch addTarget:self action:@selector(selectEndSlot) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *startCol = [[UIStackView alloc] initWithArrangedSubviews:@[[self makeLabel:SCILocalized(@"Start")], _startSwatch]];
    startCol.axis = UILayoutConstraintAxisVertical; startCol.alignment = UIStackViewAlignmentCenter; startCol.spacing = 4;
    UIStackView *endCol = [[UIStackView alloc] initWithArrangedSubviews:@[[self makeLabel:SCILocalized(@"End")], _endSwatch]];
    endCol.axis = UILayoutConstraintAxisVertical; endCol.alignment = UIStackViewAlignmentCenter; endCol.spacing = 4;

    _swatchRow = [[UIStackView alloc] initWithArrangedSubviews:@[startCol, endCol]];
    _swatchRow.axis = UILayoutConstraintAxisHorizontal;
    _swatchRow.alignment = UIStackViewAlignmentCenter;
    _swatchRow.spacing = 32;
    _swatchRow.translatesAutoresizingMaskIntoConstraints = NO;
    _swatchRow.hidden = (_mode != SCIColorPickerSheetModeGradient);
}

- (void)buildPicker {
    _picker = [[UIColorPickerViewController alloc] init];
    _picker.delegate = self;
    _picker.supportsAlpha = NO;
    _picker.selectedColor = _startColor;
    [_picker addObserver:self forKeyPath:@"selectedColor" options:NSKeyValueObservingOptionNew context:NULL];
    [self addChildViewController:_picker];
    _picker.view.translatesAutoresizingMaskIntoConstraints = NO;
}

- (void)layout {
    [self.view addSubview:_swatchRow];
    [self.view addSubview:_picker.view];
    [_picker didMoveToParentViewController:self];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    if (_mode == SCIColorPickerSheetModeGradient) {
        [NSLayoutConstraint activateConstraints:@[
            [_swatchRow.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],
            [_swatchRow.centerXAnchor constraintEqualToAnchor:g.centerXAnchor],
            [_picker.view.topAnchor constraintEqualToAnchor:_swatchRow.bottomAnchor constant:8],
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [_picker.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        ]];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_picker.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_picker.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_picker.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)refreshSwatches {
    _startSwatch.backgroundColor = _startColor;
    _endSwatch.backgroundColor = _endColor;
    _startSwatch.layer.borderColor = (_editingEndSlot ? UIColor.separatorColor : UIColor.labelColor).CGColor;
    _endSwatch.layer.borderColor   = (_editingEndSlot ? UIColor.labelColor   : UIColor.separatorColor).CGColor;
    _startSwatch.layer.borderWidth = _editingEndSlot ? 2 : 3;
    _endSwatch.layer.borderWidth   = _editingEndSlot ? 3 : 2;
}

- (void)selectStartSlot { _editingEndSlot = NO;  _picker.selectedColor = _startColor; [self refreshSwatches]; }
- (void)selectEndSlot   { _editingEndSlot = YES; _picker.selectedColor = _endColor;   [self refreshSwatches]; }

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (![keyPath isEqualToString:@"selectedColor"]) return;
    UIColor *c = change[NSKeyValueChangeNewKey];
    if (![c isKindOfClass:[UIColor class]]) return;
    UIColor *opaque = [c colorWithAlphaComponent:1.0];

    if (_mode == SCIColorPickerSheetModeGradient) {
        if (_editingEndSlot) _endColor = opaque; else _startColor = opaque;
    } else {
        _startColor = opaque;
    }
    [self refreshSwatches];
    [self fireApply];
}

- (void)fireApply {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - _lastApply < 0.033) return; // ~30 Hz throttle
    _lastApply = now;

    if (_applyHandler) {
        _applyHandler(_mode, _startColor, (_mode == SCIColorPickerSheetModeGradient) ? _endColor : nil);
    }
}

- (void)presentFromViewController:(UIViewController *)presenter {
    if (!presenter) return;
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *s = self.sheetPresentationController;
        s.detents = @[[UISheetPresentationControllerDetent mediumDetent],
                      [UISheetPresentationControllerDetent largeDetent]];
        s.prefersGrabberVisible = YES;
        s.preferredCornerRadius = 16.0;
    }
    [presenter presentViewController:self animated:YES completion:nil];
}

- (void)dealloc {
    @try { [_picker removeObserver:self forKeyPath:@"selectedColor"]; }
    @catch (__unused NSException *e) {}
}

@end
