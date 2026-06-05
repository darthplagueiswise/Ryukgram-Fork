// SCISymbolsBrowserViewController.m
// Reads Mach-O LC_SYMTAB at runtime to list ALL exported C symbols.
// WHY: _IGMobileConfigBooleanValueForInternalUse and EasyGating C functions
// live in the Mach-O symbol table (__LINKEDIT), not in ObjC runtime tables.
// FLEX uses class_copyMethodList / NSObject introspection — it can't see them.
// We parse LC_SYMTAB + __LINKEDIT in the already-mapped image directly.

#import "SCISymbolsBrowserViewController.h"
#import "GlassUI/SCIAdaptiveGlass.h"
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach-o/dyld.h>

// ---- Data model ----
@interface SCISymEntry : NSObject
@property NSString *name;
@property uintptr_t address;
@property BOOL isBoolGate; // heuristic: likely BOOL-returning gating function
@end
@implementation SCISymEntry @end

// ---- Table cell ----
@interface SCISymCell : UITableViewCell
@property (strong) SCIAdaptiveGlassPanelView *panel;
@property (strong) UILabel *nameLabel;
@property (strong) UILabel *addrLabel;
@end
@implementation SCISymCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    self = [super initWithStyle:s reuseIdentifier:r];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    _panel = [[SCIAdaptiveGlassPanelView alloc] initWithRadius:11];
    _panel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    _nameLabel.textColor = UIColor.labelColor;
    _nameLabel.numberOfLines = 2;
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _addrLabel = [UILabel new];
    _addrLabel.font = [UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightLight];
    _addrLabel.textColor = UIColor.secondaryLabelColor;
    _addrLabel.numberOfLines = 1;
    _addrLabel.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *stk = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _addrLabel]];
    stk.axis = UILayoutConstraintAxisVertical; stk.spacing = 1;
    stk.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel.contentView addSubview:stk];
    [self.contentView addSubview:_panel];
    [NSLayoutConstraint activateConstraints:@[
        [_panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3],
        [_panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [_panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
        [_panel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
        [stk.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:7],
        [stk.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:12],
        [stk.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor constant:-12],
        [stk.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor constant:-7],
    ]];
    return self;
}
@end

// ---- Symbol scanner ----
static NSArray<SCISymEntry *> *SCIScanSymbols(BOOL wantFBShared) {
    NSMutableArray<SCISymEntry *> *out = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t idx = 0; idx < count; idx++) {
        const char *imgName = _dyld_get_image_name(idx);
        if (!imgName) continue;
        BOOL match = wantFBShared
            ? (strstr(imgName, "/FBSharedFramework.framework/FBSharedFramework") != NULL)
            : (strstr(imgName, "/Instagram.app/Instagram") != NULL && !strstr(imgName, ".dylib"));
        if (!match) continue;

        const struct mach_header_64 *hdr = (const struct mach_header_64 *)_dyld_get_image_header(idx);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(idx);

        uintptr_t linkedit_vmaddr = 0, linkedit_fileoff = 0;
        const struct symtab_command *sc = NULL;
        const uint8_t *lc = (const uint8_t *)(hdr + 1);
        for (uint32_t j = 0; j < hdr->ncmds; j++) {
            const struct load_command *cmd = (const struct load_command *)lc;
            if (cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                if (strcmp(seg->segname, "__LINKEDIT") == 0) {
                    linkedit_vmaddr  = (uintptr_t)seg->vmaddr;
                    linkedit_fileoff = (uintptr_t)seg->fileoff;
                }
            } else if (cmd->cmd == LC_SYMTAB) {
                sc = (const struct symtab_command *)lc;
            }
            lc += cmd->cmdsize;
        }
        if (!sc || !linkedit_vmaddr) continue;

        // In-memory addresses: linkedit_base = vmaddr + slide - fileoff
        uintptr_t base = linkedit_vmaddr + (uintptr_t)slide - linkedit_fileoff;
        const struct nlist_64 *syms = (const struct nlist_64 *)(base + sc->symoff);
        const char *strtab = (const char *)(base + sc->stroff);

        for (uint32_t s = 0; s < sc->nsyms; s++) {
            const struct nlist_64 *n = &syms[s];
            if ((n->n_type & N_STAB) != 0) continue;
            if ((n->n_type & N_TYPE) == N_UNDF) continue;
            if (!(n->n_type & N_EXT)) continue;
            if (n->n_un.n_strx == 0) continue;
            const char *raw = strtab + n->n_un.n_strx;
            if (!raw || raw[0] != '_') continue;
            // Skip ObjC/Swift noise
            if (strncmp(raw, "_OBJC_", 6) == 0) continue;
            if (strncmp(raw, "_$s", 3) == 0) continue;
            if (strstr(raw, "__swift") || strstr(raw, "protocol witness")) continue;

            NSString *nm = [NSString stringWithUTF8String:raw] ?: @"";
            if (nm.length < 3) continue;
            SCISymEntry *e = [SCISymEntry new];
            e.name = nm;
            e.address = (uintptr_t)n->n_value + (uintptr_t)slide;
            e.isBoolGate =
                [nm containsString:@"MobileConfig"] || [nm containsString:@"EasyGating"] ||
                [nm containsString:@"GetBoolean"] || [nm containsString:@"GetBool"] ||
                [nm containsString:@"InternalUse"] || [nm containsString:@"Gating"] ||
                [nm containsString:@"Experiment"] || [nm containsString:@"Launcher"];
            [out addObject:e];
        }
        break;
    }
    return [out sortedArrayUsingComparator:^NSComparisonResult(SCISymEntry *a, SCISymEntry *b){
        return [a.name caseInsensitiveCompare:b.name];
    }];
}

// ---- View controller ----
@interface SCISymbolsBrowserViewController () <UITableViewDataSource,UITableViewDelegate,UISearchBarDelegate>
@property UISearchBar *searchBar;
@property UISegmentedControl *scopeSeg;
@property UITableView *tableView;
@property UIActivityIndicatorView *spinner;
@property NSArray<SCISymEntry *> *all;
@property NSArray<SCISymEntry *> *filtered;
@property BOOL loaded;
@end
@implementation SCISymbolsBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Symbols Browser";
    SCIApplyGlassBackdropToViewController(self);
    _all = _filtered = @[];

    _searchBar = [UISearchBar new];
    _searchBar.placeholder = @"Filter symbol name";
    _searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    _searchBar.delegate = self;
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_searchBar];

    _scopeSeg = [[UISegmentedControl alloc] initWithItems:@[@"Instagram", @"FBShared"]];
    _scopeSeg.selectedSegmentIndex = 0;
    _scopeSeg.translatesAutoresizingMaskIntoConstraints = NO;
    [_scopeSeg addTarget:self action:@selector(scopeChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_scopeSeg];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self; _tableView.delegate = self;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.estimatedRowHeight = 50; _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.contentInset = UIEdgeInsetsMake(110, 0, 0, 0);
    [_tableView registerClass:SCISymCell.class forCellReuseIdentifier:@"sym"];
    [self.view addSubview:_tableView]; [self.view sendSubviewToBack:_tableView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:g.topAnchor constant:4],
        [_searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [_searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [_scopeSeg.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:6],
        [_scopeSeg.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [_scopeSeg.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
    SCIApplyLiquidGlassToViewTree(self.view);
    [self loadSymbols];
}

- (void)loadSymbols {
    _loaded = NO; _all = _filtered = @[];
    [_tableView reloadData];
    [_spinner startAnimating];
    BOOL fbShared = _scopeSeg.selectedSegmentIndex == 1;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *result = SCIScanSymbols(fbShared);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.all = result; self.loaded = YES;
            self.title = [NSString stringWithFormat:@"Symbols (%lu)", (unsigned long)result.count];
            [self applyFilter];
            [self->_spinner stopAnimating];
        });
    });
}

