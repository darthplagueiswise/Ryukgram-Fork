// SCIGalleryViewController (Actions) — file actions, selection-mode bulk
// handlers, folder CRUD, and a few related helpers extracted from
// SCIGalleryViewController.m to keep the main file focused on layout.

#import "SCIGalleryViewController_Internal.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryCoreDataStack.h"
#import "SCIGalleryListCollectionCell.h"
#import "SCIGalleryGridCell.h"
#import "SCIGalleryDeleteViewController.h"
#import "SCIGalleryOriginController.h"
#import "SCIAssetUtils.h"
#import "SCIGalleryShim.h"
#import "../Utils.h"
#import "../PhotoAlbum.h"
#import "../Downloader/Download.h"
#import <CoreData/CoreData.h>
#import <Photos/Photos.h>

static NSString *const kSCIGalleryFoldersKey = @"gallery_folders";

static UIImage *SCIGalleryActionIcon(NSString *name) {
	return [SCIAssetUtils instagramIconNamed:(name.length ? name : @"more") pointSize:17.0];
}

static NSString *SCIGalleryTrimmedName(NSString *name) {
	return [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

static BOOL SCIGalleryPathIsInside(NSString *path, NSString *folder) {
	if (!path.length || !folder.length) return NO;
	return [path isEqualToString:folder] || [path hasPrefix:[folder stringByAppendingString:@"/"]];
}

@implementation SCIGalleryViewController (Actions)

#pragma mark - Origin open

- (void)showGalleryOpenFailureMessage:(NSString *)title actionIdentifier:(NSString *)actionIdentifier {
	[SCIUtils showToastForActionIdentifier:actionIdentifier
								   duration:2.0
									  title:title
								   subtitle:SCILocalized(@"The original content may no longer exist.")
							   iconResource:@"error_filled"
									   tone:SCIFeedbackPillToneError];
}

- (void)dismissGalleryForOriginOpenWithCompletion:(void (^)(void))completion {
	[self.navigationController dismissViewControllerAnimated:YES completion:completion];
}

- (void)openOriginalPostForFile:(SCIGalleryFile *)file {
	if ([SCIGalleryOriginController openOriginalPostForGalleryFile:file]) {
		[self dismissGalleryForOriginOpenWithCompletion:nil];
		return;
	}

	[self showGalleryOpenFailureMessage:SCILocalized(@"Unable to open original post")
					   actionIdentifier:kSCIFeedbackActionGalleryOpenOriginal];
}

- (void)openProfileForFile:(SCIGalleryFile *)file {
	if ([SCIGalleryOriginController openProfileForGalleryFile:file]) {
		[self dismissGalleryForOriginOpenWithCompletion:nil];
		return;
	}

	[self showGalleryOpenFailureMessage:SCILocalized(@"Unable to open profile")
					   actionIdentifier:kSCIFeedbackActionGalleryOpenProfile];
}

#pragma mark - Selection

- (NSArray<SCIGalleryFile *> *)selectedGalleryFiles {
	if (!self.selectedFileIDs.count) return @[];

	NSMutableArray<SCIGalleryFile *> *files = NSMutableArray.array;
	for (SCIGalleryFile *file in [self visibleGalleryFiles]) {
		if (file.identifier.length && [self.selectedFileIDs containsObject:file.identifier]) [files addObject:file];
	}
	return files.copy;
}

- (void)animateSelectionModeTransition {
	for (NSIndexPath *indexPath in self.collectionView.indexPathsForVisibleItems) {
		SCIGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];
		if (!file) continue;

		BOOL selected = [self.selectedFileIDs containsObject:file.identifier];
		UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];

		if ([cell isKindOfClass:SCIGalleryListCollectionCell.class]) {
			SCIGalleryListCollectionCell *listCell = (SCIGalleryListCollectionCell *)cell;
			[listCell setSelectionMode:self.selectionMode selected:selected animated:YES];
			[listCell setMoreActionsMenu:self.selectionMode ? nil : [self fileActionsMenuForFile:file]];
		} else if ([cell isKindOfClass:SCIGalleryGridCell.class]) {
			[(SCIGalleryGridCell *)cell setSelectionMode:self.selectionMode selected:selected animated:YES];
		}
	}
}

