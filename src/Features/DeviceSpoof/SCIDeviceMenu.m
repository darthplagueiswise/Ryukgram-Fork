#import "SCIDeviceMenu.h"
#import "SCIDeviceIdentity.h"
#import "../../Utils.h"

static void SCIToast(NSString *title, NSString *subtitle) {
    [SCIUtils showToastForDuration:2.2 title:title subtitle:subtitle];
}

@implementation SCIDeviceMenu

+ (void)presentCustomIDFrom:(UIViewController *)host onChange:(void (^)(void))onChange {
    if (!host) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"Manual device ID")
        message:SCILocalized(@"Paste or type the UUID this device should report.")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.text = [SCIDeviceIdentity effectiveDeviceID];
    }];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Apply")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [SCIDeviceIdentity setCustomDeviceID:a.textFields.firstObject.text];
            if (onChange) onChange();
            SCIToast(SCILocalized(@"Device ID set"), SCILocalized(@"Relaunch to apply"));
        }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
        style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:a animated:YES completion:nil];
}

+ (void)presentWipeConfirmFrom:(UIViewController *)host {
    if (!host) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"Clear device & relaunch?")
        message:SCILocalized(@"Forgets every saved login, cookie and the stored device identity, then relaunches so Instagram starts as a brand-new device. You'll sign in again afterwards.")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Clear & relaunch")
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
            [SCIDeviceIdentity wipeDeviceDataAndTerminate];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
        style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:a animated:YES completion:nil];
}

+ (void)presentRelaunchConfirmFrom:(UIViewController *)host {
    if (!host) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"New fingerprint ready")
        message:SCILocalized(@"Relaunch Instagram now so the new device identity applies from a clean start?")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Relaunch now")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { exit(0); }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Later")
        style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:a animated:YES completion:nil];
}

+ (void)presentRollOptionsFrom:(UIViewController *)host onChange:(void (^)(void))onChange {
    if (!host) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"New device fingerprint")
        message:SCILocalized(@"Rolls a fresh device ID, family device ID, vendor ID and clears the machine ID so Instagram re-registers as a new device. Or also wipe saved logins for a full reset.")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Roll new ID")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [SCIDeviceIdentity generateNewIdentity];
            if (onChange) onChange();
            [self presentRelaunchConfirmFrom:host];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Roll + clear IG data")
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
            [SCIDeviceIdentity freshSpoofedDeviceAndTerminate];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
        style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:a animated:YES completion:nil];
}

+ (void)revertOnChange:(void (^)(void))onChange {
    [SCIDeviceIdentity disableSpoofing];
    if (onChange) onChange();
    SCIToast(SCILocalized(@"Spoofing off"), SCILocalized(@"Relaunch to apply"));
}

+ (void)copyCurrentID {
    [UIPasteboard generalPasteboard].string = [SCIDeviceIdentity effectiveDeviceID];
    SCIToast(SCILocalized(@"Copied"), nil);
}

@end
