// SCISymbolsBrowserViewController.m
#import "SCISymbolsBrowserViewController.h"
#import "../Utils.h"
#import "../Features/Gating/SCICSymbolStub.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <objc/runtime.h>

@interface SCICSymbolEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *section;
@property (nonatomic, assign) BOOL function;
@property (nonatomic, assign) BOOL resolvable;
@end
@implementation SCICSymbolEntry @end

static BOOL scic_string_has_prefix_any(NSString *s, NSArray<NSString *> *prefixes) {
	for (NSString *p in prefixes) if ([s hasPrefix:p]) return YES;
	return NO;
}

static NSString *scic_section_label(const struct section_64 *sec) {
	if (!sec) return @"unknown";
	char seg[17] = {0}; char sect[17] = {0};
	memcpy(seg, sec->segname, 16); memcpy(sect, sec->sectname, 16);
	return [NSString stringWithFormat:@"%s,%s", seg, sect];
}

static void scic_collect_sections(const struct mach_header_64 *mh, NSMutableArray<NSValue *> *sections, const struct symtab_command **symtab, const struct segment_command_64 **linkedit) {
	const uint8_t *p = (const uint8_t *)(mh + 1);
	for (uint32_t i = 0; i < mh->ncmds; i++) {
		const struct load_command *lc = (const struct load_command *)p;
		if (lc->cmd == LC_SEGMENT_64) {
			const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
			if (strncmp(seg->segname, SEG_LINKEDIT, 16) == 0) *linkedit = seg;
			const struct section_64 *sec = (const struct section_64 *)(seg + 1);
			for (uint32_t j = 0; j < seg->nsects; j++) [sections addObject:[NSValue valueWithPointer:&sec[j]]];
		} else if (lc->cmd == LC_SYMTAB) {
			*symtab = (const struct symtab_command *)lc;
		}
		p += lc->cmdsize;
	}
}

static NSArray<SCICSymbolEntry *> *SCICEnumerateFBSharedSymbols(void) {
	NSMutableArray<SCICSymbolEntry *> *out = [NSMutableArray array];
	uint32_t count = _dyld_image_count();
	for (uint32_t i = 0; i < count; i++) {
		const char *imageName = _dyld_get_image_name(i);
		if (!imageName || !strstr(imageName, "/FBSharedFramework")) continue;
		const struct mach_header *raw = _dyld_get_image_header(i);
		if (!raw || raw->magic != MH_MAGIC_64) continue;
		const struct mach_header_64 *mh = (const struct mach_header_64 *)raw;
		intptr_t slide = _dyld_get_image_vmaddr_slide(i);
		NSMutableArray<NSValue *> *sections = [NSMutableArray array];
		const struct symtab_command *symtab = NULL;
		const struct segment_command_64 *linkedit = NULL;
		scic_collect_sections(mh, sections, &symtab, &linkedit);
		if (!symtab || !linkedit) continue;
		uintptr_t linkeditBase = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr - (uintptr_t)linkedit->fileoff;
		const struct nlist_64 *nl = (const struct nlist_64 *)(linkeditBase + symtab->symoff);
		const char *strtab = (const char *)(linkeditBase + symtab->stroff);
		NSMutableSet<NSString *> *seen = [NSMutableSet set];
		for (uint32_t s = 0; s < symtab->nsyms; s++) {
			uint8_t type = nl[s].n_type;
			if (type & N_STAB) continue;
			if ((type & N_TYPE) != N_SECT) continue;
			if (nl[s].n_un.n_strx == 0) continue;
			const char *rawName = strtab + nl[s].n_un.n_strx;
			if (!rawName || rawName[0] != '_') continue;
			NSString *name = [NSString stringWithUTF8String:rawName + 1];
			if (!name.length || [seen containsObject:name]) continue;
			if ([name hasPrefix:@"OBJC_"] || [name hasPrefix:@"__Z"] || [name hasPrefix:@"_Z"] || [name hasPrefix:@"\001"]) continue;
			[seen addObject:name];
			const struct section_64 *sec = NULL;
			uint8_t sectIndex = nl[s].n_sect;
			if (sectIndex > 0 && sectIndex <= sections.count) sec = [sections[sectIndex - 1] pointerValue];
			NSString *section = scic_section_label(sec);
			BOOL isText = sec && strncmp(sec->segname, "__TEXT", 16) == 0 && strncmp(sec->sectname, "__text", 16) == 0;
			SCICSymbolEntry *e = [SCICSymbolEntry new];
			e.name = name;
			e.section = section;
			e.function = isText;
			e.resolvable = (dlsym(RTLD_DEFAULT, name.UTF8String) != NULL);
			[out addObject:e];
		}
		break;
	}
	[out sortUsingComparator:^NSComparisonResult(SCICSymbolEntry *a, SCICSymbolEntry *b) { return [a.name compare:b.name options:NSCaseInsensitiveSearch]; }];
	return out.copy;
}

