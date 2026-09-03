#import "RYGCallPipLayoutViewController.h"
#import "../../Utils.h"

// A mock of the full-screen call video behind the draggable PiP chip.
@interface RYGCallLayoutMock : UIView
@end

@implementation RYGCallLayoutMock {
	UIImageView *_person;
	UILabel *_label;
}
- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	self.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
	_person = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.square.fill"]];
	_person.tintColor = [UIColor colorWithWhite:1.0 alpha:0.20];
	_person.contentMode = UIViewContentModeScaleAspectFit;
	[self addSubview:_person];
	_label = [UILabel new];
	_label.textColor = [UIColor colorWithWhite:1.0 alpha:0.45];
	_label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
	_label.textAlignment = NSTextAlignmentCenter;
	[self addSubview:_label];
	return self;
}
- (void)setFullLabel:(NSString *)t { _label.text = t; }
- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat s = MIN(self.bounds.size.width, self.bounds.size.height) * 0.4;
	_person.frame = CGRectMake((self.bounds.size.width - s) / 2, (self.bounds.size.height - s) / 2 - 14, s, s);
	_label.frame = CGRectMake(0, CGRectGetMaxY(_person.frame) + 6, self.bounds.size.width, 18);
}
@end

@implementation RYGCallPipLayoutViewController {
	RYGCallLayoutMock *_mock;
}

static CGPoint rygPipPoint(void) {
	double x = [RYGUtils getDoublePref:@"call_recordings_pip_x"]; if (x <= 0) x = 0.82;
	double y = [RYGUtils getDoublePref:@"call_recordings_pip_y"]; if (y <= 0) y = 0.82;
	return CGPointMake(x, y);
}

static RYGDragLayoutItem *rygPipItem(void) {
	NSString *sz = [RYGUtils getStringPref:@"call_recordings_pip_size"];
	CGFloat scale = [sz isEqualToString:@"small"] ? 0.24 : ([sz isEqualToString:@"large"] ? 0.42 : 0.33);
	// Size against the real screen width so the chip shows the true PiP proportion
	// on the canvas (the editor scales chips by canvas/screen).
	CGFloat refW = MIN(UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height);
	CGFloat w = scale * refW;
	RYGDragLayoutItem *item = [RYGDragLayoutItem itemWithIdentifier:@"pip"
															   icon:[UIImage systemImageNamed:@"video.fill"]
															  title:nil
														   position:rygPipPoint()];
	item.width = w;
	item.diameter = w / 0.5625;   // portrait 9:16 camera window
	item.cornerRadius = 14.0;
	return item;
}

- (instancetype)init {
	if (!(self = [super initWithItems:@[rygPipItem()]])) return nil;

	self.title = RYGLocalized(@"Camera position");
	self.snapMask = RYGDragLayoutSnapEdges | RYGDragLayoutSnapCenter;
	self.scalesItemsToCanvas = YES;
	self.canvasAspect = 9.0 / 16.0;
	self.placeableInsets = UIEdgeInsetsMake(0.02, 0.02, 0.02, 0.02);
	self.instructions = RYGLocalized(@"Drag your camera window to any corner or edge.");

	_mock = [RYGCallLayoutMock new];
	BOOL selfFull = [[RYGUtils getStringPref:@"call_recordings_pip_full"] isEqualToString:@"self"];
	[_mock setFullLabel:selfFull ? RYGLocalized(@"You (full screen)") : RYGLocalized(@"Them (full screen)")];
	self.backgroundContentView = _mock;

	self.onChange = ^(NSArray<RYGDragLayoutItem *> *items) {
		RYGDragLayoutItem *pip = items.firstObject;
		if (!pip) return;
		[RYGUtils setPref:@(pip.position.x) forKey:@"call_recordings_pip_x"];
		[RYGUtils setPref:@(pip.position.y) forKey:@"call_recordings_pip_y"];
	};

	__weak typeof(self) weakSelf = self;
	self.onReset = ^{
		[RYGUtils setPref:@(0.82) forKey:@"call_recordings_pip_x"];
		[RYGUtils setPref:@(0.82) forKey:@"call_recordings_pip_y"];
		[weakSelf applyItems:@[rygPipItem()]];
	};

	return self;
}

@end
