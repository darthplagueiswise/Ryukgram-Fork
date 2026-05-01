/*
 * SCIDevOptionsNativeInjector.xm
 * Ryukgram
 *
 * Injects a "Developer Options" row into the native Instagram settings,
 * equivalent to InstaMoon's "Open developer mode" dialog option.
 */

#import "../Utils.h"
#import "SCIDogfoodingMainLauncher.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface IGSettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@end

static BOOL rgEmployeeMasterEnabled(void) { 
    return [SCIUtils getBoolPref:@"igt_employee_master"]; 
}

// Helper to present the developer VC
static void RYPresentDeveloperSettings(UIViewController *presenter) {
    @try {
        Class devCls = NSClassFromString(@"IGDeveloperSettingsViewController");
        if (!devCls) devCls = NSClassFromString(@"IGInternalSettingsViewController");
        
        if (devCls) {
            NSLog(@"[RyukGram][DevInjector] Found developer class: %@", NSStringFromClass(devCls));
            id vc = [[devCls alloc] init];
            
            // Try setIsSessionlessCaaInternal:YES if the selector exists
            SEL internalSel = NSSelectorFromString(@"setIsSessionlessCaaInternal:");
            if ([vc respondsToSelector:internalSel]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(vc, internalSel, YES);
            }
            
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [presenter presentViewController:nav animated:YES completion:nil];
        } else {
            NSLog(@"[RyukGram][DevInjector] Native developer classes not found, falling back to Dogfooding launcher");
            RYDogOpenMainFrom(presenter);
        }
    } @catch (NSException *e) {
        NSLog(@"[RyukGram][DevInjector] Exception presenting dev settings: %@", e);
    }
}

%hook IGSettingsViewController

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger rows = %orig;
    // Inject into the first section if master is ON
    if (rgEmployeeMasterEnabled() && section == 0) {
        return rows + 1;
    }
    return rows;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (rgEmployeeMasterEnabled() && indexPath.section == 0) {
        // Check if this is our injected row (last row of section 0)
        // We call %orig with a safe index to get the row count from original logic if needed, 
        // but here we just need to know if we are at the end.
        NSInteger rowCount = [self tableView:tableView numberOfRowsInSection:indexPath.section];
        if (indexPath.row == rowCount - 1) {
            static NSString *identifier = @"RYDevOptionsCell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            cell.textLabel.text = @"Developer Options";
            cell.detailTextLabel.text = @"Internal Instagram developer settings";
            cell.imageView.image = [UIImage systemImageNamed:@"hammer.fill"];
            return cell;
        }
    }
    return %orig;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (rgEmployeeMasterEnabled() && indexPath.section == 0) {
        NSInteger rowCount = [self tableView:tableView numberOfRowsInSection:indexPath.section];
        if (indexPath.row == rowCount - 1) {
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            NSLog(@"[RyukGram][DevInjector] Developer Options row tapped");
            RYPresentDeveloperSettings(self);
            return;
        }
    }
    %orig;
}

%end