static NSArray<NSString *> *SCICDefaultFilters(void) {
	return @[@"MobileConfig", @"EasyGating", @"MSGC", @"MEBIs", @"IGAppIs", @"employee", @"dogfood", @"internal", @"Boolean", @"Bool", @"map", @"prism", @"igds", @"igplus"];
}

static char kSCICSymbolRowPayloadKey;
static char kSCICSymbolInteractionPayloadKey;

@interface SCISymbolsBrowserViewController ()
@end

@implementation SCISymbolsBrowserViewController {
	NSArray<SCICSymbolEntry *> *_allSymbols;
	NSString *_query;
	UISearchBar *_searchBar;
	SCIUIKit26SearchBarContainerView *_searchContainer;
	NSLayoutConstraint *_searchBottomConstraint;
	UIActivityIndicatorView *_spinner;
}

- (instancetype)init {
	self = [super initWithTitle:@"FBShared C Symbols"];
	if (self) self.reduceTopInset = YES;
	return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLoad {
	[super viewDidLoad];
	[self configureBottomSearchBar];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];

	_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
	_spinner.center = self.view.center;
	_spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
	[self.view addSubview:_spinner];
	[_spinner startAnimating];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSArray *symbols = SCICEnumerateFBSharedSymbols();
		dispatch_async(dispatch_get_main_queue(), ^{
			self->_allSymbols = symbols;
			[SCICSymbolStub reinstallPersistedStubs]; // runtime attach after UI is open; never at cold launch by default
			[self->_spinner stopAnimating];
			[self rebuildSections];
		});
	});
}

- (void)configureBottomSearchBar {
	_searchContainer = [[SCIUIKit26SearchBarContainerView alloc] initWithRadius:22.0];
	_searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
	_searchContainer.sciGlassInteractive = YES;
	_searchContainer.sciGlassClearStyle = YES;
	_searchContainer.sciGlassTintColor = [UIColor colorWithWhite:1.0 alpha:0.04];
	[_searchContainer applyLiquidGlassStyle];
	[self.view addSubview:_searchContainer];
	_searchBar = _searchContainer.searchBar;
	_searchBar.placeholder = @"Search FBShared C symbols…";
	_searchBar.delegate = self;
	SCIUIKit26ConfigureSearchBar(_searchBar);
	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	_searchBottomConstraint = [_searchContainer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10.0];
	[NSLayoutConstraint activateConstraints:@[
		[_searchContainer.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:14.0],
		[_searchContainer.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-14.0],
		_searchBottomConstraint,
		[_searchContainer.heightAnchor constraintEqualToConstant:52.0],
	]];
	[self applyBottomInset:0.0];
}

- (void)applyBottomInset:(CGFloat)overlap {
	UIEdgeInsets inset = self.tableView.contentInset;
	inset.bottom = 84.0 + MAX(0.0, overlap);
	self.tableView.contentInset = inset;
	self.tableView.scrollIndicatorInsets = inset;
}

- (void)keyboardWillHide:(NSNotification *)note { [self updateSearchForKeyboard:note hidden:YES]; }
- (void)keyboardWillChangeFrame:(NSNotification *)note { [self updateSearchForKeyboard:note hidden:NO]; }
- (void)updateSearchForKeyboard:(NSNotification *)note hidden:(BOOL)hidden {
	CGFloat overlap = 0.0;
	if (!hidden) {
		CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
		CGRect frameInView = [self.view convertRect:endFrame fromView:nil];
		overlap = MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(frameInView) - self.view.safeAreaInsets.bottom);
	}
	NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	UIViewAnimationOptions options = ([note.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16);
	void (^changes)(void) = ^{ self->_searchBottomConstraint.constant = -10.0 - overlap; [self applyBottomInset:overlap]; [self.view layoutIfNeeded]; };
	if (duration > 0) [UIView animateWithDuration:duration delay:0 options:options animations:changes completion:nil]; else changes();
}

