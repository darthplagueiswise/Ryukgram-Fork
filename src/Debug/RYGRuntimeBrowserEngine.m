#import "RYGRuntimeBrowserEngine.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

static NSString *const kRYGRuntimeOverridesKey = @"ryg_runtime_bool_overrides";
static NSDictionary<NSString *, NSNumber *> *gRYGOverrideCache;
static NSMutableSet<NSString *> *gRYGInstalledKeys;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGObservedValues;
static BOOL gRYGReinstallScheduled;

static NSString *RYGMethodKey(NSString *className, NSString *selectorName, BOOL classMethod) {
	return [NSString stringWithFormat:@"%@%@#%@", classMethod ? @"+" : @"-", className ?: @"", selectorName ?: @""];
}

static NSDictionary<NSString *, NSNumber *> *RYGPersistedOverrides(void) {
	id value = [NSUserDefaults.standardUserDefaults objectForKey:kRYGRuntimeOverridesKey];
	if (![value isKindOfClass:NSDictionary.class]) return @{};
	NSMutableDictionary *clean = [NSMutableDictionary dictionary];
	[(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSNumber.class]) clean[key] = obj;
	}];
	return clean.copy;
}

static void RYGRefreshOverrideCache(void) {
	@synchronized(RYGRuntimeBrowserEngine.class) {
		gRYGOverrideCache = RYGPersistedOverrides();
	}
}

static NSNumber *RYGCachedOverride(NSString *key) {
	@synchronized(RYGRuntimeBrowserEngine.class) {
		id value = gRYGOverrideCache[key];
		return [value isKindOfClass:NSNumber.class] ? value : nil;
	}
}

static void RYGRememberObservedValue(NSString *key, BOOL value) {
	@synchronized(RYGRuntimeBrowserEngine.class) {
		if (!gRYGObservedValues) gRYGObservedValues = [NSMutableDictionary dictionary];
		gRYGObservedValues[key] = @(value);
	}
}

static NSNumber *RYGObservedValue(NSString *key) {
	@synchronized(RYGRuntimeBrowserEngine.class) {
		return gRYGObservedValues[key];
	}
}

static const char *RYGSkipTypeQualifiers(const char *type) {
	while (type && strchr("rnNoORV", *type)) type++;
	return type;
}

static RYGRuntimeArgumentKind RYGArgumentKindForMethod(Method method) {
	if (!method) return -1;
	unsigned int count = method_getNumberOfArguments(method);
	if (count == 2) return RYGRuntimeArgumentNone;
	if (count != 3) return -1;
	char encoded[32] = {0};
	method_getArgumentType(method, 2, encoded, sizeof(encoded));
	const char *type = RYGSkipTypeQualifiers(encoded);
	if (!type || !*type) return -1;
	if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
	if (strchr("BcCsSiIlLqQ^*", *type)) return RYGRuntimeArgumentInteger;
	return -1;
}

static BOOL RYGMethodHasSupportedBoolSignature(Method method) {
	if (!method) return NO;
	char encoded[16] = {0};
	method_getReturnType(method, encoded, sizeof(encoded));
	const char *type = RYGSkipTypeQualifiers(encoded);
	// On arm64, Objective-C BOOL is `B`. Generic chars are deliberately excluded.
	return type && *type == 'B' && RYGArgumentKindForMethod(method) >= 0;
}

