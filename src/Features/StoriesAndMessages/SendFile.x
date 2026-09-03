// Send files in DMs — adds a "Send File" option to the plus menu.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/message.h>

static BOOL rygFileMenuPending;
static __weak UIViewController *rygFileThreadVC;
static id rygFilePickerDelegate;

static inline id rygCall(id obj, SEL sel) {
	return (obj && [obj respondsToSelector:sel]) ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

static BOOL rygSendFile(NSURL *url, UIViewController *vc) {
	if (!url || !vc) return NO;

	id fm = [RYGUtils getIvarForObj:vc name:"_featureManager"];
	id fc = rygCall(fm, @selector(messageSenderFeatureController));
	id sender = rygCall(fc, @selector(messageSender));
	id threadKey = rygCall(vc, @selector(threadKey));

	if (!sender || !threadKey) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"File sending not available")];
		return NO;
	}

	SEL sel = @selector(sendFileWithURL:threadKey:attribution:replyMessagePk:quotedPublishedMessage:messageSentSpeedLogger:messageSentSpeedMarker:localSendSpeedLogger:localSendSpeedMarker:);
	if (![sender respondsToSelector:sel]) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"File sending not supported")];
		return NO;
	}

	((void (*)(id, SEL, id, id, id, id, id, id, id, id, id))objc_msgSend)(sender, sel, url, threadKey, nil, nil, nil, nil, nil, nil, nil);
	return YES;
}

@interface _RYGFilePickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *threadVC;
@end

@implementation _RYGFilePickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	(void)controller;

	NSURL *url = urls.firstObject;
	UIViewController *vc = self.threadVC;
	rygFilePickerDelegate = nil;

	if (url && vc) rygSendFile(url, vc);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
	(void)controller;
	rygFilePickerDelegate = nil;
}

@end

static void rygShowFilePicker(UIViewController *vc) {
	if (!vc) return;

	_RYGFilePickerDelegate *delegate = [_RYGFilePickerDelegate new];
	delegate.threadVC = vc;
	rygFilePickerDelegate = delegate;

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
	if (rygFileThreadVC == (UIViewController *)self) rygFileThreadVC = nil;
}

- (void)composerOverflowButtonMenuWillPrepareExpandWithPlusButton:(id)plusButton {
	%orig;

	if (![RYGUtils getBoolPref:@"send_file"]) return;

	rygFileThreadVC = (UIViewController *)self;
	rygFileMenuPending = YES;
}

%end

%hook IGDSMenu

- (id)initWithMenuItems:(NSArray *)items edr:(BOOL)edr headerLabelText:(id)header {
	if (!rygFileMenuPending) return %orig;

	rygFileMenuPending = NO;
	if (![RYGUtils getBoolPref:@"send_file"]) return %orig;

	NSString *title = RYGLocalized(@"Send File");

	for (id item in items) {
		id itemTitle = rygCall(item, @selector(title));
		if ([itemTitle isKindOfClass:NSString.class] && [itemTitle isEqualToString:title]) return %orig;
	}

	Class cls = NSClassFromString(@"IGDSMenuItem");
	SEL sel = @selector(initWithTitle:image:handler:);
	if (!cls || ![cls instancesRespondToSelector:sel]) return %orig;

	UIImage *image = [[UIImage systemImageNamed:@"doc"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	void (^handler)(void) = ^{
		UIViewController *vc = rygFileThreadVC;
		if (vc && vc.view.window) rygShowFilePicker(vc);
	};

	id fileItem = ((id (*)(id, SEL, id, id, id))objc_msgSend)([cls alloc], sel, title, image, handler);
	if (!fileItem) return %orig;

	NSMutableArray *newItems = [NSMutableArray arrayWithObject:fileItem];
	if (items.count) [newItems addObjectsFromArray:items];

	return %orig(newItems, edr, header);
}

%end