#import "SCIDeletedMessagesChipBar.h"
#import "../../Gallery/SCIGalleryChip.h"

@interface SCIDeletedMessagesChipBar ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) NSArray<SCIGalleryChip *> *chips;
@end

@implementation SCIDeletedMessagesChipBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    self.backgroundColor = [UIColor clearColor];

    _scroll = [UIScrollView new];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.contentInset = UIEdgeInsetsMake(0, 14, 0, 14);
    [self addSubview:_scroll];

    _stack = [UIStackView new];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    _stack.axis = UILayoutConstraintAxisHorizontal;
    _stack.spacing = 8;
    _stack.alignment = UIStackViewAlignmentCenter;
    [_scroll addSubview:_stack];

    [NSLayoutConstraint activateConstraints:@[
        [_scroll.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scroll.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [_scroll.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
        [_stack.leadingAnchor   constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
        [_stack.trailingAnchor  constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
        [_stack.topAnchor       constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor   constant:6],
        [_stack.bottomAnchor    constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-6],
        [_stack.heightAnchor    constraintEqualToAnchor:_scroll.frameLayoutGuide.heightAnchor constant:-12],
    ]];
    return self;
}

- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 50); }

- (void)setItems:(NSArray<NSString *> *)titles symbols:(NSArray<NSString *> *)symbols {
    for (UIView *v in self.stack.arrangedSubviews) {
        [self.stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    NSMutableArray<SCIGalleryChip *> *chips = [NSMutableArray arrayWithCapacity:titles.count];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        NSString *sym = (i < (NSInteger)symbols.count) ? symbols[i] : nil;
        SCIGalleryChip *c = [SCIGalleryChip chipWithTitle:titles[i] symbol:sym];
        c.tag = i;
        [c addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.stack addArrangedSubview:c];
        [chips addObject:c];
    }
    self.chips = chips;
    [self refreshSelection];
}

- (void)setSelectedIndex:(NSInteger)idx {
    _selectedIndex = idx;
    [self refreshSelection];
}

- (void)refreshSelection {
    for (NSInteger i = 0; i < (NSInteger)self.chips.count; i++) {
        [self.chips[i] setOnState:(i == self.selectedIndex) animated:NO];
    }
}

- (void)chipTapped:(SCIGalleryChip *)c {
    if (c.tag == self.selectedIndex) return;
    self.selectedIndex = c.tag;
    [self refreshSelection];
    if ([self.delegate respondsToSelector:@selector(chipBar:didSelectIndex:)]) {
        [self.delegate chipBar:self didSelectIndex:c.tag];
    }
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
}

@end