static NSSet<NSString *> *RYGStructuralNoiseNames(void) {
	static NSSet<NSString *> *names;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		names = [NSSet setWithArray:@[
			@"isEqual:", @"isEqualToString:", @"isEqualToDiffableObject:",
			@"respondsToSelector:", @"conformsToProtocol:", @"isKindOfClass:",
			@"isMemberOfClass:", @"isProxy", @"allowsWeakReference",
			@"retainWeakReference", @"supportsSecureCoding",
			@"automaticallyNotifiesObserversForKey:", @"canPerformAction:withSender:",
			@"canBecomeFirstResponder", @"canResignFirstResponder", @"isFirstResponder",
			@"becomeFirstResponder", @"resignFirstResponder",
			@"gestureRecognizerShouldBegin:",
			@"gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:",
			@"gestureRecognizer:shouldReceiveTouch:",
			@"gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:",
			@"gestureRecognizer:shouldRequireFailureOfGestureRecognizer:",
			@"textFieldShouldReturn:", @"textFieldShouldBeginEditing:",
			@"textFieldShouldEndEditing:", @"textFieldShouldClear:",
			@"textField:shouldChangeCharactersInRange:replacementString:",
			@"textViewShouldBeginEditing:", @"textViewShouldEndEditing:",
			@"textView:shouldChangeTextInRange:replacementText:",
			@"searchBarShouldBeginEditing:", @"searchBarShouldEndEditing:",
			@"scrollViewShouldScrollToTop:", @"isAccessibilityElement",
			@"accessibilityActivate", @"accessibilityPerformEscape",
			@"accessibilityPerformMagicTap", @"accessibilityScroll:"
		]];
	});
	return names;
}

static BOOL RYGSelectorIsStructuralNoise(NSString *name) {
	if (!name.length || [RYGStructuralNoiseNames() containsObject:name]) return YES;
	NSString *lower = name.lowercaseString;
	return [lower hasPrefix:@"isequal"]
		|| [lower hasPrefix:@"respondstoselector"]
		|| [lower hasPrefix:@"canrespond"];
}

static BOOL RYGClassMethodIsStructuralState(Class cls, NSString *selectorName) {
	if (!cls || !selectorName.length) return YES;
	BOOL viewLike = [cls isSubclassOfClass:UIView.class]
		|| [cls isSubclassOfClass:UIViewController.class]
		|| [cls isSubclassOfClass:CALayer.class];
	if (!viewLike) return NO;
	static NSSet<NSString *> *stateNames;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		stateNames = [NSSet setWithArray:@[
			@"isHidden", @"isSelected", @"isEnabled", @"isHighlighted",
			@"isOpaque", @"clipsToBounds", @"isUserInteractionEnabled",
			@"userInteractionEnabled", @"isFocused", @"canBecomeFocused",
			@"prefersStatusBarHidden", @"prefersHomeIndicatorAutoHidden",
			@"shouldAutorotate"
		]];
	});
	return [stateNames containsObject:selectorName];
}

static BOOL RYGMethodIsRelevant(NSString *className, NSString *selectorName, RYGRuntimeBrowserScope scope) {
	if (scope == RYGRuntimeBrowserScopeAll) return YES;
	NSString *haystack = [[NSString stringWithFormat:@"%@ %@", className ?: @"", selectorName ?: @""] lowercaseString];
	NSArray<NSString *> *employeeNeedles = @[@"employee", @"dogfood", @"internal", @"launcher", @"staff", @"metamate"];
	for (NSString *needle in employeeNeedles) {
		if ([haystack containsString:needle]) return YES;
	}
	if (scope == RYGRuntimeBrowserScopeEmployee) return NO;
	for (NSString *needle in @[@"experiment", @"feature", @"gate", @"gating", @"enable", @"available", @"allow", @"support", @"test", @"debug", @"rollout", @"treatment", @"variant", @"config"]) {
		if ([haystack containsString:needle]) return YES;
	}
	return NO;
}

static BOOL RYGParseMethodKey(NSString *key, NSString **className, NSString **selectorName, BOOL *classMethod) {
	if (key.length < 4) return NO;
	unichar prefix = [key characterAtIndex:0];
	if (prefix != '+' && prefix != '-') return NO;
	NSString *body = [key substringFromIndex:1];
	NSRange separator = [body rangeOfString:@"#"];
	if (separator.location == NSNotFound || separator.location == 0 || NSMaxRange(separator) >= body.length) return NO;
	if (className) *className = [body substringToIndex:separator.location];
	if (selectorName) *selectorName = [body substringFromIndex:NSMaxRange(separator)];
	if (classMethod) *classMethod = prefix == '+';
	return YES;
}