- (void)enterSelectionMode {
	self.selectionMode = YES;
	[self.selectedFileIDs removeAllObjects];
	[self refreshNavigationItems];
	[self refreshBottomToolbarItems];
	[self animateSelectionModeTransition];
}

- (void)exitSelectionMode {
	self.selectionMode = NO;
	[self.selectedFileIDs removeAllObjects];
	[self refreshNavigationItems];
	[self refreshBottomToolbarItems];
	[self animateSelectionModeTransition];
}

- (void)toggleSelectionForFile:(SCIGalleryFile *)file {
	if (!file.identifier.length) return;

	if ([self.selectedFileIDs containsObject:file.identifier]) {
		[self.selectedFileIDs removeObject:file.identifier];
	} else {
		[self.selectedFileIDs addObject:file.identifier];
	}

	[self refreshNavigationItems];
	[self.collectionView reloadData];
}

- (void)selectAllVisibleFiles {
	NSArray<SCIGalleryFile *> *files = [self visibleGalleryFiles];
	BOOL allSelected = files.count && self.selectedFileIDs.count == files.count;

	[self.selectedFileIDs removeAllObjects];

	if (!allSelected) {
		for (SCIGalleryFile *file in files) {
			if (file.identifier.length) [self.selectedFileIDs addObject:file.identifier];
		}
	}

	self.navigationItem.rightBarButtonItem.title = (!allSelected && files.count)
		? SCILocalized(@"Deselect All")
		: SCILocalized(@"Select All");

	[self.collectionView reloadData];
}

#pragma mark - Bulk actions

- (void)shareSelectedFiles {
	NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
	if (!files.count) return;

	NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:files.count];
	for (SCIGalleryFile *file in files) {
		if (file.fileURL) [urls addObject:file.fileURL];
	}

	if (!urls.count) return;

	[SCIPhotoAlbum armWatcherIfEnabled];
	UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
	[self presentViewController:vc animated:YES completion:nil];
}

- (void)saveSelectedFilesToPhotos {
	NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
	if (!files.count) return;

	[self sciSaveGalleryFilesToPhotos:files];
	[self exitSelectionMode];
}

- (void)moveSelectedFiles {
	NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
	if (files.count) [self presentMoveSheetForFiles:files];
}

- (void)toggleFavoriteForSelectedFiles {
	NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
	if (!files.count) return;

	BOOL shouldFavorite = NO;
	for (SCIGalleryFile *file in files) {
		if (!file.isFavorite) {
			shouldFavorite = YES;
			break;
		}
	}

	for (SCIGalleryFile *file in files) file.isFavorite = shouldFavorite;

	[[SCIGalleryCoreDataStack shared] saveContext];
	[self refetch];
}

