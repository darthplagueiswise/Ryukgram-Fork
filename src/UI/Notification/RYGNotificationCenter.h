#import <UIKit/UIKit.h>
#import "RYGNotificationPillView.h"
#import "RYGNotificationActions.h"

NS_ASSUME_NONNULL_BEGIN

@class RYGNotificationHandle;

@interface RYGNotificationCenter : NSObject

+ (instancetype)shared;

- (void)notifyAction:(NSString *)actionID
               title:(NSString *)title
            subtitle:(nullable NSString *)subtitle
                icon:(nullable NSString *)iconSymbol
                tone:(RYGNotificationTone)tone;

- (void)notifyAction:(NSString *)actionID
               title:(NSString *)title
            subtitle:(nullable NSString *)subtitle
                icon:(nullable NSString *)iconSymbol
                tone:(RYGNotificationTone)tone
            duration:(NSTimeInterval)duration;

- (void)notifyAction:(NSString *)actionID
               title:(NSString *)title
            subtitle:(nullable NSString *)subtitle
                icon:(nullable NSString *)iconSymbol
                tone:(RYGNotificationTone)tone
            duration:(NSTimeInterval)duration
               onTap:(nullable void (^)(void))onTap;

- (void)notifyError:(NSString *)actionID
              title:(NSString *)title
            message:(nullable NSString *)message;

// Returns nil when the action's surface is "off". IG-native is forced to pill
// for progress because the IG toast presenter has no progress affordance.
- (nullable RYGNotificationHandle *)beginProgressForAction:(NSString *)actionID
                                                     title:(NSString *)title
                                                  onCancel:(nullable void (^)(void))onCancel;

// Indeterminate loading pill. Caller flips to determinate via [handle setProgress:].
- (nullable RYGNotificationHandle *)beginLoadingForAction:(NSString *)actionID
                                                    title:(NSString *)title
                                                 onCancel:(nullable void (^)(void))onCancel;

- (void)dismissAll;

// Provider is re-invoked per fire; return nil to leave the pill non-interactive.
// Explicit `onTap:` on the call overrides the provider.
- (void)setDefaultTapProvider:(void (^ _Nullable (^ _Nullable)(void))(void))provider
                    forAction:(NSString *)actionID;

// Same, plus an owner VC class — tap no-ops when an instance of that class
// is already anywhere in the presentation chain.
- (void)setDefaultTapProvider:(void (^ _Nullable (^ _Nullable)(void))(void))provider
                 ownerVCClass:(nullable Class)ownerClass
                    forAction:(NSString *)actionID;

// Per-action pref defaults (notif_action_<id> = "default") — merged into
// RYGRegisterDefaultsOnce so picker rows resolve to "Default" on first launch.
+ (NSDictionary<NSString *, NSString *> *)defaultPerActionPrefs;

// Settings preview hooks.
- (void)presentPreviewWithTone:(RYGNotificationTone)tone;
- (void)presentPreviewDownloadEndingWithError:(BOOL)endWithError;
- (void)presentPreviewLoadingEndingWithError:(BOOL)endWithError;

@end


@interface RYGNotificationHandle : NSObject

@property (nonatomic, readonly, copy) NSString *actionID;
@property (nonatomic, assign, readonly) BOOL isFinished;

- (void)setProgress:(float)progress;
- (void)setIndeterminate:(BOOL)indeterminate;
- (void)setTitle:(NSString *)title;
- (void)setSubtitle:(nullable NSString *)subtitle;

// Terminal transitions — pill lingers ~1.2s then auto-dismisses.
- (void)success:(nullable NSString *)title;
- (void)success:(nullable NSString *)title subtitle:(nullable NSString *)subtitle;
- (void)error:(nullable NSString *)title;
- (void)error:(nullable NSString *)title subtitle:(nullable NSString *)subtitle;
- (void)cancelled:(nullable NSString *)title;

- (void)dismiss;

@end


// C-style convenience callable from any TU (auto-imported via RYGPrefix.h).
FOUNDATION_EXPORT void RYGNotify(NSString *actionID, NSString *title, NSString * _Nullable subtitle, NSString * _Nullable iconSymbol, RYGNotificationTone tone);
FOUNDATION_EXPORT void RYGNotifySuccess(NSString *actionID, NSString *title, NSString * _Nullable subtitle);
FOUNDATION_EXPORT void RYGNotifyInfo(NSString *actionID, NSString *title, NSString * _Nullable subtitle);
FOUNDATION_EXPORT void RYGNotifyError(NSString *actionID, NSString *title, NSString * _Nullable message);
FOUNDATION_EXPORT void RYGNotifyWarning(NSString *actionID, NSString *title, NSString * _Nullable message);
FOUNDATION_EXPORT void RYGNotifyTap(NSString *actionID, NSString *title, NSString * _Nullable subtitle, NSString * _Nullable iconSymbol, RYGNotificationTone tone, void (^ _Nullable onTap)(void));
FOUNDATION_EXPORT RYGNotificationHandle * _Nullable RYGNotifyProgress(NSString *actionID, NSString *title, void (^ _Nullable onCancel)(void));
FOUNDATION_EXPORT RYGNotificationHandle * _Nullable RYGNotifyLoading(NSString *actionID, NSString *title, void (^ _Nullable onCancel)(void));

NS_ASSUME_NONNULL_END
