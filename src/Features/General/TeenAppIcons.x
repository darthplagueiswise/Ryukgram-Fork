#import "../../InstagramHeaders.h"
#import "../../Utils.h"

%hook IGImageWithAccessoryButton

- (void)didMoveToSuperview {
    %orig;
    [self addLongPressGestureRecognizer];
}

%new - (void)addLongPressGestureRecognizer {
    for (UIGestureRecognizer *g in self.gestureRecognizers) {
        if ([g isKindOfClass:UILongPressGestureRecognizer.class]) return;
    }
    UILongPressGestureRecognizer *gr = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleLongPress:)];
    [self addGestureRecognizer:gr];
}

%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    if (![RYGUtils getBoolPref:@"teen_app_icons"]) return;
    IGHomeFeedHeaderViewController *header = [RYGUtils nearestViewControllerForView:self];
    [header headerDidLongPressLogo:nil];
}

%end
