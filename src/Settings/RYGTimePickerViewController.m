#import "RYGTimePickerViewController.h"
#import "../UI/RYGPopupChrome.h"

@interface RYGTimePickerViewController ()
@property (nonatomic, copy) NSString *prefKey;
@property (nonatomic, copy) void (^onSave)(void);
@property (nonatomic, strong) UIDatePicker *picker;
@end

@implementation RYGTimePickerViewController

+ (void)presentForKey:(NSString *)key title:(NSString *)title from:(UIViewController *)presenter onSave:(void (^)(void))onSave {
    RYGTimePickerViewController *vc = [RYGTimePickerViewController new];
    vc.prefKey = key;
    vc.onSave = onSave;
    vc.title = title;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        sheet.prefersGrabberVisible = YES;
    }
    [presenter presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(save)];

    self.picker = [UIDatePicker new];
    self.picker.datePickerMode = UIDatePickerModeTime;
    self.picker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    self.picker.translatesAutoresizingMaskIntoConstraints = NO;
    self.picker.date = [self dateFromPref];
    [self.view addSubview:self.picker];
    [NSLayoutConstraint activateConstraints:@[
        [self.picker.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.picker.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (NSDate *)dateFromPref {
    NSString *raw = [NSUserDefaults.standardUserDefaults stringForKey:self.prefKey] ?: @"";
    NSArray<NSString *> *p = [raw componentsSeparatedByString:@":"];
    NSInteger h = 22, m = 0;
    if (p.count == 2) { h = p[0].integerValue; m = p[1].integerValue; }
    NSDate *d = [NSCalendar.currentCalendar dateBySettingHour:h minute:m second:0 ofDate:[NSDate date] options:0];
    return d ?: [NSDate date];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    NSDateComponents *c = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:self.picker.date];
    NSString *v = [NSString stringWithFormat:@"%02ld:%02ld", (long)c.hour, (long)c.minute];
    [NSUserDefaults.standardUserDefaults setObject:v forKey:self.prefKey];
    void (^cb)(void) = self.onSave;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) cb(); }];
}

@end