- (void)deleteSelectedFiles {
	NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
	if (!files.count) return;

	NSString *message = [NSString stringWithFormat:SCILocalized(@"This will permanently remove %ld file%@ from the gallery."),
		(long)files.count, files.count == 1 ? @"" : @"s"];

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Delete Selected Files?")
																  message:message
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete")
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		(void)action;

		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		NSError *firstError = nil;

		for (SCIGalleryFile *file in files) {
			NSError *error = nil;
			[file removeWithError:&error];
			if (!firstError && error) firstError = error;
		}

		if (firstError) {
			[SCIUtils showToastForActionIdentifier:kSCIFeedbackActionGalleryDeleteSelected
										  duration:2.0
											 title:SCILocalized(@"Failed to delete")
										  subtitle:firstError.localizedDescription
									  iconResource:@"error_filled"
											  tone:SCIFeedbackPillToneError];
			return;
		}

		[SCIUtils showToastForActionIdentifier:kSCIFeedbackActionGalleryDeleteSelected
									  duration:1.5
										 title:SCILocalized(@"Deleted selected files")
									  subtitle:nil
								  iconResource:@"circle_check_filled"
										  tone:SCIFeedbackPillToneSuccess];

		[self exitSelectionMode];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Photos save

- (void)sciSaveGalleryFilesToPhotos:(NSArray<SCIGalleryFile *> *)files {
	if (!files.count) return;

	[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
		if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Photo library access denied")];
			});
			return;
		}

		BOOL useAlbum = [SCIUtils getBoolPref:@"save_to_ryukgram_album"];
		SCIDownloadPillView *pill = SCIDownloadPillView.shared;
		NSString *ticket = [pill beginTicketWithTitle:SCILocalized(@"Saving...") onCancel:nil];

		__block NSUInteger index = 0;
		__block NSUInteger saved = 0;
		__block void (^next)(void);

		next = ^{
			if (index >= files.count) {
				NSString *message = files.count == 1
					? (useAlbum ? SCILocalized(@"Saved to RyukGram") : SCILocalized(@"Saved to Photos"))
					: [NSString stringWithFormat:SCILocalized(@"Saved %lu items"), (unsigned long)saved];

				[pill finishTicket:ticket successMessage:message];
				next = nil;
				return;
			}

			SCIGalleryFile *file = files[index++];
			NSURL *url = file.fileURL;
			[pill updateTicket:ticket progress:(float)index / (float)files.count];

			void (^done)(BOOL, NSError *) = ^(BOOL ok, NSError *error) {
				if (ok) saved++;
				else NSLog(@"[RyukGram] Gallery save failed: %@", error);
				if (next) next();
			};

			if (!url) {
				done(NO, nil);
				return;
			}

			if (useAlbum) {
				NSURL *temp = [self sciCopyToTemp:url];
				if (!temp) {
					done(NO, nil);
					return;
				}
				[SCIPhotoAlbum saveFileToAlbum:temp completion:done];
				return;
			}

			[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
				NSString *ext = url.pathExtension.lowercaseString;
				BOOL isVideo = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];

				PHAssetCreationRequest *request = PHAssetCreationRequest.creationRequestForAsset;
				PHAssetResourceCreationOptions *options = PHAssetResourceCreationOptions.new;
				options.shouldMoveFile = NO;

				[request addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto)
									  fileURL:url
									 options:options];
				request.creationDate = NSDate.date;
			} completionHandler:done];
		};

		next();
	}];
}

- (NSURL *)sciCopyToTemp:(NSURL *)src {
	if (!src) return nil;

	NSString *ext = src.pathExtension.length ? src.pathExtension : @"bin";
	NSString *name = [NSString stringWithFormat:@"sci_gal_%@.%@", NSUUID.UUID.UUIDString, ext];
	NSURL *dst = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];

	NSError *error = nil;
	if (![NSFileManager.defaultManager copyItemAtURL:src toURL:dst error:&error]) {
		NSLog(@"[RyukGram] Temp copy failed: %@", error);
		return nil;
	}

	return dst;
}

#pragma mark - Menus

- (UIMenu *)fileActionsMenuForFile:(SCIGalleryFile *)file {
	if (!file) return nil;

	__weak typeof(self) weakSelf = self;

	UIAction *(^makeAction)(NSString *, NSString *, UIMenuElementAttributes, void (^)(void)) =
	^UIAction *(NSString *title, NSString *icon, UIMenuElementAttributes attrs, void (^block)(void)) {
		UIAction *action = [UIAction actionWithTitle:title
											   image:SCIGalleryActionIcon(icon)
										  identifier:nil
											 handler:^(UIAction *a) {
			(void)a;
			if (block) block();
		}];
		action.attributes = attrs;
		return action;
	};

	UIAction *favorite = makeAction(file.isFavorite ? SCILocalized(@"Unfavorite") : SCILocalized(@"Favorite"),
									file.isFavorite ? @"heart_filled" : @"heart",
									0, ^{
		file.isFavorite = !file.isFavorite;
		[[SCIGalleryCoreDataStack shared] saveContext];
	});

	UIAction *rename = makeAction(SCILocalized(@"Rename"), @"edit", 0, ^{
		[weakSelf renameFile:file];
	});

	UIAction *move = makeAction(SCILocalized(@"Move to Folder"), @"folder_move", 0, ^{
		[weakSelf moveFile:file];
	});

	UIAction *save = makeAction(SCILocalized(@"Save to Photos"), @"download", 0, ^{
		[weakSelf sciSaveGalleryFilesToPhotos:@[file]];
	});

	UIAction *share = makeAction(SCILocalized(@"Share"), @"share", 0, ^{
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !file.fileURL) return;

		[SCIPhotoAlbum armWatcherIfEnabled];
		UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[file.fileURL] applicationActivities:nil];
		[self presentViewController:vc animated:YES completion:nil];
	});

	UIAction *delete = makeAction(SCILocalized(@"Delete"), @"trash", UIMenuElementAttributesDestructive, ^{
		[weakSelf confirmDeleteFile:file];
	});

	NSMutableArray<UIMenuElement *> *items = NSMutableArray.array;

	if (file.hasOpenableOriginalMedia) {
		[items addObject:makeAction(SCILocalized(@"Open Original Post"), @"external_link", 0, ^{
			[weakSelf openOriginalPostForFile:file];
		})];
	}

	if (file.hasOpenableProfile) {
		[items addObject:makeAction(SCILocalized(@"Open Profile"), @"profile", 0, ^{
			[weakSelf openProfileForFile:file];
		})];
	}

	if (items.count) {
		[items addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[]]];
	}

	[items addObjectsFromArray:@[favorite, rename, move, save, share, delete]];
	return [UIMenu menuWithTitle:@"" children:items];
}

