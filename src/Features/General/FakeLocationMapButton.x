// Quick fake-location toggle injected into IG's Friends Map (DMs > Maps).

#import "../../Utils.h"
#import "../../RYGChrome.h"
#import "../../Settings/RYGFakeLocationSettingsVC.h"
#import "../../Settings/RYGFakeLocationPickerVC.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static const NSInteger kRYGMapButtonTag = 0x5C1F4B;
static const NSInteger kRYGMapHitTag = 0x5C1F4C;

static NSString *const kRYGMapPrefShowButton = @"show_fake_location_map_button";
static NSString *const kRYGMapPrefEnabled = @"fake_location_enabled";
static NSString *const kRYGMapPrefLat = @"fake_location_lat";
static NSString *const kRYGMapPrefLon = @"fake_location_lon";
static NSString *const kRYGMapPrefName = @"fake_location_name";
static NSString *const kRYGMapPrefPresets = @"fake_location_presets";

static BOOL RYGMapButtonEnabled(void) {
	return [RYGUtils getBoolPref:kRYGMapPrefShowButton];
}

static BOOL RYGFakeLocationEnabled(void) {
	return [RYGUtils getBoolPref:kRYGMapPrefEnabled];
}

static CLLocationCoordinate2D RYGCurrentFakeCoordinate(void) {
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	return CLLocationCoordinate2DMake([[defaults objectForKey:kRYGMapPrefLat] doubleValue], [[defaults objectForKey:kRYGMapPrefLon] doubleValue]);
}

static UIViewController *RYGPresenterFromView(UIView *view) {
	UIResponder *responder = view;

	while (responder) {
		if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
		responder = responder.nextResponder;
	}

	UIWindow *window = view.window ?: UIApplication.sharedApplication.keyWindow;
	UIViewController *controller = window.rootViewController;

	while (controller.presentedViewController) {
		controller = controller.presentedViewController;
	}

	return controller;
}

static NSHashTable<UIView *> *RYGMapViews(void) {
	static NSHashTable *table;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		table = [NSHashTable weakObjectsHashTable];
	});

	return table;
}

static void RYGRegisterMapView(UIView *mapView) {
	if (mapView) [RYGMapViews() addObject:mapView];
}

static void RYGRemoveMapButton(UIView *mapView) {
	[[mapView viewWithTag:kRYGMapButtonTag] removeFromSuperview];
	[[mapView viewWithTag:kRYGMapHitTag] removeFromSuperview];
}

static void RYGRefreshMapButton(UIView *mapView);

static void RYGRefreshKnownMapButtons(void) {
	for (UIView *mapView in RYGMapViews().allObjects) {
		if (!mapView.window) continue;

		if (!RYGMapButtonEnabled()) {
			RYGRemoveMapButton(mapView);
		} else {
			RYGRefreshMapButton(mapView);
		}
	}
}

static void RYGOpenSettings(UIView *sourceView) {
	UIViewController *presenter = RYGPresenterFromView(sourceView);
	if (!presenter) return;

	RYGFakeLocationSettingsVC *controller = [RYGFakeLocationSettingsVC new];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
	nav.modalPresentationStyle = UIModalPresentationFormSheet;

	[presenter presentViewController:nav animated:YES completion:nil];
}

static void RYGOpenPickerForCurrentLocation(UIView *sourceView) {
	UIViewController *presenter = RYGPresenterFromView(sourceView);
	if (!presenter) return;

	RYGFakeLocationPickerVC *controller = [RYGFakeLocationPickerVC new];
	controller.initialCoord = RYGCurrentFakeCoordinate();
	controller.titleText = RYGLocalized(@"Set location");

	controller.onPick = ^(double lat, double lon, NSString *name) {
		NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
		[defaults setObject:@(lat) forKey:kRYGMapPrefLat];
		[defaults setObject:@(lon) forKey:kRYGMapPrefLon];
		[defaults setObject:(name ?: @"") forKey:kRYGMapPrefName];
		[defaults setBool:YES forKey:kRYGMapPrefEnabled];
		RYGRefreshKnownMapButtons();
	};

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;

	[presenter presentViewController:nav animated:YES completion:nil];
}

