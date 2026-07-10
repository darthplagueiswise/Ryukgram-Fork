// Reusable drag-to-place editor: drop chips on a canvas, snap on release; caller persists positions via onChange.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, SCIDragLayoutSnap) {
	SCIDragLayoutSnapNone   = 0,
	SCIDragLayoutSnapEdges  = 1 << 0,
	SCIDragLayoutSnapCenter = 1 << 1,
	SCIDragLayoutSnapGrid   = 1 << 2,
	SCIDragLayoutSnapAll    = SCIDragLayoutSnapEdges | SCIDragLayoutSnapCenter | SCIDragLayoutSnapGrid,
};

@interface SCIDragLayoutItem : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, strong, nullable) UIImage *icon;
@property (nonatomic, assign) CGFloat diameter;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) CGPoint position;
@property (nonatomic, assign) CGPoint homePosition;   // (-1,-1) = none
@property (nonatomic, assign) BOOL disabled;
+ (instancetype)itemWithIdentifier:(NSString *)identifier icon:(nullable UIImage *)icon title:(nullable NSString *)title position:(CGPoint)position;
@end

@interface SCIDragLayoutEditorViewController : UIViewController

- (instancetype)initWithItems:(NSArray<SCIDragLayoutItem *> *)items;

@property (nonatomic, strong, nullable) UIView *backgroundContentView;
@property (nonatomic, assign) CGFloat canvasAspect;
@property (nonatomic, assign) CGFloat canvasCornerRadius;
@property (nonatomic, assign) SCIDragLayoutSnap snapMask;
@property (nonatomic, assign) NSInteger gridDivisions;
@property (nonatomic, assign) UIEdgeInsets placeableInsets;
@property (nonatomic, assign) CGFloat minimumSpacing;
@property (nonatomic, copy, nullable) NSArray<NSValue *> *slots;   // non-empty → slot mode: nearest bubble, one chip each, swaps on conflict
@property (nonatomic, assign) BOOL showsSlots;
@property (nonatomic, assign) BOOL scalesItemsToCanvas;   // YES only when chips are real on-screen buttons; NO keeps abstract chips their own size
@property (nonatomic, copy, nullable) NSString *instructions;

@property (nonatomic, copy, nullable) void (^onChange)(NSArray<SCIDragLayoutItem *> *items);
@property (nonatomic, copy, nullable) void (^onReset)(void);

@property (nonatomic, copy, readonly) NSArray<SCIDragLayoutItem *> *items;
- (void)applyItems:(NSArray<SCIDragLayoutItem *> *)items;

@end

NS_ASSUME_NONNULL_END
