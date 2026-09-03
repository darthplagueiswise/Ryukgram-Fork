#import "RYGSettingsSections.h"
#import "../../Features/DeviceSpoof/RYGDeviceMenu.h"

@implementation RYGTweakSettings (Section_Advanced)

+ (RYGSetting *)deviceIDNavCell {
	RYGSetting *(^btn)(NSString *, NSString *, NSString *, NSString *, void(^)(void)) =
		^(NSString *title, NSString *subtitle, NSString *ig, NSString *sf, void(^action)(void)) {
			return [RYGSetting buttonCellWithTitle:title subtitle:subtitle
											  icon:[RYGSymbol symbolWithIGName:ig fallback:sf]
											action:action];
		};
	RYGSetting *deviceIDCell = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Device ID")
									  subtitle:@""
										  icon:[RYGSymbol symbolWithIGName:@"phone" fallback:@"iphone.gen3"]
								   navSections:@[@{
		@"footer": RYGLocalized(@"Masks the identifiers Instagram uses to fingerprint this device: device ID, family device ID, vendor ID and machine ID. Changes apply after a relaunch. The same controls appear on the login screen."),
		@"rows": @[
			btn(RYGLocalized(@"Roll a new fingerprint"), RYGLocalized(@"Generate fresh device identifiers"),
				@"bcn_refresh_outline_24", @"arrow.triangle.2.circlepath",
				^{ [RYGDeviceMenu presentRollOptionsFrom:rygTopVC() onChange:nil]; }),
			btn(RYGLocalized(@"Enter ID manually…"), @"",
				@"bcn_edit_outline_24", @"pencil",
				^{ [RYGDeviceMenu presentCustomIDFrom:rygTopVC() onChange:nil]; }),
			btn(RYGLocalized(@"Copy current ID"), @"",
				@"bcn_copy_outline_24", @"doc.on.doc",
				^{ [RYGDeviceMenu copyCurrentID]; }),
			btn(RYGLocalized(@"Revert to my real device ID"), RYGLocalized(@"Restore the original, stop masking"),
				@"bcn_arrow-ccw_outline_24", @"arrow.uturn.backward",
				^{ [RYGDeviceMenu revertOnChange:nil]; }),
		]
	}, @{
		@"header": RYGLocalized(@"Machine ID"),
		@"footer": RYGLocalized(@"Issued by Instagram and format-checked by the server, so it can only be kept, never made up. RyukGram pins the one you were issued so Instagram can't swap it."),
		@"rows": @[
			btn(RYGLocalized(@"Enter machine ID manually…"), RYGLocalized(@"Restore a saved one, or clear it to re-register"),
				@"bcn_edit_outline_24", @"pencil",
				^{ [RYGDeviceMenu presentCustomMachineIDFrom:rygTopVC() onChange:nil]; }),
			btn(RYGLocalized(@"Copy machine ID"), @"",
				@"bcn_copy_outline_24", @"doc.on.doc",
				^{ [RYGDeviceMenu copyMachineID]; }),
		]
	}, @{
		@"header": RYGLocalized(@"Reset"),
		@"rows": @[
			btn(RYGLocalized(@"Mask everything & relaunch"), RYGLocalized(@"Fresh IDs, blocked attestation, cleared logins"),
				@"bcn_shield_outline_24", @"shield.lefthalf.filled",
				^{ [RYGDeviceMenu presentMaskEverythingConfirmFrom:rygTopVC()]; }),
			btn(RYGLocalized(@"Clear device & relaunch"), RYGLocalized(@"Full reset to a brand-new device"),
				@"bcn_trash_outline_24", @"trash",
				^{ [RYGDeviceMenu presentWipeConfirmFrom:rygTopVC()]; }),
		]
	}, @{
		@"header": RYGLocalized(@"Apple attestation"),
		@"footer": RYGLocalized(@"Blocks Instagram's Apple device attestation (DeviceCheck and App Attest). These are bound to the hardware and can't be changed, so they keep linking the device across resets. Blocking makes Instagram see a device that doesn't support them. Only works while masking is on."),
		@"rows": @[
			[RYGSetting switchCellWithTitle:RYGLocalized(@"Block Apple device attestation") subtitle:RYGLocalized(@"Stop the hardware attestation that links the device") defaultsKey:@"ryg_devicespoof_block_devicecheck" requiresRestart:YES],
		]
	}, @{
		@"rows": @[
			[RYGSetting switchCellWithTitle:RYGLocalized(@"Show button on login screen") subtitle:RYGLocalized(@"Floating Device ID button while signed out") defaultsKey:@"ryg_devicespoof_login_button" requiresRestart:YES],
		]
	}]
	];
	deviceIDCell.whatsNewID = @"ui_deviceid";
	return deviceIDCell;
}