static void RYGOpenPickerForNewPreset(UIView *sourceView) {
	UIViewController *presenter = RYGPresenterFromView(sourceView);
	if (!presenter) return;

	RYGFakeLocationPickerVC *controller = [RYGFakeLocationPickerVC new];
	controller.initialCoord = RYGCurrentFakeCoordinate();
	controller.titleText = RYGLocalized(@"Add preset");

	__weak UIView *weakSource = sourceView;

	controller.onPick = ^(double lat, double lon, NSString *name) {
		UIViewController *top = RYGPresenterFromView(weakSource);
		if (!top) return;

		UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Save preset") message:nil preferredStyle:UIAlertControllerStyleAlert];

		[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
			textField.placeholder = RYGLocalized(@"Name");
			textField.text = name;
		}];

		[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

		[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
			NSString *presetName = alert.textFields.firstObject.text.length ? alert.textFields.firstObject.text : name;
			if (!presetName.length) presetName = RYGLocalized(@"Preset");

			NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
			NSArray *rawPresets = [defaults objectForKey:kRYGMapPrefPresets];
			NSMutableArray *presets = [rawPresets isKindOfClass:NSArray.class] ? rawPresets.mutableCopy : NSMutableArray.array;

			[presets addObject:@{@"name": presetName, @"lat": @(lat), @"lon": @(lon)}];
			[defaults setObject:presets.copy forKey:kRYGMapPrefPresets];

			RYGRefreshKnownMapButtons();
			RYGNotifySuccess(RYG_NOTIF_SETTINGS_ACTION, [NSString stringWithFormat:RYGLocalized(@"Saved preset \"%@\""), presetName], nil);
		}]];

		[top presentViewController:alert animated:YES completion:nil];
	};

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;

	[presenter presentViewController:nav animated:YES completion:nil];
}

static UIMenu *RYGBuildMapMenu(UIView *sourceView) {
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

	BOOL enabled = [defaults boolForKey:kRYGMapPrefEnabled];
	NSString *name = [defaults objectForKey:kRYGMapPrefName];
	if (!name.length) name = RYGLocalized(@"Unset");

	UIAction *current = [UIAction actionWithTitle:[NSString stringWithFormat:RYGLocalized(@"Current: %@"), name] image:[UIImage systemImageNamed:@"mappin.and.ellipse"] identifier:nil handler:^(__unused UIAction *action) {}];
	current.attributes = UIMenuElementAttributesDisabled;

	UIAction *toggle = [UIAction actionWithTitle:enabled ? RYGLocalized(@"Disable") : RYGLocalized(@"Enable") image:[UIImage systemImageNamed:enabled ? @"location.slash.fill" : @"location.fill"] identifier:nil handler:^(__unused UIAction *action) {
		[defaults setBool:!enabled forKey:kRYGMapPrefEnabled];
		RYGRefreshKnownMapButtons();
	}];

	if (enabled) toggle.attributes = UIMenuElementAttributesDestructive;

	UIAction *change = [UIAction actionWithTitle:RYGLocalized(@"Change location") image:[UIImage systemImageNamed:@"map"] identifier:nil handler:^(__unused UIAction *action) {
		RYGOpenPickerForCurrentLocation(sourceView);
	}];

	UIMenu *mainSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[current, toggle, change]];

	NSMutableArray<UIMenuElement *> *presetItems = NSMutableArray.array;
	NSArray *presets = [defaults objectForKey:kRYGMapPrefPresets];

	if ([presets isKindOfClass:NSArray.class]) {
		for (NSDictionary *preset in presets) {
			if (![preset isKindOfClass:NSDictionary.class]) continue;

			NSString *presetName = preset[@"name"];
			if (!presetName.length) presetName = RYGLocalized(@"Preset");

			BOOL active = [presetName isEqualToString:name];

			UIAction *presetAction = [UIAction actionWithTitle:presetName image:[UIImage systemImageNamed:@"mappin.circle.fill"] identifier:nil handler:^(__unused UIAction *action) {
				[defaults setObject:preset[@"lat"] forKey:kRYGMapPrefLat];
				[defaults setObject:preset[@"lon"] forKey:kRYGMapPrefLon];
				[defaults setObject:(preset[@"name"] ?: @"") forKey:kRYGMapPrefName];
				[defaults setBool:YES forKey:kRYGMapPrefEnabled];
				RYGRefreshKnownMapButtons();
			}];

			if (active) presetAction.state = UIMenuElementStateOn;
			[presetItems addObject:presetAction];
		}
	}

	[presetItems addObject:[UIAction actionWithTitle:RYGLocalized(@"Add location") image:[UIImage systemImageNamed:@"plus.circle.fill"] identifier:nil handler:^(__unused UIAction *action) {
		RYGOpenPickerForNewPreset(sourceView);
	}]];

	UIMenu *presetSection = [UIMenu menuWithTitle:RYGLocalized(@"Saved locations") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:presetItems];

	UIAction *settings = [UIAction actionWithTitle:RYGLocalized(@"Settings") image:[UIImage systemImageNamed:@"gearshape.fill"] identifier:nil handler:^(__unused UIAction *action) {
		RYGOpenSettings(sourceView);
	}];

	UIMenu *settingsSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[settings]];

	return [UIMenu menuWithTitle:RYGLocalized(@"Fake location") image:nil identifier:nil options:0 children:@[mainSection, presetSection, settingsSection]];
}

