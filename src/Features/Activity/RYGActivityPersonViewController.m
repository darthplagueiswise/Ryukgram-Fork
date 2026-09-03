#import "RYGActivityPersonViewController.h"
#import "RYGActivityConfig.h"

typedef NS_ENUM(NSInteger, RYGPersonSection) { RYGPSTypes = 0, RYGPSReset };

@implementation RYGActivityPersonViewController {
    NSString *_pk;          // nil = global defaults
    NSString *_username;
    RYGActivityType _notifyMask;
    RYGActivityType _logMask;
}

- (instancetype)initWithPK:(NSString *)pk username:(NSString *)username {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _pk = pk;
        _username = username;
        _notifyMask = pk ? ([RYGActivityConfig hasOverrideForPK:pk] ? [RYGActivityConfig overrideMaskForPK:pk] : [RYGActivityConfig globalNotifyMask]) : 0;
        _logMask    = pk ? ([RYGActivityConfig hasLogOverrideForPK:pk] ? [RYGActivityConfig overrideLogMaskForPK:pk] : [RYGActivityConfig globalLogMask]) : 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _pk ? (_username.length ? [@"@" stringByAppendingString:_username] : RYGLocalized(@"Person"))
                     : RYGLocalized(@"Everyone");
}

- (RYGActivityMode)modeForType:(RYGActivityType)type {
    if (!_pk) return [RYGActivityConfig globalModeForType:type];
    RYGActivityMode m = RYGActivityModeOff;
    if (_notifyMask & type) m |= RYGActivityModeNotify;
    if (_logMask & type)    m |= RYGActivityModeLog;
    return m;
}

- (void)setMode:(RYGActivityMode)mode forType:(RYGActivityType)type {
    if (!_pk) { [RYGActivityConfig setGlobalMode:mode forType:type]; return; }
    if (mode & RYGActivityModeNotify) _notifyMask |= type; else _notifyMask &= ~type;
    if (mode & RYGActivityModeLog)    _logMask |= type;    else _logMask &= ~type;
    [RYGActivityConfig setOverrideNotifyMask:_notifyMask logMask:_logMask forPK:_pk username:nil picURL:nil];
}

- (UIMenu *)menuForType:(RYGActivityType)type {
    RYGActivityMode current = [self modeForType:type];
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    for (NSNumber *n in RYGActivityConfig.allModes) {
        RYGActivityMode m = (RYGActivityMode)n.integerValue;
        UIAction *a = [UIAction actionWithTitle:[RYGActivityConfig titleForMode:m] image:nil identifier:nil
                                        handler:^(UIAction *x) { [self setMode:m forType:type]; }];
        a.state = (m == current) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:a];
    }
    return [UIMenu menuWithChildren:actions];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return _pk ? 2 : 1; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == RYGPSTypes) return RYGActivityConfig.allTypes.count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s != RYGPSTypes) return nil;
    return _pk ? RYGLocalized(@"For this person") : RYGLocalized(@"For everyone");
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s != RYGPSTypes) return nil;
    return RYGLocalized(@"Log only records silently. Notify only pings you without keeping it. Notify + log does both.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == RYGPSTypes) {
        RYGActivityType type = (RYGActivityType)[RYGActivityConfig.allTypes[ip.row] unsignedIntegerValue];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = [RYGActivityConfig titleForType:type];
        cell.imageView.image = [RYGActivityConfig imageForType:type];
        cell.imageView.tintColor = [RYGActivityConfig tintForType:type];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UIButton *picker = [UIButton buttonWithType:UIButtonTypeSystem];
        picker.showsMenuAsPrimaryAction = YES;
        picker.changesSelectionAsPrimaryAction = YES;
        picker.menu = [self menuForType:type];
        picker.tintColor = UIColor.secondaryLabelColor;
        [picker sizeToFit];
        cell.accessoryView = picker;
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = RYGLocalized(@"Reset to defaults");
    cell.textLabel.textColor = UIColor.systemRedColor;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == RYGPSReset) {
        [RYGActivityConfig clearOverrideForPK:_pk];
        [self.navigationController popViewControllerAnimated:YES];
    }
}

@end
