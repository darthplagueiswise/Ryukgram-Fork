// Reusable drag-to-place editor: drop chips on a canvas, snap on release; caller persists positions via onChange.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, RYGDragLayoutSnap) {
	RYGDragLayoutSnapNone   = 0,
	RYGDragLayoutSnapEdges  = 1 << 0,
	RYGDragLayoutSnapCenter = 1 << 1,
	RYGDragLayoutSnapGrid   = 1 << 2,
	RYGDragLayoutSnapAll    = RYGDragLayoutSnapEdges | RYGDragLayoutSnapCenter | RYGDragLayoutSnapGrid,
};

@interface RYGDragLayoutItem : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, strong, nullable) UIImage *icon;
@property (nonatomic, assign) CGFloat diameter;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) CGFloat cornerRadius;   // >0 → render as a width×diameter rounded rectangle (e.g. a video/PiP window)
@property (nonatomic, assign) CGPoint position;
@property (nonatomic, assign) CGPoint homePosition;   // (-1,-1) = none
@property (nonatomic, assign) BOOL disabled;
+ (instancetype)itemWithIdentifier:(NSString *)identifier icon:(nullable UIImage *)icon title:(nullable NSString *)title position:(CGPoint)position;
@end

@interface RYGDragLayoutEditorViewController : UIViewController

- (instancetype)initWithItems:(NSArray<RYGDragLayoutItem *> *)items;

@property (nonatomic, strong, nullable) UIView *backgroundContentView;
@property (nonatomic, assign) CGFloat canvasAspect;
@property (nonatomic, assign) CGFloat canvasCornerRadius;
@property (nonatomic, assign) RYGDragLayoutSnap snapMask;
@property (nonatomic, assign) NSInteger gridDivisions;
@property (nonatomic, assign) UIEdgeInsets placeableInsets;
@property (nonatomic, assign) UIEdgeInsets canvasOutsetFractions;
@property (nonatomic, assign) CGFloat minimumSpacing;
@property (nonatomic, copy, nullable) NSArray<NSValue *> *slots;   // non-empty → slot mode: nearest bubble, one chip each, swaps on conflict
@property (nonatomic, assign) BOOL showsSlots;
@property (nonatomic, assign) BOOL scalesItemsToCanvas;
@property (nonatomic, assign) CGFloat referenceWidth;
@property (nonatomic, copy, nullable) NSString *instructions;

@property (nonatomic, copy, nullable) void (^onChange)(NSArray<RYGDragLayoutItem *> *items);
@property (nonatomic, copy, nullable) void (^onReset)(void);

@property (nonatomic, copy, readonly) NSArray<RYGDragLayoutItem *> *items;
- (void)applyItems:(NSArray<RYGDragLayoutItem *> *)items;

@end

NS_ASSUME_NONNULL_END
