#import <Foundation/Foundation.h>
#import <objc/message.h>

%hook SCIDexKitViewController
- (void)confirmAndForceDescriptor:(id)descriptor value:(BOOL)value {
    SEL directSetter = NSSelectorFromString(@"setOverrideValue:descriptor:");
    if ([self respondsToSelector:directSetter]) {
        void (*send)(id, SEL, id, id) = (void (*)(id, SEL, id, id))objc_msgSend;
        send(self, directSetter, @(value), descriptor);
        return;
    }
    %orig;
}
%end
