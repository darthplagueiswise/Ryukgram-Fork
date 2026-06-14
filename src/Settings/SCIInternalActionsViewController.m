#import "SCIInternalActionsViewController.h"
#import "../Features/Dogfooding/SCIInternalActions.h"
#import <objc/runtime.h>

@interface SCIActionToggleCell : UITableViewCell
@property (nonatomic, strong) SCIUIKit26GlassPanelView *panel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, copy) void (^onToggle)(BOOL on);
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on enabled:(BOOL)enabled;
@end

@implementation SCIActionToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _panel = [[SCIUIKit26GlassPanelView alloc] initWithRadius:16.0];
        _panel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_panel];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.numberOfLines = 2;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 2.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [_panel.contentView addSubview:stack];

        _toggle = [UISwitch new];
        _toggle.onTintColor = UIColor.systemBlueColor;
        _toggle.translatesAutoresizingMaskIntoConstraints = NO;
        [_toggle addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
        [_panel.contentView addSubview:_toggle];

        [_toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_toggle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        [NSLayoutConstraint activateConstraints:@[
            [_panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_panel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [stack.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:10.0],
            [stack.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:14.0],
            [stack.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor constant:-10.0],
            [_toggle.leadingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:12.0],
            [_toggle.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor constant:-14.0],
            [_toggle.centerYAnchor constraintEqualToAnchor:_panel.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)switchChanged { if (self.onToggle) self.onToggle(self.toggle.isOn); }
- (void)prepareForReuse { [super prepareForReuse]; self.onToggle = nil; }
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on enabled:(BOOL)enabled {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    [self.toggle setOn:on animated:NO];
    self.toggle.enabled = enabled;
    self.toggle.alpha = enabled ? 1.0 : 0.4;
}

@end

@interface SCIActionSegmentedCell : UITableViewCell
@property (nonatomic, strong) SCIUIKit26GlassPanelView *panel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISegmentedControl *segmented;
@property (nonatomic, copy) void (^onChange)(NSInteger idx);
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle segments:(NSArray<NSString *> *)segments selected:(NSInteger)selected;
@end

@implementation SCIActionSegmentedCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _panel = [[SCIUIKit26GlassPanelView alloc] initWithRadius:16.0];
        _panel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_panel];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.numberOfLines = 2;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _segmented = [[UISegmentedControl alloc] init];
        _segmented.translatesAutoresizingMaskIntoConstraints = NO;
        [_segmented addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel, _segmented]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 6.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [_panel.contentView addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [_panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_panel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [stack.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:10.0],
            [stack.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:14.0],
            [stack.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor constant:-14.0],
            [stack.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor constant:-10.0],
        ]];
    }
    return self;
}

- (void)segmentChanged { if (self.onChange) self.onChange(self.segmented.selectedSegmentIndex); }
- (void)prepareForReuse { [super prepareForReuse]; self.onChange = nil; }
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle segments:(NSArray<NSString *> *)segments selected:(NSInteger)selected {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    [self.segmented removeAllSegments];
    [segments enumerateObjectsUsingBlock:^(NSString *label, NSUInteger idx, __unused BOOL *stop) {
        [self.segmented insertSegmentWithTitle:label atIndex:idx animated:NO];
    }];
    if (selected >= 0 && selected < (NSInteger)segments.count) self.segmented.selectedSegmentIndex = selected;
}

@end

typedef NS_ENUM(NSInteger, SCIActionRowKind) {
    SCIActionRowStatus,
    SCIActionRowButton,
    SCIActionRowToggle,
    SCIActionRowSegmented,
};

@interface SCIActionRow : NSObject
@property (nonatomic, assign) SCIActionRowKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *badge;
@property (nonatomic, assign) BOOL emphasized;
@property (nonatomic, assign) BOOL on;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSArray<NSString *> *segments;
@property (nonatomic, assign) NSInteger selectedSegment;
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, copy) void (^onToggle)(BOOL on);
@property (nonatomic, copy) void (^onSegment)(NSInteger idx);
@end
@implementation SCIActionRow @end

@interface SCIInternalActionsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@end

@implementation SCIInternalActionsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Internal Actions";
    SCIUIKit26ConfigureViewController(self);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(rebuild)];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 76.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:SCIUIKit26ParamCell.class forCellReuseIdentifier:@"info"];
    [self.tableView registerClass:SCIActionToggleCell.class forCellReuseIdentifier:@"toggle"];
    [self.tableView registerClass:SCIActionSegmentedCell.class forCellReuseIdentifier:@"segment"];
    [self.tableView registerClass:SCIUIKit26SectionHeaderView.class forHeaderFooterViewReuseIdentifier:@"header"];
    [self.view addSubview:self.tableView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:g.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    SCIUIKit26ConfigureViewController(self);
    [self rebuild];
}

- (NSString *)sessionSummary:(id)session {
    if (!session) return @"Not seen yet. Open an IG account screen once and come back.";
    return [NSString stringWithFormat:@"Captured %@ %p", NSStringFromClass(object_getClass(session)), session];
}

