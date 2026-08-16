// Drag-to-place editor for any RYGOverlayButtonLayout subclass (story, DM).
// Builds the chips from the layout class, draws a story-style preview, persists
// positions on drag. One screen for every overlay-button surface.

#import "../UI/DragLayout/RYGDragLayoutEditor.h"

@interface RYGOverlayLayoutEditorViewController : RYGDragLayoutEditorViewController
- (instancetype)initWithLayoutClass:(Class)layoutClass;
@end
