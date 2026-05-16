#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static void RYAllFLEXingShowExplorer(void) {
    Class managerClass = NSClassFromString(@"FLEXManager");
    if (!managerClass) return;

    SEL sharedSelector = NSSelectorFromString(@"sharedManager");
    if (![managerClass respondsToSelector:sharedSelector]) return;

    id manager = ((id (*)(Class, SEL))objc_msgSend)(managerClass, sharedSelector);
    SEL showSelector = NSSelectorFromString(@"showExplorer");
    if (manager && [manager respondsToSelector:showSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(manager, showSelector);
    }
}

__attribute__((constructor))
static void RYAllFLEXingInit(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:@"RyukGramShowFLEXExplorerNotification"
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *note) {
            RYAllFLEXingShowExplorer();
        }];
    }
}