static BOOL RYGInstallOverrideKey(NSString *key) {
	@synchronized(RYGRuntimeBrowserEngine.class) {
		if (!gRYGInstalledKeys) gRYGInstalledKeys = [NSMutableSet set];
		if ([gRYGInstalledKeys containsObject:key]) return YES;
	}

	NSString *className = nil, *selectorName = nil;
	BOOL classMethod = NO;
	if (!RYGParseMethodKey(key, &className, &selectorName, &classMethod)
		|| RYGSelectorIsStructuralNoise(selectorName)) return NO;
	Class cls = NSClassFromString(className);
	SEL selector = NSSelectorFromString(selectorName);
	Method method = classMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
	if (!cls || !selector || !RYGMethodHasSupportedBoolSignature(method)
		|| RYGClassMethodIsStructuralState(cls, selectorName)) return NO;

	Class hookClass = classMethod ? object_getClass(cls) : cls;
	RYGRuntimeArgumentKind argumentKind = RYGArgumentKindForMethod(method);
	NSString *capturedKey = key.copy;
	SEL capturedSelector = selector;
	// Keep one process-lifetime original-IMP slot per installed override. This
	// avoids relying on a __block variable's forwarding storage after the block
	// has been copied by imp_implementationWithBlock.
	IMP *original = calloc(1, sizeof(IMP));
	if (!original) return NO;
	IMP replacement = NULL;
	if (argumentKind == RYGRuntimeArgumentNone) {
		replacement = imp_implementationWithBlock(^BOOL(id receiver) {
			BOOL native = *original ? ((BOOL (*)(id, SEL))*original)(receiver, capturedSelector) : NO;
			RYGRememberObservedValue(capturedKey, native);
			NSNumber *forced = RYGCachedOverride(capturedKey);
			return forced ? forced.boolValue : native;
		});
	} else if (argumentKind == RYGRuntimeArgumentObject) {
		replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
			BOOL native = *original ? ((BOOL (*)(id, SEL, id))*original)(receiver, capturedSelector, argument) : NO;
			RYGRememberObservedValue(capturedKey, native);
			NSNumber *forced = RYGCachedOverride(capturedKey);
			return forced ? forced.boolValue : native;
		});
	} else {
		replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
			BOOL native = *original ? ((BOOL (*)(id, SEL, uint64_t))*original)(receiver, capturedSelector, argument) : NO;
			RYGRememberObservedValue(capturedKey, native);
			NSNumber *forced = RYGCachedOverride(capturedKey);
			return forced ? forced.boolValue : native;
		});
	}
	if (!replacement) { free(original); return NO; }
	@synchronized(RYGRuntimeBrowserEngine.class) {
		if ([gRYGInstalledKeys containsObject:key]) {
			imp_removeBlock(replacement);
			free(original);
			return YES;
		}
		[gRYGInstalledKeys addObject:key];
	}
	MSHookMessageEx(hookClass, selector, replacement, original);
	@synchronized(RYGRuntimeBrowserEngine.class) {
		if (!*original) [gRYGInstalledKeys removeObject:key];
	}
	return *original != NULL;
}

@implementation RYGRuntimeBoolMethod
- (NSString *)overrideKey { return RYGMethodKey(self.className, self.selectorName, self.classMethod); }
- (NSNumber *)overrideValue { return [RYGRuntimeBrowserEngine overrideForKey:self.overrideKey]; }
- (NSNumber *)liveValue {
	// Never execute an unknown private method just to populate a cell. A native
	// value appears only after the passthrough hook has observed a real call.
	return RYGObservedValue(self.overrideKey);
}
@end

@implementation RYGMachOSymbol @end

@implementation RYGRuntimeBrowserEngine

