/*
 * SCIDevOptionsNativeInjector.xm
 * Ryukgram
 *
 * Injects a "Developer Options" row into the native Instagram settings.
 * Based on Instagram 15 validation report.
 */

#import "../Utils.h"
#import "SCIDogfoodingMainLauncher.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kRYDogInjectedSectionKey = &kRYDogInjectedSectionKey;
static const NSInteger kRYDogFloatingButtonTag = 0xD06F00F;

static BOOL RYDogEmployeeModeEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_employee_master"] || [SCIUtils getBoolPref:@"igt_employee_devoptions_gate"];
}

static void RYDogOpenDeveloperDogfood(UIViewController *presenter) {
    if (!presenter) return;
    NSLog(@"[RyukGram][DogfoodInjector] Opening native Dogfooding Settings through validated launcher");
    RYDogOpenMainFrom(presenter);
}

static UITableViewCell *RYDogDeveloperCell(UITableView *tableView) {
    static NSString *identifier = @"RYDogDeveloperCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.textLabel.text = @"Dogfood / Developer Options";
    cell.detailTextLabel.text = @"Native IGDogfoodingSettings entry point";
    if (@available(iOS 13.0, *)) {
        cell.imageView.image = [UIImage systemImageNamed:@"hammer.fill"];
    }
    return cell;
}

static NSInteger RYDogInjectedSection(id controller) {
    NSNumber *section = objc_getAssociatedObject(controller, kRYDogInjectedSectionKey);
    return section ? section.integerValue : NSIntegerMax;
}

@interface NSObject (RYDogDeveloperAction)
- (void)ryDogDeveloperButtonTapped:(id)sender;
@end

@implementation NSObject (RYDogDeveloperAction)
- (void)ryDogDeveloperButtonTapped:(id)sender {
    UIViewController *vc = [self isKindOfClass:UIViewController.class] ? (UIViewController *)self : nil;
    RYDogOpenDeveloperDogfood(vc);
}
@end

static void RYDogAttachFloatingButton(UIViewController *vc) {
    if (!vc || !vc.view || !RYDogEmployeeModeEnabled()) return;
    if ([vc.view viewWithTag:kRYDogFloatingButtonTag]) return;
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kRYDogFloatingButtonTag;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.layer.cornerRadius = 18.0;
    button.clipsToBounds = YES;
    button.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.88];
    [button setTitle:@"Dogfood" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    [button addTarget:vc action:@selector(ryDogDeveloperButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    [vc.view addSubview:button];
    
    UILayoutGuide *guide = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [button.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-14.0],
        [button.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-14.0],
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:108.0],
        [button.heightAnchor constraintEqualToConstant:36.0]
    ]];
}

%hook IGSettingsViewController

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger sections = %orig;
    if (RYDogEmployeeModeEnabled()) {
        objc_setAssociatedObject(self, kRYDogInjectedSectionKey, @(sections), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return sections + 1;
    }
    objc_setAssociatedObject(self, kRYDogInjectedSectionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return sections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (RYDogEmployeeModeEnabled() && section == RYDogInjectedSection(self)) return 1;
    return %orig;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (RYDogEmployeeModeEnabled() && indexPath.section == RYDogInjectedSection(self)) {
        return RYDogDeveloperCell(tableView);
    }
    return %orig;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (RYDogEmployeeModeEnabled() && section == RYDogInjectedSection(self)) return @"Internal";
    return %orig;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (RYDogEmployeeModeEnabled() && indexPath.section == RYDogInjectedSection(self)) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        RYDogOpenDeveloperDogfood((UIViewController *)self);
        return;
    }
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        UITableView *tableView = nil;
        id obj = (id)self;
        SEL tableViewSel = @selector(tableView);
        if ([obj respondsToSelector:tableViewSel]) {
            tableView = ((UITableView *(*)(id, SEL))objc_msgSend)(obj, tableViewSel);
        }
        [tableView reloadData];
    } @catch (__unused id e) {
    }
}

%end

%hook IGProfileMenuViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RYDogAttachFloatingButton((UIViewController *)self);
}
%end

%hook IGProfileMoreOptionsViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RYDogAttachFloatingButton((UIViewController *)self);
}
%end

%ctor {
    NSLog(@"[RyukGram][DogfoodInjector] loaded. employeeMode=%d", RYDogEmployeeModeEnabled());
}
