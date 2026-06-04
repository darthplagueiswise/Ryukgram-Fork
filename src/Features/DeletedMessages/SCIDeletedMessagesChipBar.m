#import "SCIDeletedMessagesChipBar.h"
#import "../../Gallery/SCIGalleryChip.h"

@interface SCIDeletedMessagesChipBar ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) NSArray<SCIGalleryChip *> *chips;
@end

@implementation SCIDeletedMessagesChipBar

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.backgroundColor = UIColor.clearColor;

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
			[_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[_scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
			[_scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

			[_stack.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
			[_stack.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
			[_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:6],
			[_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-6],
			[_stack.heightAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.heightAnchor constant:-12],
		]];
	}
	return self;
}

- (CGSize)intrinsicContentSize {
	return CGSizeMake(UIViewNoIntrinsicMetric, 50);
}

#pragma mark - Items

- (void)setItems:(NSArray<NSString *> *)titles symbols:(NSArray<NSString *> *)symbols {
	for (UIView *v in self.stack.arrangedSubviews.copy) {
		[self.stack removeArrangedSubview:v];
		[v removeFromSuperview];
	}

	if (!titles.count) {
		self.chips = @[];
		_selectedIndex = NSNotFound;
		return;
	}

	NSMutableArray *chips = [NSMutableArray arrayWithCapacity:titles.count];

	for (NSUInteger i = 0; i < titles.count; i++) {
		NSString *symbol = i < symbols.count ? symbols[i] : nil;
		SCIGalleryChip *chip = [SCIGalleryChip chipWithTitle:titles[i] symbol:symbol];
		chip.tag = (NSInteger)i;
		[chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.stack addArrangedSubview:chip];
		[chips addObject:chip];
	}

	self.chips = chips;
	if (_selectedIndex < 0 || _selectedIndex >= (NSInteger)chips.count) _selectedIndex = 0;
	[self refreshSelectionAnimated:NO];
}

- (void)setSelectedIndex:(NSInteger)idx {
	if (_selectedIndex == idx) return;
	_selectedIndex = idx;
	[self refreshSelectionAnimated:NO];
}

- (void)refreshSelectionAnimated:(BOOL)animated {
	for (NSUInteger i = 0; i < self.chips.count; i++) {
		[self.chips[i] setOnState:((NSInteger)i == self.selectedIndex) animated:animated];
	}
}

#pragma mark - Actions

- (void)chipTapped:(SCIGalleryChip *)chip {
	NSInteger idx = chip.tag;
	if (idx == self.selectedIndex || idx < 0 || idx >= (NSInteger)self.chips.count) return;

	self.selectedIndex = idx;

	if ([self.delegate respondsToSelector:@selector(chipBar:didSelectIndex:)]) {
		[self.delegate chipBar:self didSelectIndex:idx];
	}

	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

@end