+ (NSArray<NSString *> *)runtimeImagePaths {
	NSString *executable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
	NSString *bundleRoot = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
	NSString *frameworkRoot = [[bundleRoot stringByAppendingPathComponent:@"Frameworks"] stringByStandardizingPath];
	NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
	uint32_t count = _dyld_image_count();
	for (uint32_t index = 0; index < count; index++) {
		const char *raw = _dyld_get_image_name(index);
		if (!raw) continue;
		NSString *path = [[NSString stringWithUTF8String:raw] stringByStandardizingPath];
		BOOL main = executable.length && [path isEqualToString:executable];
		BOOL framework = [path hasPrefix:[frameworkRoot stringByAppendingString:@"/"]];
		BOOL bundledDylib = [path hasPrefix:[bundleRoot stringByAppendingString:@"/"]]
			&& [path.pathExtension.lowercaseString isEqualToString:@"dylib"];
		if (main || framework || bundledDylib) [paths addObject:path];
	}
	return [paths.array sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
		BOOL leftMain = [left isEqualToString:executable];
		BOOL rightMain = [right isEqualToString:executable];
		if (leftMain != rightMain) return leftMain ? NSOrderedAscending : NSOrderedDescending;
		return [[self shortNameForImagePath:left] localizedCaseInsensitiveCompare:[self shortNameForImagePath:right]];
	}];
}

+ (NSString *)shortNameForImagePath:(NSString *)imagePath {
	NSString *name = imagePath.lastPathComponent;
	return name.length ? name : @"Image";
}

+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName {
	return RYGSelectorIsStructuralNoise(selectorName);
}

+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePath:(NSString *)imagePath scope:(RYGRuntimeBrowserScope)scope {
	NSString *wanted = imagePath.stringByStandardizingPath;
	if (!wanted.length) return @[];
	unsigned int classCount = 0;
	Class *classes = objc_copyClassList(&classCount);
	if (!classes) return @[];
	NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
	for (unsigned int index = 0; index < classCount; index++) {
		Class cls = classes[index];
		const char *rawImage = class_getImageName(cls);
		if (!rawImage) continue;
		NSString *classImage = [[NSString stringWithUTF8String:rawImage] stringByStandardizingPath];
		if (![classImage isEqualToString:wanted]) continue;
		NSString *className = NSStringFromClass(cls);
		if (!className.length) continue;

		for (NSInteger pass = 0; pass < 2; pass++) {
			BOOL classMethod = pass == 1;
			Class owner = classMethod ? object_getClass(cls) : cls;
			unsigned int methodCount = 0;
			Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
			for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
				Method method = methods[methodIndex];
				SEL selector = method_getName(method);
				NSString *selectorName = selector ? NSStringFromSelector(selector) : nil;
				if (!selectorName.length || [selectorName hasPrefix:@"set"] || [selectorName hasPrefix:@"init"]
					|| RYGSelectorIsStructuralNoise(selectorName)
					|| RYGClassMethodIsStructuralState(cls, selectorName)
					|| !RYGMethodHasSupportedBoolSignature(method)
					|| !RYGMethodIsRelevant(className, selectorName, scope)) continue;

				RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
				row.imagePath = wanted;
				row.className = className;
				row.selectorName = selectorName;
				row.classMethod = classMethod;
				row.argumentKind = RYGArgumentKindForMethod(method);
				row.typeEncoding = [NSString stringWithUTF8String:method_getTypeEncoding(method) ?: ""];
				[rows addObject:row];
			}
			if (methods) free(methods);
		}
	}
	free(classes);
	[rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
		NSComparisonResult classOrder = [left.className localizedCaseInsensitiveCompare:right.className];
		return classOrder == NSOrderedSame ? [left.selectorName localizedCaseInsensitiveCompare:right.selectorName] : classOrder;
	}];
	return rows.copy;
}

+ (NSInteger)dyldIndexForImagePath:(NSString *)imagePath {
	NSString *wanted = imagePath.stringByStandardizingPath;
	for (uint32_t index = 0; index < _dyld_image_count(); index++) {
		const char *raw = _dyld_get_image_name(index);
		if (raw && [[NSString stringWithUTF8String:raw].stringByStandardizingPath isEqualToString:wanted]) return index;
	}
	return NSNotFound;
}