- (void)rebuild {
    id session = [SCIInternalActions liveUserSession];
    BOOL hasSession = session != nil;
    __weak typeof(self) ws = self;
    NSMutableArray *sections = [NSMutableArray array];

    SCIActionRow *status = [SCIActionRow new];
    status.kind = SCIActionRowStatus;
    status.title = @"Live IGUserSession";
    status.subtitle = [self sessionSummary:session];
    status.badge = hasSession ? @"ready" : @"none";
    status.emphasized = hasSession;
    [sections addObject:@{@"title": @"Status", @"rows": @[status]}];

    SCIActionRow *employee = [SCIActionRow new];
    employee.kind = SCIActionRowToggle;
    employee.title = @"Force IG internal employee";
    employee.subtitle = @"Hooks IGFacebookUserInfo.isEmployee to return YES. Restart IG after changing.";
    employee.on = [SCIInternalActions forceInternalEmployeeEnabled];
    employee.enabled = YES;
    employee.onToggle = ^(BOOL on) {
        [SCIInternalActions setForceInternalEmployeeEnabled:on];
        [ws rebuild];
    };
    [sections addObject:@{@"title": @"IG-only rows", @"rows": @[employee]}];

    SCIActionRow *notes = [SCIActionRow new];
    notes.kind = SCIActionRowButton;
    notes.title = @"Open Notes Dogfooding";
    notes.subtitle = @"Calls the native IGDirectNotesDogfoodingSettings opener with the live IGUserSession.";
    notes.badge = hasSession ? @"open" : @"need session";
    notes.emphasized = hasSession;
    notes.onTap = ^{
        NSError *error = nil;
        if (![SCIInternalActions openNotesDogfoodSettings:&error]) [ws presentError:error title:@"Could not open Notes dogfood"];
    };
    [sections addObject:@{@"title": @"Native dogfood UIs", @"rows": @[notes]}];

    NSInteger state = [SCIInternalActions bloksForceExperienceState];
    SCIActionRow *bloks = [SCIActionRow new];
    bloks.kind = SCIActionRowSegmented;
    bloks.title = @"Bloks force experience";
    bloks.subtitle = @"Uses IGUserSession.autofillInternalSettings native setters.";
    bloks.segments = @[@"Force OFF", @"Force ON", @"Default"];
    bloks.selectedSegment = state == 1 ? 1 : (state == 0 ? 0 : 2);
    bloks.onSegment = ^(NSInteger idx) {
        NSInteger newState = idx == 1 ? 1 : (idx == 0 ? 0 : 2);
        NSError *error = nil;
        if (![SCIInternalActions setBloksForceExperienceState:newState error:&error]) [ws presentError:error title:@"Bloks setter failed"];
        [ws rebuild];
    };
    [sections addObject:@{@"title": @"Bloks experience", @"rows": @[bloks]}];

    SCIActionRow *prefetch = [SCIActionRow new];
    prefetch.kind = SCIActionRowToggle;
    prefetch.title = @"Bloks prefetch";
    prefetch.subtitle = @"setBloksPrefetchEnabledWithEnabled:";
    prefetch.on = [SCIInternalActions bloksPrefetchEnabled];
    prefetch.enabled = hasSession;
    prefetch.onToggle = ^(BOOL on) {
        NSError *error = nil;
        if (![SCIInternalActions setBloksPrefetchEnabled:on error:&error]) [ws presentError:error title:@"Prefetch setter failed"];
        [ws rebuild];
    };

    SCIActionRow *footer = [SCIActionRow new];
    footer.kind = SCIActionRowToggle;
    footer.title = @"Debug footer";
    footer.subtitle = @"setDebugFooterEnabledWithEnabled:";
    footer.on = [SCIInternalActions debugFooterEnabled];
    footer.enabled = hasSession;
    footer.onToggle = ^(BOOL on) {
        NSError *error = nil;
        if (![SCIInternalActions setDebugFooterEnabled:on error:&error]) [ws presentError:error title:@"Debug footer setter failed"];
        [ws rebuild];
    };
    [sections addObject:@{@"title": @"Debug toggles", @"rows": @[prefetch, footer]}];

    self.sections = sections;
    [self.tableView reloadData];
}

- (void)presentError:(NSError *)error title:(NSString *)title {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:error.localizedDescription ?: @"Unknown error."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"rows"] count]; }

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    SCIUIKit26SectionHeaderView *h = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"header"];
    [h configureWithTitle:self.sections[section][@"title"] subtitle:nil];
    return h;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 58.0; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIActionRow *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (row.kind == SCIActionRowToggle) {
        SCIActionToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"toggle" forIndexPath:indexPath];
	SCIUIKit26ConfigureTableCell(cell);
        [cell configureWithTitle:row.title subtitle:row.subtitle on:row.on enabled:row.enabled];
        cell.onToggle = row.onToggle;
        return cell;
    }
    if (row.kind == SCIActionRowSegmented) {
        SCIActionSegmentedCell *cell = [tableView dequeueReusableCellWithIdentifier:@"segment" forIndexPath:indexPath];
	SCIUIKit26ConfigureTableCell(cell);
        [cell configureWithTitle:row.title subtitle:row.subtitle segments:row.segments selected:row.selectedSegment];
        cell.onChange = row.onSegment;
        return cell;
    }
    SCIUIKit26ParamCell *cell = [tableView dequeueReusableCellWithIdentifier:@"info" forIndexPath:indexPath];
	SCIUIKit26ConfigureTableCell(cell);
    [cell configureWithTitle:row.title subtitle:row.subtitle badge:row.badge emphasized:row.emphasized];
    cell.accessoryType = row.kind == SCIActionRowButton ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SCIActionRow *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (row.kind == SCIActionRowButton && row.onTap) row.onTap();
}

@end
