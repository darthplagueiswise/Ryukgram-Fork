#import "SCISettingsSections.h"
#import "../../Features/DeviceSpoof/SCIDeviceMenu.h"

@implementation SCITweakSettings (Section_Advanced)

+ (SCISetting *)deviceIDNavCell {
	SCISetting *(^btn)(NSString *, NSString *, NSString *, NSString *, void(^)(void)) =
		^(NSString *title, NSString *subtitle, NSString *ig, NSString *sf, void(^action)(void)) {
			return [SCISetting buttonCellWithTitle:title subtitle:subtitle
											  icon:[SCISymbol symbolWithIGName:ig fallback:sf]
											action:action];
		};
	SCISetting *deviceIDCell = [SCISetting navigationCellWithTitle:SCILocalized(@"Device ID")
									  subtitle:@""
										  icon:[SCISymbol symbolWithIGName:@"phone" fallback:@"iphone.gen3"]
								   navSections:@[@{
		@"footer": SCILocalized(@"Masks the identifiers Instagram uses to fingerprint this device: device ID, family device ID, vendor ID and machine ID. Changes apply after a relaunch. The same controls appear on the login screen."),
		@"rows": @[
			btn(SCILocalized(@"Roll a new fingerprint"), SCILocalized(@"Generate fresh device identifiers"),
				@"bcn_refresh_outline_24", @"arrow.triangle.2.circlepath",
				^{ [SCIDeviceMenu presentRollOptionsFrom:sciTopVC() onChange:nil]; }),
			btn(SCILocalized(@"Enter ID manually…"), @"",
				@"bcn_edit_outline_24", @"pencil",
				^{ [SCIDeviceMenu presentCustomIDFrom:sciTopVC() onChange:nil]; }),
			btn(SCILocalized(@"Copy current ID"), @"",
				@"bcn_copy_outline_24", @"doc.on.doc",
				^{ [SCIDeviceMenu copyCurrentID]; }),
			btn(SCILocalized(@"Revert to my real device ID"), SCILocalized(@"Restore the original, stop masking"),
				@"bcn_arrow-ccw_outline_24", @"arrow.uturn.backward",
				^{ [SCIDeviceMenu revertOnChange:nil]; }),
		]
	}, @{
		@"header": SCILocalized(@"Reset"),
		@"footer": SCILocalized(@"Forgets every saved login, cookie and the stored device identity, then relaunches so Instagram starts as a brand-new device. You'll sign in again afterwards."),
		@"rows": @[
			btn(SCILocalized(@"Clear device & relaunch"), SCILocalized(@"Full reset to a brand-new device"),
				@"bcn_trash_outline_24", @"trash",
				^{ [SCIDeviceMenu presentWipeConfirmFrom:sciTopVC()]; }),
		]
	}, @{
		@"header": SCILocalized(@"Apple attestation"),
		@"footer": SCILocalized(@"Blocks Instagram's Apple device attestation (DeviceCheck and App Attest). These are bound to the hardware and can't be changed, so they keep linking the device across resets. Blocking makes Instagram see a device that doesn't support them. Only works while masking is on."),
		@"rows": @[
			[SCISetting switchCellWithTitle:SCILocalized(@"Block Apple device attestation") subtitle:SCILocalized(@"Stop the hardware attestation that links the device") defaultsKey:@"sci_devicespoof_block_devicecheck" requiresRestart:YES],
		]
	}, @{
		@"rows": @[
			[SCISetting switchCellWithTitle:SCILocalized(@"Show button on login screen") subtitle:SCILocalized(@"Floating Device ID button while signed out") defaultsKey:@"sci_devicespoof_login_button" requiresRestart:YES],
		]
	}]
	];
	deviceIDCell.whatsNewID = @"ui_deviceid";
	return deviceIDCell;
}

+ (SCISetting *)advancedNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Advanced")
										   subtitle:@""
											   icon:[SCISymbol symbolWithIGName:@"toolbox" fallback:@"gearshape.2"]
										navSections:@[@{
											@"header": SCILocalized(@"Notifications"),
											@"footer": SCILocalized(@"Suppresses the second notification IG enqueues in-app while the notification extension is also delivering it."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Fix duplicate notifications") subtitle:SCILocalized(@"Prevents two banners for the same message when IG is in the foreground") defaultsKey:@"sci_fix_duplicate_notifications"],
											]
										},
										@{
											@"header": SCILocalized(@"Tweak settings"),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Enable tweak settings quick-access") subtitle:SCILocalized(@"Hold on the home tab to open RyukGram settings") defaultsKey:@"settings_shortcut" requiresRestart:YES],
												[SCISetting switchCellWithTitle:SCILocalized(@"Show tweak settings on app launch") subtitle:SCILocalized(@"Automatically opens settings when the app launches") defaultsKey:@"tweak_settings_app_launch"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Pause playback when opening settings") subtitle:SCILocalized(@"Pauses any playing video/audio when settings opens") defaultsKey:@"settings_pause_playback"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Always show what's new") subtitle:SCILocalized(@"Keep the blue dot on every new feature instead of clearing it once viewed") defaultsKey:@"whatsnew_always_show"],
											]
										},
										@{
											@"header": SCILocalized(@"Cache"),
											@"footer": SCILocalized(@"Clearing still scans on demand."),
											@"rows": @[
												[self clearCacheButtonCell],
												[self autoClearCacheMenuCell],
												[self autoCheckCacheSizeCell],
												[self preserveMessagesDBCell],
											]
										},
										@{
											@"header": SCILocalized(@"Instagram"),
											@"footer": SCILocalized(@"Instagram runs stock while this is on. Turn it back off to restore your settings."),
											@"rows": @[
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable safe mode") subtitle:SCILocalized(@"Prevents Instagram from resetting settings after crashes (at your own risk)") defaultsKey:@"disable_safe_mode"],
												[SCISetting switchCellWithTitle:SCILocalized(@"Hide TestFlight popup") subtitle:SCILocalized(@"Suppresses the \"It's time to update Instagram Beta\" nag") defaultsKey:@"hide_testflight_nag" requiresRestart:YES],
												[SCISetting buttonCellWithTitle:SCILocalized(@"Reset onboarding state")
																		   subtitle:@""
																			   icon:[SCISymbol symbolWithIGName:@"bcn_arrow-ccw_outline_24" fallback:@"arrow.counterclockwise.circle"]
																			 action:^(void) { [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SCInstaFirstRun"]; [SCIUtils showRestartConfirmation];}
												],
												[SCISetting switchCellWithTitle:SCILocalized(@"Disable all tweak options") subtitle:SCILocalized(@"Turn every feature off — your settings are kept") defaultsKey:@"sci_disable_all" requiresRestart:YES],
											]
										},
										@{
											@"rows": @[
												[self deviceIDNavCell],
											]
										},
										@{
											@"header": SCILocalized(@"Advanced experimental features"),
											@"footer": SCILocalized(@"Toggle hidden Instagram experiments. Some may not work on every account or IG version."),
											@"rows": @[
												[self experimentalEntryCell],
											]
										}]
				];
}

@end