- (NSArray<NSString *> *)queryTokens {
	NSString *q = [[_query ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
	if (!q.length) return @[];
	NSArray *raw = [q componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSMutableArray *tokens = [NSMutableArray array];
	for (NSString *t in raw) if (t.length) [tokens addObject:t];
	return tokens.copy;
}

- (BOOL)symbol:(SCICSymbolEntry *)e matchesTokens:(NSArray<NSString *> *)tokens {
	NSString *hay = [NSString stringWithFormat:@"%@ %@", e.name ?: @"", e.section ?: @""].lowercaseString;
	for (NSString *t in tokens) if (![hay containsString:t]) return NO;
	return YES;
}

- (BOOL)symbolMatchesDefaultFilters:(SCICSymbolEntry *)e {
	if ([SCICSymbolStub forceForSymbol:e.name] != nil) return YES;
	if ([SCICSymbolStub observeForSymbol:e.name]) return YES;
	if ([SCICSymbolStub hookInstalledForSymbol:e.name]) return YES;
	for (NSString *f in SCICDefaultFilters()) if ([e.name.lowercaseString containsString:f.lowercaseString]) return YES;
	return NO;
}

- (NSString *)statusForSymbol:(SCICSymbolEntry *)e {
	NSMutableArray<NSString *> *bits = [NSMutableArray array];
	[bits addObject:@"FBSharedFramework export"];
	[bits addObject:e.function ? @"function" : @"data/const"];
	[bits addObject:e.resolvable ? @"resolvable" : @"not resolvable"];
	if ([SCICSymbolStub isBoolLikeSymbol:e.name]) [bits addObject:@"bool-like"];
	NSString *hookBlock = [SCICSymbolStub notHookableReasonForSymbol:e.name];
	if (hookBlock) [bits addObject:@"list-only"];
	else [bits addObject:@"hookable"];
	NSString *blocked = [SCICSymbolStub notForceableReasonForSymbol:e.name];
	if (blocked) [bits addObject:@"observe-only"];
	else [bits addObject:@"force allowed"];
	if ([SCICSymbolStub observeForSymbol:e.name]) [bits addObject:@"observe=ON"];
	if ([SCICSymbolStub hookInstalledForSymbol:e.name]) [bits addObject:@"hooked"];
	NSNumber *forced = [SCICSymbolStub forceForSymbol:e.name];
	BOOL installed = [SCICSymbolStub hookInstalledForSymbol:e.name];
	if (forced) [bits addObject:forced.boolValue ? @"forced=YES" : @"forced=NO"];
	if (forced && !installed) [bits addObject:@"restart required"];
	NSUInteger hits = [SCICSymbolStub callCountForSymbol:e.name];
	if (hits) [bits addObject:[NSString stringWithFormat:@"hits=%lu", (unsigned long)hits]];
	NSNumber *obs = [SCICSymbolStub observedValueForSymbol:e.name];
	if (obs) [bits addObject:obs.boolValue ? @"observed=YES" : @"observed=NO"];
	return [bits componentsJoinedByString:@" • "];
}

- (void)showMessage:(NSString *)message {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"C Symbol" message:message preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)presentActionsForSymbol:(SCICSymbolEntry *)entry {
	NSString *name = entry.name ?: @"";
	BOOL canObserve = entry.function && entry.resolvable && [SCICSymbolStub isHookableSymbol:name];
	BOOL canForce = entry.function && entry.resolvable && [SCICSymbolStub isForceableSymbol:name];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:name message:[self statusForSymbol:entry] preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	if (canObserve) {
		NSString *observeTitle = [SCICSymbolStub observeForSymbol:name] ? @"Disable observe hook" : @"Enable observe hook";
		[a addAction:[UIAlertAction actionWithTitle:observeTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
			[SCICSymbolStub setObserve:![SCICSymbolStub observeForSymbol:name] forSymbol:name];
			[weakSelf showMessage:@"Observe state persisted. New C hooks install on next launch; installed hooks keep recording hits/value."];
			[weakSelf rebuildSections];
		}]];
	}
	if (canForce) {
		[a addAction:[UIAlertAction actionWithTitle:@"Force return YES" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
			[SCICSymbolStub setForce:@YES forSymbol:name];
			[weakSelf showMessage:@"Force YES persisted. Applies after relaunch unless already installed."];
			[weakSelf rebuildSections];
		}]];
		[a addAction:[UIAlertAction actionWithTitle:@"Force return NO" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
			[SCICSymbolStub setForce:@NO forSymbol:name];
			[weakSelf showMessage:@"Force NO persisted. Applies after relaunch unless already installed."];
			[weakSelf rebuildSections];
		}]];
	}
	NSString *clearTitle = [SCICSymbolStub forceForSymbol:name] ? @"Clear force" : @"Clear force (none)";
	UIAlertAction *clear = [UIAlertAction actionWithTitle:clearTitle style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
		[SCICSymbolStub setForce:nil forSymbol:name];
		[weakSelf rebuildSections];
	}];
	if (![SCICSymbolStub forceForSymbol:name]) clear.enabled = NO;
	[a addAction:clear];
	[a addAction:[UIAlertAction actionWithTitle:@"Copy symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		UIPasteboard.generalPasteboard.string = name;
	}]];
	if (!canObserve) {
		NSString *reason = [SCICSymbolStub notHookableReasonForSymbol:name] ?: @"Symbol is not a resolvable function with a validated ABI/profile.";
		UIAlertAction *blocked = [UIAlertAction actionWithTitle:[@"List-only: " stringByAppendingString:reason] style:UIAlertActionStyleDefault handler:nil];
		blocked.enabled = NO;
		[a addAction:blocked];
	} else if (!canForce) {
		NSString *reason = [SCICSymbolStub notForceableReasonForSymbol:name] ?: @"Observe-only reader.";
		UIAlertAction *blocked = [UIAlertAction actionWithTitle:[@"Force blocked: " stringByAppendingString:reason] style:UIAlertActionStyleDefault handler:nil];
		blocked.enabled = NO;
		[a addAction:blocked];
	}
	[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	UIPopoverPresentationController *pop = a.popoverPresentationController;
	pop.sourceView = self.view;
	pop.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds) - 40.0, 1.0, 1.0);
	[self presentViewController:a animated:YES completion:nil];
}

