// Drag-to-place editor for any RYGOverlayButtonLayout subclass (story, DM).

#import "../UI/DragLayout/RYGDragLayoutEditor.h"

@interface RYGOverlayLayoutEditorViewController : RYGDragLayoutEditorViewController
- (instancetype)initWithLayoutClass:(Class)layoutClass;
@end