+ (NSArray<RYGMachOSymbol *> *)machOSymbolsForImagePath:(NSString *)imagePath {
	NSInteger imageIndex = [self dyldIndexForImagePath:imagePath];
	if (imageIndex == NSNotFound) return @[];
	const struct mach_header *rawHeader = _dyld_get_image_header((uint32_t)imageIndex);
	if (!rawHeader || rawHeader->magic != MH_MAGIC_64) return @[];
	const struct mach_header_64 *header = (const struct mach_header_64 *)rawHeader;
	if (!header->sizeofcmds || header->sizeofcmds > 16 * 1024 * 1024 || header->ncmds > 65535) return @[];
	intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
	const uint8_t *cursor = (const uint8_t *)(header + 1);
	const uint8_t *commandsEnd = cursor + header->sizeofcmds;
	const struct symtab_command *symtabCommand = NULL;
	const struct segment_command_64 *linkedit = NULL;
	NSMutableDictionary<NSNumber *, NSString *> *sectionKinds = [NSMutableDictionary dictionary];
	uint16_t sectionOrdinal = 1;
	for (uint32_t commandIndex = 0; commandIndex < header->ncmds; commandIndex++) {
		if (cursor > commandsEnd || (size_t)(commandsEnd - cursor) < sizeof(struct load_command)) return @[];
		const struct load_command *command = (const struct load_command *)cursor;
		if (command->cmdsize < sizeof(struct load_command)
			|| command->cmdsize > (size_t)(commandsEnd - cursor)) return @[];
		if (command->cmd == LC_SYMTAB) symtabCommand = (const struct symtab_command *)command;
		if (command->cmd == LC_SEGMENT_64) {
			const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
			if (segment->cmdsize < sizeof(*segment)
				|| segment->nsects > (segment->cmdsize - sizeof(*segment)) / sizeof(struct section_64)) return @[];
			if (strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname)) == 0) linkedit = segment;
			const struct section_64 *sections = (const struct section_64 *)(segment + 1);
			for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; sectionIndex++, sectionOrdinal++) {
				uint32_t flags = sections[sectionIndex].flags;
				BOOL instructions = (flags & S_ATTR_PURE_INSTRUCTIONS) || (flags & S_ATTR_SOME_INSTRUCTIONS);
				if (sectionOrdinal <= UINT8_MAX) sectionKinds[@(sectionOrdinal)] = instructions ? @"Function" : @"Data";
			}
		}
		cursor += command->cmdsize;
	}
	if (!symtabCommand || !linkedit || !symtabCommand->nsyms || !symtabCommand->strsize) return @[];
	uint64_t linkeditStart = linkedit->fileoff;
	uint64_t linkeditEnd = linkeditStart + linkedit->filesize;
	uint64_t symbolsEnd = (uint64_t)symtabCommand->symoff
		+ (uint64_t)symtabCommand->nsyms * sizeof(struct nlist_64);
	uint64_t stringsEnd = (uint64_t)symtabCommand->stroff + symtabCommand->strsize;
	if (linkeditEnd < linkeditStart
		|| symtabCommand->symoff < linkeditStart || symbolsEnd > linkeditEnd
		|| symtabCommand->stroff < linkeditStart || stringsEnd > linkeditEnd) return @[];
	if (slide < 0 || (uintptr_t)slide > UINTPTR_MAX - (uintptr_t)linkedit->vmaddr) return @[];
	uintptr_t slidLinkedit = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr;
	if (slidLinkedit < (uintptr_t)linkedit->fileoff) return @[];
	uintptr_t linkeditBase = slidLinkedit - (uintptr_t)linkedit->fileoff;
	if (linkeditBase > UINTPTR_MAX - symtabCommand->symoff
		|| linkeditBase > UINTPTR_MAX - symtabCommand->stroff) return @[];
	const struct nlist_64 *symbols = (const struct nlist_64 *)(linkeditBase + symtabCommand->symoff);
	const char *strings = (const char *)(linkeditBase + symtabCommand->stroff);
	NSMutableArray<RYGMachOSymbol *> *rows = [NSMutableArray array];
	NSUInteger limit = MIN((NSUInteger)symtabCommand->nsyms, (NSUInteger)50000);
	for (NSUInteger index = 0; index < limit; index++) {
		const struct nlist_64 entry = symbols[index];
		if ((entry.n_type & N_STAB) || entry.n_un.n_strx == 0 || entry.n_un.n_strx >= symtabCommand->strsize) continue;
		size_t remaining = symtabCommand->strsize - entry.n_un.n_strx;
		const char *rawName = strings + entry.n_un.n_strx;
		size_t length = strnlen(rawName, MIN(remaining, (size_t)4096));
		if (!length || length >= remaining) continue;
		NSString *name = [[NSString alloc] initWithBytes:rawName length:length encoding:NSUTF8StringEncoding];
		if (!name.length) continue;
		RYGMachOSymbol *row = [RYGMachOSymbol new];
		row.name = name;
		row.external = (entry.n_type & N_EXT) != 0;
		uint8_t type = entry.n_type & N_TYPE;
		if (type == N_UNDF) row.kind = @"Undefined";
		else if (type == N_ABS) row.kind = @"Absolute";
		else if (type == N_SECT) row.kind = sectionKinds[@(entry.n_sect)] ?: @"Section";
		else row.kind = @"Symbol";
			row.address = entry.n_value
				? (type == N_SECT ? entry.n_value + slide : entry.n_value)
				: 0;
		[rows addObject:row];
	}
	[rows sortUsingComparator:^NSComparisonResult(RYGMachOSymbol *left, RYGMachOSymbol *right) {
		return [left.name localizedCaseInsensitiveCompare:right.name];
	}];
	return rows.copy;
}

