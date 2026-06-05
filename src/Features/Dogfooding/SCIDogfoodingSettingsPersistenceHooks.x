// SCIDogfoodingSettingsPersistenceHooks.x
//
// Disabled intentionally.
//
// The native IGDirectNotesDogfoodingSettings screen already opens with:
// +[IGDirectNotesDogfoodingSettingsStaticFuncs notesDogfoodingSettingsOpenOnViewController:userSession:]
//
// The previous build hooked IGDogfoodingSettings delegate callbacks:
//   - dogfoodingSettingsToggleCell:didToggle:
//   - dogfoodingSettingsSelectionViewController:updatedOptions:
//
// On Instagram 431/SDK 26.2 those callbacks can be Swift protocol thunks. Hooking
// them with a C IMP is enough to make every Notes option crash as soon as the user
// taps a row. Keep this file as a compile-time no-op so the Makefile's recursive
// source discovery stays stable, but do not hook the native Notes UI.

#import <Foundation/Foundation.h>

%ctor {
    // no-op by design
}