static void RYGAddMapButton(UIView *mapView) {
	if (!mapView) return;

	RYGRegisterMapView(mapView);

	if (!RYGMapButtonEnabled()) {
		RYGRemoveMapButton(mapView);
		return;
	}

	if ([mapView viewWithTag:kRYGMapButtonTag] && [mapView viewWithTag:kRYGMapHitTag]) return;

	BOOL enabled = RYGFakeLocationEnabled();

	RYGChromeButton *chrome = [[RYGChromeButton alloc] initWithSymbol:enabled ? @"location.fill" : @"location.slash" pointSize:18.0 diameter:48.0];
	chrome.tag = kRYGMapButtonTag;
	chrome.bubbleColor = UIColor.secondarySystemBackgroundColor;
	chrome.iconTint = enabled ? UIColor.systemGreenColor : UIColor.labelColor;
	chrome.layer.shadowColor = UIColor.blackColor.CGColor;
	chrome.layer.shadowOpacity = 0.18;
	chrome.layer.shadowRadius = 5.0;
	chrome.layer.shadowOffset = CGSizeMake(0.0, 2.0);
	chrome.userInteractionEnabled = NO;

	[mapView addSubview:chrome];

	[NSLayoutConstraint activateConstraints:@[
		[chrome.leadingAnchor constraintEqualToAnchor:mapView.leadingAnchor constant:16.0],
		[chrome.topAnchor constraintEqualToAnchor:mapView.safeAreaLayoutGuide.topAnchor constant:78.0],
		[chrome.widthAnchor constraintEqualToConstant:48.0],
		[chrome.heightAnchor constraintEqualToConstant:48.0],
	]];

	UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
	hit.tag = kRYGMapHitTag;
	hit.backgroundColor = UIColor.clearColor;
	hit.translatesAutoresizingMaskIntoConstraints = NO;
	hit.showsMenuAsPrimaryAction = YES;
	hit.menu = RYGBuildMapMenu(hit);

	[hit addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
		UIButton *sender = (UIButton *)[mapView viewWithTag:kRYGMapHitTag];
		if ([sender isKindOfClass:UIButton.class]) sender.menu = RYGBuildMapMenu(sender);
	}] forControlEvents:UIControlEventMenuActionTriggered];

	[mapView addSubview:hit];

	[NSLayoutConstraint activateConstraints:@[
		[hit.leadingAnchor constraintEqualToAnchor:chrome.leadingAnchor],
		[hit.trailingAnchor constraintEqualToAnchor:chrome.trailingAnchor],
		[hit.topAnchor constraintEqualToAnchor:chrome.topAnchor],
		[hit.bottomAnchor constraintEqualToAnchor:chrome.bottomAnchor],
	]];

	[mapView bringSubviewToFront:chrome];
	[mapView bringSubviewToFront:hit];
}

static void RYGRefreshMapButton(UIView *mapView) {
	if (!mapView) return;

	if (!RYGMapButtonEnabled()) {
		RYGRemoveMapButton(mapView);
		return;
	}

	RYGChromeButton *button = (RYGChromeButton *)[mapView viewWithTag:kRYGMapButtonTag];

	if (![button isKindOfClass:RYGChromeButton.class]) {
		RYGAddMapButton(mapView);
		return;
	}

	BOOL enabled = RYGFakeLocationEnabled();

	button.symbolName = enabled ? @"location.fill" : @"location.slash";
	button.iconTint = enabled ? UIColor.systemGreenColor : UIColor.labelColor;

	UIView *hit = [mapView viewWithTag:kRYGMapHitTag];
	if (hit) [mapView bringSubviewToFront:hit];
}

static void (*orig_IGFriendsMapView_layoutSubviews)(UIView *, SEL);

static void hook_IGFriendsMapView_layoutSubviews(UIView *self, SEL _cmd) {
	orig_IGFriendsMapView_layoutSubviews(self, _cmd);

	RYGRegisterMapView(self);

	if (!RYGMapButtonEnabled()) {
		RYGRemoveMapButton(self);
		return;
	}

	RYGAddMapButton(self);
	RYGRefreshMapButton(self);
}

static void RYGInstallFriendsMapHooks(void) {
	static BOOL installed = NO;
	if (installed) return;

	Class mapClass = NSClassFromString(@"IGFriendsMapCoreUI.IGFriendsMapView");
	if (!mapClass) mapClass = NSClassFromString(@"_TtC18IGFriendsMapCoreUI16IGFriendsMapView");
	if (!mapClass) return;

	Method method = class_getInstanceMethod(mapClass, @selector(layoutSubviews));
	if (!method) return;

	installed = YES;

	MSHookMessageEx(mapClass, @selector(layoutSubviews), (IMP)hook_IGFriendsMapView_layoutSubviews, (IMP *)&orig_IGFriendsMapView_layoutSubviews);
}

%ctor {
	RYGInstallFriendsMapHooks();

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		RYGInstallFriendsMapHooks();
	});

	[NSNotificationCenter.defaultCenter addObserverForName:@"RYGFakeLocationMapBtnPrefChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
		RYGRefreshKnownMapButtons();
	}];
}