- (UIContextMenuConfiguration *)contextMenuForFile:(SCIGalleryFile *)file {
	__weak typeof(self) weakSelf = self;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil
												   previewProvider:nil
													actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		(void)suggested;
		return [weakSelf fileActionsMenuForFile:file];
	}];
}

- (UIContextMenuConfiguration *)contextMenuForFolder:(NSString *)folderPath {
	__weak typeof(self) weakSelf = self;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil
												   previewProvider:nil
													actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		(void)suggested;

		UIAction *rename = [UIAction actionWithTitle:SCILocalized(@"Rename Folder")
											   image:SCIGalleryActionIcon(@"edit")
										  identifier:nil
											 handler:^(UIAction *a) {
			(void)a;
			[weakSelf renameFolder:folderPath];
		}];

		UIAction *delete = [UIAction actionWithTitle:SCILocalized(@"Delete Folder")
											   image:SCIGalleryActionIcon(@"trash")
										  identifier:nil
											 handler:^(UIAction *a) {
			(void)a;
			[weakSelf deleteFolder:folderPath];
		}];
		delete.attributes = UIMenuElementAttributesDestructive;

		return [UIMenu menuWithTitle:@"" children:@[rename, delete]];
	}];
}

#pragma mark - Delete

- (void)confirmDeleteFile:(SCIGalleryFile *)file {
	if (!file) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Delete from Gallery?")
																  message:SCILocalized(@"This will permanently remove this file from the gallery.")
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete")
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		(void)action;

		NSError *error = nil;
		[file removeWithError:&error];

		[SCIUtils showToastForActionIdentifier:kSCIFeedbackActionGalleryDeleteFile
									  duration:error ? 2.0 : 1.5
										 title:error ? SCILocalized(@"Failed to delete") : SCILocalized(@"Deleted from Gallery")
									  subtitle:error.localizedDescription
								  iconResource:error ? @"error_filled" : @"circle_check_filled"
										  tone:error ? SCIFeedbackPillToneError : SCIFeedbackPillToneSuccess];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - File rename / move

- (void)renameFile:(SCIGalleryFile *)file {
	if (!file) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Rename")
																  message:nil
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.text = file.displayName;
		textField.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;

		NSString *name = SCIGalleryTrimmedName(alert.textFields.firstObject.text);
		file.customName = name.length ? name : nil;

		[[SCIGalleryCoreDataStack shared] saveContext];
		[self.collectionView reloadData];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

- (void)moveFile:(SCIGalleryFile *)file {
	if (file) [self presentMoveSheetForFiles:@[file]];
}

- (void)assignFolderPath:(NSString *)folderPath toFiles:(NSArray<SCIGalleryFile *> *)files {
	if (!files.count) return;

	for (SCIGalleryFile *file in files) file.folderPath = folderPath;

	[[SCIGalleryCoreDataStack shared] saveContext];
	[self refetch];
}

- (void)presentMoveSheetForFiles:(NSArray<SCIGalleryFile *> *)files {
	if (!files.count) return;

	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Move to Folder")
																  message:nil
														   preferredStyle:UIAlertControllerStyleActionSheet];

	__weak typeof(self) weakSelf = self;

	[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Root")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;
		[weakSelf assignFolderPath:nil toFiles:files];
	}]];

	for (NSString *folder in [self allFolderPaths]) {
		[sheet addAction:[UIAlertAction actionWithTitle:folder
												  style:UIAlertActionStyleDefault
												handler:^(UIAlertAction *action) {
			(void)action;
			[weakSelf assignFolderPath:folder toFiles:files];
		}]];
	}

	[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"New folder…")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;

		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"New Folder")
																	  message:nil
															   preferredStyle:UIAlertControllerStyleAlert];

		[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
			textField.placeholder = SCILocalized(@"Folder name");
			textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
		}];

		[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

		[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Create & Move")
												  style:UIAlertActionStyleDefault
												handler:^(UIAlertAction *x) {
			(void)x;

			NSString *name = SCIGalleryTrimmedName(alert.textFields.firstObject.text);
			if (!name.length) return;

			[self assignFolderPath:[self folderPathByAppendingComponent:name toBase:self.currentFolderPath] toFiles:files];
		}]];

		[self presentViewController:alert animated:YES completion:nil];
	}]];

	[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Folder CRUD

- (void)presentCreateFolder {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"New Folder")
																  message:nil
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.placeholder = SCILocalized(@"Folder name");
		textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
	}];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Create")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;

		NSString *name = SCIGalleryTrimmedName(alert.textFields.firstObject.text);
		if (name.length) [self createFolderNamed:name];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