+ (NSNumber *)overrideForKey:(NSString *)overrideKey {
	return RYGCachedOverride(overrideKey);
}

+ (void)setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
	if (!method.overrideKey.length) return;
	NSMutableDictionary *overrides = [RYGPersistedOverrides() mutableCopy];
	if (value) overrides[method.overrideKey] = @([value boolValue]);
	else [overrides removeObjectForKey:method.overrideKey];
	[NSUserDefaults.standardUserDefaults setObject:overrides.copy forKey:kRYGRuntimeOverridesKey];
	RYGRefreshOverrideCache();
	if (value) RYGInstallOverrideKey(method.overrideKey);
}

+ (void)reinstallPersistedOverrides {
	RYGRefreshOverrideCache();
	for (NSString *key in gRYGOverrideCache) RYGInstallOverrideKey(key);
}

@end

// Only exact user-created override keys are restored. There is no constructor
// scan and no persisted/preloaded runtime table. dyld callbacks retry the exact
// keys when their owning framework is loaded later in the launch sequence.
static void RYGSchedulePersistedOverrideReinstall(void) {
	@synchronized(RYGRuntimeBrowserEngine.class) {
		if (gRYGReinstallScheduled) return;
		gRYGReinstallScheduled = YES;
	}
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			@synchronized(RYGRuntimeBrowserEngine.class) { gRYGReinstallScheduled = NO; }
			[RYGRuntimeBrowserEngine reinstallPersistedOverrides];
		});
}

static void RYGRuntimeImageDidLoad(const struct mach_header *header, intptr_t slide) {
	(void)header;
	(void)slide;
	RYGSchedulePersistedOverrideReinstall();
}

__attribute__((constructor)) static void RYGRuntimeOverrideBootstrap(void) {
	@autoreleasepool {
		RYGRefreshOverrideCache();
		_dyld_register_func_for_add_image(RYGRuntimeImageDidLoad);
		RYGSchedulePersistedOverrideReinstall();
	}
}
