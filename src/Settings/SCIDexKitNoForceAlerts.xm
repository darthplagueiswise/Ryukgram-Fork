#import <Foundation/Foundation.h>
#import <objc/message.h>

%hook SCIDexKitViewController
- (void)confirmAndForceDescriptor:(id)descriptor value:(BOOL)value {
    SEL directSetter = NSSelectorFromString(@"setOverrideValue:descriptor:");
    id target = (id)self;
    if (![target respondsToSelector:directSetter]) {
        %orig;
        return;
    }
    ((void (*)(id, SEL, id, id))objc_msgSend)(target, directSetter, @(value), descriptor);
}
%end