- (void)createFolderNamed:(NSString *)name {
	NSString *path = [self folderPathByAppendingComponent:name toBase:self.currentFolderPath];
	if (!path.length) return;

	NSMutableArray<NSString *> *folders = [self mutablePlaceholderFolders];
	if (![folders containsObject:path]) {
		[folders addObject:path];
		[NSUserDefaults.standardUserDefaults setObject:folders forKey:kSCIGalleryFoldersKey];
	}

	[self reloadSubfolders];
	[self.collectionView reloadData];
	[self updateEmptyState];
}

- (NSString *)folderPathByAppendingComponent:(NSString *)component toBase:(NSString *)base {
	NSString *name = [SCIGalleryTrimmedName(component) stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
	if (!name.length) return nil;
	return base.length ? [base stringByAppendingFormat:@"/%@", name] : [@"/" stringByAppendingString:name];
}

- (void)mergePlaceholderSubfolders {
	NSArray<NSString *> *placeholders = [NSUserDefaults.standardUserDefaults arrayForKey:kSCIGalleryFoldersKey] ?: @[];
	NSString *base = self.currentFolderPath ?: @"";
	NSString *prefix = base.length ? [base stringByAppendingString:@"/"] : @"/";

	NSMutableSet<NSString *> *merged = [NSMutableSet setWithArray:self.subfolders ?: @[]];

	for (NSString *path in placeholders) {
		if (![path hasPrefix:prefix]) continue;

		NSString *rest = [path substringFromIndex:prefix.length];
		if (!rest.length) continue;

		NSString *name = [rest componentsSeparatedByString:@"/"].firstObject;
		if (name.length) [merged addObject:[prefix stringByAppendingString:name]];
	}

	self.subfolders = [merged.allObjects sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (void)renameFolder:(NSString *)folderPath {
	if (!folderPath.length) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Rename Folder")
																  message:nil
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.text = folderPath.lastPathComponent;
		textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
		textField.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Rename")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;

		NSString *name = SCIGalleryTrimmedName(alert.textFields.firstObject.text);
		if (name.length) [self performRenameOfFolder:folderPath toName:name];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

- (void)performRenameOfFolder:(NSString *)oldPath toName:(NSString *)newName {
	NSString *parent = oldPath.stringByDeletingLastPathComponent;
	if (!parent.length || ![parent hasPrefix:@"/"]) parent = [@"/" stringByAppendingString:parent ?: @""];

	NSString *cleanName = [SCIGalleryTrimmedName(newName) stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
	NSString *newPath = [parent isEqualToString:@"/"] ? [@"/" stringByAppendingString:cleanName] : [parent stringByAppendingFormat:@"/%@", cleanName];

	if (!cleanName.length || [oldPath isEqualToString:newPath]) return;

	NSManagedObjectContext *context = SCIGalleryCoreDataStack.shared.viewContext;
	NSFetchRequest *request = [self requestForFilesInFolder:oldPath];
	NSArray<SCIGalleryFile *> *files = [context executeFetchRequest:request error:nil] ?: @[];

	for (SCIGalleryFile *file in files) {
		NSString *current = file.folderPath ?: @"";
		if ([current isEqualToString:oldPath]) file.folderPath = newPath;
		else if ([current hasPrefix:[oldPath stringByAppendingString:@"/"]]) file.folderPath = [newPath stringByAppendingString:[current substringFromIndex:oldPath.length]];
	}

	[context save:nil];
	[self rewritePlaceholderFoldersFrom:oldPath to:newPath remove:NO];
	[self reloadSubfolders];
	[self.collectionView reloadData];
}

- (void)deleteFolder:(NSString *)folderPath {
	if (!folderPath.length) return;

	NSManagedObjectContext *context = SCIGalleryCoreDataStack.shared.viewContext;
	NSInteger count = [context countForFetchRequest:[self requestForFilesInFolder:folderPath] error:nil];

	NSString *message = count
		? [NSString stringWithFormat:SCILocalized(@"This folder contains %ld file(s). They will be moved to the parent folder."), (long)count]
		: SCILocalized(@"This folder is empty.");

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@?", SCILocalized(@"Delete Folder")]
																  message:message
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete")
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		(void)action;
		[self performDeleteFolder:folderPath];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

- (void)performDeleteFolder:(NSString *)folderPath {
	NSString *parent = folderPath.stringByDeletingLastPathComponent;
	if (!parent.length || [parent isEqualToString:@"/"]) parent = nil;

	NSManagedObjectContext *context = SCIGalleryCoreDataStack.shared.viewContext;
	NSArray<SCIGalleryFile *> *files = [context executeFetchRequest:[self requestForFilesInFolder:folderPath] error:nil] ?: @[];

	for (SCIGalleryFile *file in files) file.folderPath = parent;

	[context save:nil];
	[self rewritePlaceholderFoldersFrom:folderPath to:nil remove:YES];
	[self reloadSubfolders];
	[self.collectionView reloadData];
	[self updateEmptyState];
}

#pragma mark - Folder helpers

- (NSFetchRequest *)requestForFilesInFolder:(NSString *)folderPath {
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
	request.predicate = [NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@", folderPath, [folderPath stringByAppendingString:@"/"]];
	return request;
}

- (NSMutableArray<NSString *> *)mutablePlaceholderFolders {
	return [[NSUserDefaults.standardUserDefaults arrayForKey:kSCIGalleryFoldersKey] mutableCopy] ?: NSMutableArray.array;
}

- (void)rewritePlaceholderFoldersFrom:(NSString *)oldPath to:(NSString *)newPath remove:(BOOL)remove {
	NSMutableArray<NSString *> *folders = NSMutableArray.array;

	for (NSString *path in [self mutablePlaceholderFolders]) {
		if (!SCIGalleryPathIsInside(path, oldPath)) {
			[folders addObject:path];
			continue;
		}

		if (!remove && newPath.length) {
			NSString *suffix = [path isEqualToString:oldPath] ? @"" : [path substringFromIndex:oldPath.length];
			[folders addObject:[newPath stringByAppendingString:suffix]];
		}
	}

	[NSUserDefaults.standardUserDefaults setObject:folders forKey:kSCIGalleryFoldersKey];
}

- (NSArray<NSString *> *)allFolderPaths {
	NSManagedObjectContext *context = SCIGalleryCoreDataStack.shared.viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];

	request.resultType = NSDictionaryResultType;
	request.propertiesToFetch = @[@"folderPath"];
	request.returnsDistinctResults = YES;
	request.predicate = [NSPredicate predicateWithFormat:@"folderPath != nil AND folderPath != ''"];

	NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil] ?: @[];
	NSMutableSet<NSString *> *set = NSMutableSet.set;

	for (NSDictionary *row in rows) {
		NSString *path = row[@"folderPath"];
		if (path.length) [set addObject:path];
	}

	[set addObjectsFromArray:[NSUserDefaults.standardUserDefaults arrayForKey:kSCIGalleryFoldersKey] ?: @[]];

	return [set.allObjects sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

@end