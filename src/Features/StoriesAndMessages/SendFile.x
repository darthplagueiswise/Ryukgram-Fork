// Send files in DMs — adds a "Send File" option to the plus menu.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/message.h>

static BOOL sciFileMenuPending;
static __weak UIViewController *sciFileThreadVC;
static id sciFilePickerDelegate;

static inline id sciCall(id obj, SEL sel) {
	return (obj && [obj respondsToSelector:sel]) ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

static BOOL sciSendFile(NSURL *url, UIViewController *vc) {
	if (!url || !vc) return NO;

	id fm = [SCIUtils getIvarForObj:vc name:"_featureManager"];
	id fc = sciCall(fm, @selector(messageSenderFeatureController));
	id sender = sciCall(fc, @selector(messageSender));
	id threadKey = sciCall(vc, @selector(threadKey));

	if (!sender || !threadKey) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"File sending not available")];
		return NO;
	}

	SEL sel = @selector(sendFileWithURL:threadKey:attribution:replyMessagePk:quotedPublishedMessage:messageSentSpeedLogger:messageSentSpeedMarker:localSendSpeedLogger:localSendSpeedMarker:);
	if (![sender respondsToSelector:sel]) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"File sending not supported")];
		return NO;
	}

	((void (*)(id, SEL, id, id, id, id, id, id, id, id, id))objc_msgSend)(sender, sel, url, threadKey, nil, nil, nil, nil, nil, nil, nil);
	return YES;
}

@interface _SCIFilePickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *threadVC;
@end

@implementation _SCIFilePickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	(void)controller;

	NSURL *url = urls.firstObject;
	UIViewController *vc = self.threadVC;
	sciFilePickerDelegate = nil;

	if (url && vc) sciSendFile(url, vc);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
	(void)controller;
	sciFilePickerDelegate = nil;
}

@end

static void sciShowFilePicker(UIViewController *vc) {
	if (!vc) return;

	_SCIFilePickerDelegate *delegate = [_SCIFilePickerDelegate new];
	delegate.threadVC = vc;
	sciFilePickerDelegate = delegate;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop

	picker.delegate = delegate;
	picker.allowsMultipleSelection = NO;
	[vc presentViewController:picker animated:YES completion:nil];
}

%hook IGDirectThreadViewController

- (void)viewDidDisappear:(BOOL)animated {
	%orig;
	if (sciFileThreadVC == (UIViewController *)self) sciFileThreadVC = nil;
}

- (void)composerOverflowButtonMenuWillPrepareExpandWithPlusButton:(id)plusButton {
	%orig;

	if (![SCIUtils getBoolPref:@"send_file"]) return;

	sciFileThreadVC = (UIViewController *)self;
	sciFileMenuPending = YES;
}

%end

%hook IGDSMenu

- (id)initWithMenuItems:(NSArray *)items edr:(BOOL)edr headerLabelText:(id)header {
	if (!sciFileMenuPending) return %orig;

	sciFileMenuPending = NO;
	if (![SCIUtils getBoolPref:@"send_file"]) return %orig;

	NSString *title = SCILocalized(@"Send File");

	for (id item in items) {
		id itemTitle = sciCall(item, @selector(title));
		if ([itemTitle isKindOfClass:NSString.class] && [itemTitle isEqualToString:title]) return %orig;
	}

	Class cls = NSClassFromString(@"IGDSMenuItem");
	SEL sel = @selector(initWithTitle:image:handler:);
	if (!cls || ![cls instancesRespondToSelector:sel]) return %orig;

	UIImage *image = [[UIImage systemImageNamed:@"doc"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	void (^handler)(void) = ^{
		UIViewController *vc = sciFileThreadVC;
		if (vc && vc.view.window) sciShowFilePicker(vc);
	};

	id fileItem = ((id (*)(id, SEL, id, id, id))objc_msgSend)([cls alloc], sel, title, image, handler);
	if (!fileItem) return %orig;

	NSMutableArray *newItems = [NSMutableArray arrayWithObject:fileItem];
	if (items.count) [newItems addObjectsFromArray:items];

	return %orig(newItems, edr, header);
}

%end
