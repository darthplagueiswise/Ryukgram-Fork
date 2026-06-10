#import <Foundation/Foundation.h>

// Applies Advanced hooks after the app is already active.
// %ctor only registers a post-launch notification; it does not install hooks
// during dyld/static init or scene-create.
void SCIAdvancedHooksApplyForCurrentPrefs(void);
void SCIAdvancedHooksApplyForChangedKey(NSString *key, BOOL isOn);