- (void)applyFilter {
    NSString *q = _searchBar.text.lowercaseString;
    _filtered = q.length
        ? [_all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SCISymEntry *e, __unused id _){
            return [e.name.lowercaseString containsString:q];
          }]]
        : _all;
    [_tableView reloadData];
}

- (void)scopeChanged { _searchBar.text = @""; [self loadSymbols]; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sec {
    return _loaded ? (NSInteger)_filtered.count : 0;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    SCISymCell *cell = [tv dequeueReusableCellWithIdentifier:@"sym" forIndexPath:ip];
    SCISymEntry *e = _filtered[ip.row];
    // Strip leading _ for display
    cell.nameLabel.text = e.name.length > 1 ? [e.name substringFromIndex:1] : e.name;
    cell.nameLabel.textColor = e.isBoolGate ? UIColor.systemBlueColor : UIColor.labelColor;
    cell.addrLabel.text = [NSString stringWithFormat:@"0x%llx", (unsigned long long)e.address];
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    SCISymEntry *e = _filtered[ip.row];
    UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@ 0x%llx", e.name, (unsigned long long)e.address];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[e.name substringFromIndex:1]
        message:[NSString stringWithFormat:@"0x%llx\nBool gate: %@\nCopied to clipboard.",
                 (unsigned long long)e.address, e.isBoolGate ? @"yes" : @"no"]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)t { [self applyFilter]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }
- (void)scrollViewWillBeginDragging:(UIScrollView *)sv { [_searchBar resignFirstResponder]; }
@end
