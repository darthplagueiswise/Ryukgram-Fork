#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void RYGPresentRuntimeValueEditor(UIViewController *presenter,
                                                    UIView * _Nullable sourceView,
                                                    NSString *className,
                                                    NSString *selectorName,
                                                    BOOL classMethod,
                                                    NSString *typeCode,
                                                    NSString *currentDescription,
                                                    id _Nullable currentRawValue,
                                                    dispatch_block_t _Nullable completion);

NS_ASSUME_NONNULL_END
