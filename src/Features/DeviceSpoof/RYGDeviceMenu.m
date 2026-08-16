#import "RYGDeviceMenu.h"
#import "RYGDeviceIdentity.h"
#import "../../Utils.h"

static void RYGToast(NSString *title, NSString *subtitle) {
    [RYGUtils showToastForDuration:2.2 title:title subtitle:subtitle];
}

@implementation RYGDeviceMenu

+ (void)presentCustomIDFrom:(UIViewController *)host onChange:(void (^)(void))onChange {
    if (!host) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:RYGLocalized(@"Manual device ID")
        message:RYGLocalized(@"Paste or type the UUID this device should report.")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.text = [RYGDeviceIdentity effectiveDeviceID];
    }];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Apply")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [RYGDeviceIdentity setCustomDeviceID:a.textFields.firstObject.text];
            if (onChange) onChange();
            RYGToast(RYGLocalized(@"Device ID set"), RYGLocalized(@"Relaunch to apply"));
        }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
        style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:a animated:YES completion:nil];
}

+ (void)presentWipeConfirmFrom:(UIViewController *)host {
    if (!host) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:RYGLocalized(@"Clear device & relaunch?")
        message:RYGLocalized(@"Forgets every saved login, cookie and the stored device identity, then relaunches so Instagram starts as a brand-new device. You'll sign in again afterwards.")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Clear & relaunch")
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
            [RYGDeviceIdentity wipeDeviceDataAndTerminate];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
        style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:a animated:YES completion:nil];
}

+ (void)presentRelaunchConfirmFrom:(UIViewController *)host {
    if (!host) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:RYGLocalized(@"New fingerprint ready")
        message:RYGLocalized(@"Relaunch Instagram now so the new device identity applies from a clean start?")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Relaunch now")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { exit(0); }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Later")
        style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:a animated:YES completion:nil];
}

+ (void)presentRollOptionsFrom:(UIViewController *)host onChange:(void (^)(void))onChange {
    if (!host) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:RYGLocalized(@"New device fingerprint")
        message:RYGLocalized(@"Rolls a fresh device ID, family device ID, vendor ID and clears the machine ID so Instagram re-registers as a new device. Or also wipe saved logins for a full reset.")
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Roll new ID")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [RYGDeviceIdentity generateNewIdentity];
            if (onChange) onChange();
            [self presentRelaunchConfirmFrom:host];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Roll + clear IG data")
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
            [RYGDeviceIdentity freshSpoofedDeviceAndTerminate];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
        style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:a animated:YES completion:nil];
}

+ (void)revertOnChange:(void (^)(void))onChange {
    [RYGDeviceIdentity disableSpoofing];
    if (onChange) onChange();
    RYGToast(RYGLocalized(@"Spoofing off"), RYGLocalized(@"Relaunch to apply"));
}

+ (void)copyCurrentID {
    [UIPasteboard generalPasteboard].string = [RYGDeviceIdentity effectiveDeviceID];
    RYGToast(RYGLocalized(@"Copied"), nil);
}

@end
