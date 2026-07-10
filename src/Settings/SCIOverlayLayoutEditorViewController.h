// Drag-to-place editor for any SCIOverlayButtonLayout subclass (story, DM).
// Builds the chips from the layout class, draws a story-style preview, persists
// positions on drag. One screen for every overlay-button surface.

#import "../UI/DragLayout/SCIDragLayoutEditor.h"

@interface SCIOverlayLayoutEditorViewController : SCIDragLayoutEditorViewController
- (instancetype)initWithLayoutClass:(Class)layoutClass;
@end
