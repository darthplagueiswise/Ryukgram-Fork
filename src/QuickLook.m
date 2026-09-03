#import "QuickLook.h"

@implementation RYGQuickLookDelegate

- (instancetype)initWithPreviewItemURLs:(NSArray<NSURL *> *)urls {
    if ((self = [super init])) {
        _previewItemURLs = [urls copy];
    }
    return self;
}

#pragma mark - QLPreviewControllerDataSource

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return (NSInteger)self.previewItemURLs.count;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.previewItemURLs.count) return nil;
    return self.previewItemURLs[(NSUInteger)index];
}

@end