+ (RYGSetting *)advancedNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Advanced")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"toolbox" fallback:@"gearshape.2"]
										navSections:@[@{
											@"header": RYGLocalized(@"Notifications"),
											@"footer": RYGLocalized(@"Suppresses the second notification IG enqueues in-app while the notification extension is also delivering it."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Fix duplicate notifications") subtitle:RYGLocalized(@"Prevents two banners for the same message when IG is in the foreground") defaultsKey:@"ryg_fix_duplicate_notifications"],
											]
										},
										@{
											@"header": RYGLocalized(@"Tweak settings"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable tweak settings quick-access") subtitle:RYGLocalized(@"Hold on the home tab to open RyukGram settings") defaultsKey:@"settings_shortcut" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Show tweak settings on app launch") subtitle:RYGLocalized(@"Automatically opens settings when the app launches") defaultsKey:@"tweak_settings_app_launch"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Pause playback when opening settings") subtitle:RYGLocalized(@"Pauses any playing video/audio when settings opens") defaultsKey:@"settings_pause_playback"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Always show what's new") subtitle:RYGLocalized(@"Keep the blue dot on every new feature instead of clearing it once viewed") defaultsKey:@"whatsnew_always_show"],
											]
										},
										@{
											@"header": RYGLocalized(@"Cache"),
											@"footer": RYGLocalized(@"Clearing still scans on demand."),
											@"rows": @[
												[self clearCacheButtonCell],
												[self autoClearCacheMenuCell],
												[self autoCheckCacheSizeCell],
												[self preserveMessagesDBCell],
											]
										},
										@{
											@"header": RYGLocalized(@"Instagram"),
											@"footer": RYGLocalized(@"Instagram runs stock while this is on. Turn it back off to restore your settings."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable safe mode") subtitle:RYGLocalized(@"Prevents Instagram from resetting settings after crashes (at your own risk)") defaultsKey:@"disable_safe_mode"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide TestFlight popup") subtitle:RYGLocalized(@"Suppresses the \"It's time to update Instagram Beta\" nag") defaultsKey:@"hide_testflight_nag" requiresRestart:YES],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Reset onboarding state")
																		   subtitle:@""
																			   icon:[RYGSymbol symbolWithIGName:@"bcn_arrow-ccw_outline_24" fallback:@"arrow.counterclockwise.circle"]
																			 action:^(void) { [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"RyukGramFirstRun"]; [RYGUtils showRestartConfirmation];}
												],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Disable all tweak options") subtitle:RYGLocalized(@"Turn every feature off — your settings are kept") defaultsKey:@"ryg_disable_all" requiresRestart:YES],
											]
										},
										@{
											@"rows": @[
												[self deviceIDNavCell],
											]
										},
										@{
											@"header": RYGLocalized(@"Advanced experimental features"),
											@"footer": RYGLocalized(@"Toggle hidden Instagram experiments. Some may not work on every account or IG version."),
											@"rows": @[
												[self experimentalEntryCell],
											]
										}]
				];
}

@end