- (void)applyObserveValue:(BOOL)value forSymbolName:(NSString *)name {
	if (![name isKindOfClass:NSString.class] || !name.length) return;
	[SCICSymbolStub setObserve:value forSymbol:name];
	[self rebuildSections];
}

- (void)applyForceValue:(NSNumber *)value forSymbolName:(NSString *)name {
	if (![name isKindOfClass:NSString.class] || !name.length) return;
	[SCICSymbolStub setForce:value forSymbol:name];
	[self rebuildSections];
}

- (void)rebuildSections {
	if (!_allSymbols) return;
	NSArray<NSString *> *tokens = [self queryTokens];
	NSMutableArray<SCIBaseSettingsSection *> *sections = [NSMutableArray array];
	NSMutableArray<SCIBaseSettingsRow *> *rows = [NSMutableArray array];
	NSUInteger shown = 0;
	for (SCICSymbolEntry *e in _allSymbols) {
		if (tokens.count) { if (![self symbol:e matchesTokens:tokens]) continue; }
		else if (![self symbolMatchesDefaultFilters:e]) continue;
		NSUInteger limit = tokens.count ? 500 : 260;
		if (shown++ >= limit) break;
		__weak typeof(self) weakSelf = self;
		NSString *name = e.name ?: @"";
		BOOL canObserve = e.function && e.resolvable && [SCICSymbolStub isHookableSymbol:name];
		BOOL canForce = e.function && e.resolvable && [SCICSymbolStub isForceableSymbol:name];
		SCIBaseSettingsRow *row = nil;
		if (canObserve) {
			row = [SCIBaseSettingsRow
				switchRowWithTitle:name
					  subtitle:nil
						 value:^BOOL{
							 NSNumber *forced = [SCICSymbolStub forceForSymbol:name];
							 if (canForce) return forced ? forced.boolValue : NO;
							 return [SCICSymbolStub observeForSymbol:name];
						 }
						action:^(BOOL enabled, __unused UIViewController *vc) {
							 if (canForce) {
								 [SCICSymbolStub setForce:(enabled ? @YES : nil) forSymbol:name];
							 } else {
								 [SCICSymbolStub setObserve:enabled forSymbol:name];
							 }
							 [weakSelf rebuildSections];
						 }];
			NSDictionary *payload = @{ @"name": name };
			objc_setAssociatedObject(row, &kSCICSymbolRowPayloadKey, payload, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		} else {
			row = [SCIBaseSettingsRow rowWithTitle:name subtitle:nil action:^(__unused UIViewController *vc) {
				[weakSelf presentActionsForSymbol:e];
			}];
		}
		row.dynamicSubtitle = ^NSString *{ return [weakSelf statusForSymbol:e]; };
		[rows addObject:row];
	}
	NSString *footer = [NSString stringWithFormat:@"Indexed %lu FBShared symbols. %@", (unsigned long)_allSymbols.count, tokens.count ? @"Search scans the full cached symbol table. Search scans the full runtime FBShared export table. Only single-purpose validated BOOL functions get C-hook toggles; multi-key readers must be forced by key in MobileConfig/EasyGating." : @"Showing default internal/gating filters and forced stubs. Single-purpose validated BOOL functions appear as toggles; list-only/multi-key symbols remain browse/copy only."];
	if (!rows.count) [rows addObject:[SCIBaseSettingsRow rowWithTitle:@"No matching C symbols" subtitle:@"Search another term." action:nil]];
	[sections addObject:[SCIBaseSettingsSection sectionWithHeader:@"FBSharedFramework C exports" footer:footer rows:rows]];
	self.sections = sections;
	[self reloadSettings];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	if ([cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) {
		UIListContentConfiguration *cfg = (UIListContentConfiguration *)cell.contentConfiguration;
		cfg.textProperties.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightRegular];
		cfg.textProperties.numberOfLines = 2;
		cfg.secondaryTextProperties.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
		cfg.secondaryTextProperties.numberOfLines = 2;
		cell.contentConfiguration = cfg;
	}

	if (indexPath.section < (NSInteger)self.sections.count) {
		SCIBaseSettingsSection *section = self.sections[indexPath.section];
		if (indexPath.row < (NSInteger)section.rows.count) {
			SCIBaseSettingsRow *row = section.rows[indexPath.row];
			NSDictionary *payload = objc_getAssociatedObject(row, &kSCICSymbolRowPayloadKey);
			for (id<UIInteraction> interaction in cell.interactions.copy) {
				if ([interaction isKindOfClass:UIContextMenuInteraction.class]) [cell removeInteraction:interaction];
			}
			if ([payload isKindOfClass:NSDictionary.class]) {
				UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
				objc_setAssociatedObject(interaction, &kSCICSymbolInteractionPayloadKey, payload, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				[cell addInteraction:interaction];
			}
		}
	}
	return cell;
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(__unused CGPoint)location {
	NSDictionary *payload = objc_getAssociatedObject(interaction, &kSCICSymbolInteractionPayloadKey);
	if (![payload isKindOfClass:NSDictionary.class]) return nil;
	NSString *name = payload[@"name"] ?: @"";
	if (!name.length) return nil;
	BOOL hasForce = [SCICSymbolStub forceForSymbol:name] != nil;
	BOOL canForce = [SCICSymbolStub isForceableSymbol:name];
	BOOL observing = [SCICSymbolStub observeForSymbol:name];
	__weak typeof(self) weakSelf = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(__unused NSArray<UIMenuElement *> *suggestedActions) {
		UIAction *observe = [UIAction actionWithTitle:(observing ? @"Disable observe" : @"Enable observe") image:[UIImage systemImageNamed:@"eye"] identifier:nil handler:^(__unused UIAction *action) {
			[weakSelf applyObserveValue:!observing forSymbolName:name];
		}];
		UIAction *clear = [UIAction actionWithTitle:@"Clear force" image:[UIImage systemImageNamed:@"arrow.uturn.backward"] identifier:nil handler:^(__unused UIAction *action) {
			[weakSelf applyForceValue:nil forSymbolName:name];
		}];
		if (!hasForce) clear.attributes = UIMenuElementAttributesDisabled;
		UIAction *forceNo = [UIAction actionWithTitle:@"Force return NO" image:[UIImage systemImageNamed:@"poweroff"] identifier:nil handler:^(__unused UIAction *action) {
			[weakSelf applyForceValue:@NO forSymbolName:name];
		}];
		if (!canForce) forceNo.attributes = UIMenuElementAttributesDisabled;
		UIAction *copy = [UIAction actionWithTitle:@"Copy symbol" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__unused UIAction *action) {
			UIPasteboard.generalPasteboard.string = name;
		}];
		return [UIMenu menuWithTitle:@"" children:@[observe, clear, forceNo, copy]];
	}];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { _query = searchText ?: @""; [self rebuildSections]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
