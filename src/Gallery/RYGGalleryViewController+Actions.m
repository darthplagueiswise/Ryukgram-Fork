#import "RYGGalleryViewController_Internal.h"
#import "RYGGalleryFile.h"
#import "RYGGalleryCoreDataStack.h"
#import "RYGGalleryListCollectionCell.h"
#import "RYGGalleryGridCell.h"
#import "RYGGalleryDeleteViewController.h"
#import "RYGGalleryOriginController.h"
#import "../RYGProfileOpener.h"
#import "RYGAssetUtils.h"
#import "RYGGalleryShim.h"
#import "../Utils.h"
#import "../PhotoAlbum.h"
#import "../Downloader/Download.h"
#import <CoreData/CoreData.h>
#import <Photos/Photos.h>

static NSString *const kRYGGalleryFoldersKey = @"gallery_folders";

static UIImage *RYGGalleryActionIcon(NSString *name) {
	return [RYGAssetUtils instagramIconNamed:(name.length ? name : @"more") pointSize:17.0];
}

static NSString *RYGGalleryTrimmedName(NSString *name) {
	return [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

static BOOL RYGGalleryPathIsInside(NSString *path, NSString *folder) {
	if (!path.length || !folder.length) return NO;
	return [path isEqualToString:folder] || [path hasPrefix:[folder stringByAppendingString:@"/"]];
}

@implementation RYGGalleryViewController (Actions)

#pragma mark - Origin open

- (void)showGalleryOpenFailureMessage:(NSString *)title actionIdentifier:(NSString *)actionIdentifier {
	[RYGUtils showToastForActionIdentifier:actionIdentifier
								   duration:2.0
									  title:title
								   subtitle:RYGLocalized(@"The original content may no longer exist.")
							   iconResource:@"error_filled"
									   tone:RYGFeedbackPillToneError];
}

- (void)dismissGalleryForOriginOpenWithCompletion:(void (^)(void))completion {
	[self.navigationController dismissViewControllerAnimated:YES completion:completion];
}

- (void)openOriginalPostForFile:(RYGGalleryFile *)file {
	if ([RYGGalleryOriginController openOriginalPostForGalleryFile:file]) {
		[self dismissGalleryForOriginOpenWithCompletion:nil];
		return;
	}

	[self showGalleryOpenFailureMessage:RYGLocalized(@"Unable to open original post")
					   actionIdentifier:kRYGFeedbackActionGalleryOpenOriginal];
}

- (void)openProfileForFile:(RYGGalleryFile *)file {
	if (file.sourceUserPK.length || file.sourceUsername.length) {
		if ([RYGProfileOpener openProfileForPK:file.sourceUserPK username:file.sourceUsername from:self]) return;
	}

	[self showGalleryOpenFailureMessage:RYGLocalized(@"Unable to open profile")
					   actionIdentifier:kRYGFeedbackActionGalleryOpenProfile];
}

#pragma mark - Selection

- (NSArray<RYGGalleryFile *> *)selectedGalleryFiles {
	if (!self.selectedFileIDs.count) return @[];

	NSMutableArray<RYGGalleryFile *> *files = NSMutableArray.array;
	for (RYGGalleryFile *file in [self visibleGalleryFiles]) {
		if (file.identifier.length && [self.selectedFileIDs containsObject:file.identifier]) [files addObject:file];
	}
	return files.copy;
}

- (void)animateSelectionModeTransition {
	for (NSIndexPath *indexPath in self.collectionView.indexPathsForVisibleItems) {
		RYGGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];
		if (!file) continue;

		BOOL selected = [self.selectedFileIDs containsObject:file.identifier];
		UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];

		if ([cell isKindOfClass:RYGGalleryListCollectionCell.class]) {
			RYGGalleryListCollectionCell *listCell = (RYGGalleryListCollectionCell *)cell;
			[listCell setSelectionMode:self.selectionMode selected:selected animated:YES];
			[listCell setMoreActionsMenu:self.selectionMode ? nil : [self fileActionsMenuForFile:file]];
		} else if ([cell isKindOfClass:RYGGalleryGridCell.class]) {
			[(RYGGalleryGridCell *)cell setSelectionMode:self.selectionMode selected:selected animated:YES];
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

- (void)toggleSelectionForFile:(RYGGalleryFile *)file {
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
	NSArray<RYGGalleryFile *> *files = [self visibleGalleryFiles];
	BOOL allSelected = files.count && self.selectedFileIDs.count == files.count;

	[self.selectedFileIDs removeAllObjects];

	if (!allSelected) {
		for (RYGGalleryFile *file in files) {
			if (file.identifier.length) [self.selectedFileIDs addObject:file.identifier];
		}
	}

	self.navigationItem.rightBarButtonItem.title = (!allSelected && files.count)
		? RYGLocalized(@"Deselect All")
		: RYGLocalized(@"Select All");

	[self.collectionView reloadData];
}

- (void)selectAllFilesInDisplaySection:(NSInteger)displaySection {
	NSArray *sections = self.fetchedResultsController.sections;
	NSInteger frc = [self realSectionForOrderedIndex:(displaySection - [self folderSectionOffset])];
	if (frc < 0 || frc >= (NSInteger)sections.count) return;

	if (!self.selectionMode) [self enterSelectionMode];

	id<NSFetchedResultsSectionInfo> info = sections[frc];
	for (NSInteger i = 0; i < (NSInteger)info.numberOfObjects; i++) {
		RYGGalleryFile *file = [self.fetchedResultsController objectAtIndexPath:[NSIndexPath indexPathForItem:i inSection:frc]];
		if (file.identifier.length) [self.selectedFileIDs addObject:file.identifier];
	}

	[self refreshNavigationItems];
	[self.collectionView reloadData];
}

#pragma mark - Bulk actions

// Share under the file's display name, not its on-disk `<epochMs>_` name — via a hardlink, no copy.
- (NSURL *)rygShareURLForGalleryFile:(RYGGalleryFile *)file {
	NSURL *src = file.fileURL;
	if (!src) return nil;
	NSString *clean = file.exportFilename;
	if (!clean.length || [src.lastPathComponent isEqualToString:clean]) return src;
	NSURL *dst = [RYGTempFiles claimNamedFile:clean ttl:600 tag:@"galshare"];
	NSFileManager *fm = NSFileManager.defaultManager;
	if ([fm linkItemAtURL:src toURL:dst error:nil] || [fm copyItemAtURL:src toURL:dst error:nil]) return dst;
	[RYGTempFiles releaseURL:dst];
	return src;
}

- (void)shareSelectedFiles {
	NSArray<RYGGalleryFile *> *files = [self selectedGalleryFiles];
	if (!files.count) return;

	NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:files.count];
	for (RYGGalleryFile *file in files) {
		NSURL *shareURL = [self rygShareURLForGalleryFile:file];
		if (shareURL) [urls addObject:shareURL];
	}

	if (!urls.count) return;

	[RYGPhotoAlbum armWatcherIfEnabled];
	UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
	[self presentViewController:vc animated:YES completion:nil];
}

- (void)saveSelectedFilesToPhotos {
	NSArray<RYGGalleryFile *> *files = [self selectedGalleryFiles];
	if (!files.count) return;

	[self rygSaveGalleryFilesToPhotos:files];
	[self exitSelectionMode];
}

- (void)moveSelectedFiles {
	NSArray<RYGGalleryFile *> *files = [self selectedGalleryFiles];
	if (files.count) [self presentMoveSheetForFiles:files];
}

- (void)toggleFavoriteForSelectedFiles {
	NSArray<RYGGalleryFile *> *files = [self selectedGalleryFiles];
	if (!files.count) return;

	BOOL shouldFavorite = NO;
	for (RYGGalleryFile *file in files) {
		if (!file.isFavorite) {
			shouldFavorite = YES;
			break;
		}
	}

	for (RYGGalleryFile *file in files) file.isFavorite = shouldFavorite;

	[[RYGGalleryCoreDataStack shared] saveContext];
	[self refetch];
}

- (void)deleteSelectedFiles {
	NSArray<RYGGalleryFile *> *files = [self selectedGalleryFiles];
	if (!files.count) return;

	NSString *message = [NSString stringWithFormat:RYGLocalized(@"This will permanently remove %ld file%@ from the gallery."),
		(long)files.count, files.count == 1 ? @"" : @"s"];

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Delete Selected Files?")
																  message:message
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete")
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		(void)action;

		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		NSError *firstError = nil;

		for (RYGGalleryFile *file in files) {
			NSError *error = nil;
			[file removeWithError:&error];
			if (!firstError && error) firstError = error;
		}

		if (firstError) {
			[RYGUtils showToastForActionIdentifier:kRYGFeedbackActionGalleryDeleteSelected
										  duration:2.0
											 title:RYGLocalized(@"Failed to delete")
										  subtitle:firstError.localizedDescription
									  iconResource:@"error_filled"
											  tone:RYGFeedbackPillToneError];
			return;
		}

		[RYGUtils showToastForActionIdentifier:kRYGFeedbackActionGalleryDeleteSelected
									  duration:1.5
										 title:RYGLocalized(@"Deleted selected files")
									  subtitle:nil
								  iconResource:@"circle_check_filled"
										  tone:RYGFeedbackPillToneSuccess];

		[self exitSelectionMode];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Photos save

- (void)rygSaveGalleryFilesToPhotos:(NSArray<RYGGalleryFile *> *)files {
	if (!files.count) return;

	[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
		dispatch_async(dispatch_get_main_queue(), ^{
		if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
			[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Photo library access denied")];
			return;
		}

		BOOL useAlbum = [RYGUtils getBoolPref:@"save_to_ryukgram_album"];
		RYGDownloadPillView *pill = RYGDownloadPillView.shared;
		NSString *ticket = [pill beginTicketWithTitle:RYGLocalized(@"Saving…") onCancel:nil];

		__block NSUInteger index = 0;
		__block NSUInteger saved = 0;
		__block void (^next)(void);

		next = ^{
			if (index >= files.count) {
				NSString *message = files.count == 1
					? (useAlbum ? RYGLocalized(@"Saved to RyukGram") : RYGLocalized(@"Saved to Photos"))
					: [NSString stringWithFormat:RYGLocalized(@"Saved %lu items"), (unsigned long)saved];

				[pill finishTicket:ticket successMessage:message];
				next = nil;
				return;
			}

			RYGGalleryFile *file = files[index++];
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
				NSURL *temp = [self rygCopyToTemp:url];
				if (!temp) {
					done(NO, nil);
					return;
				}
				[RYGPhotoAlbum saveFileToAlbum:temp originalFilename:file.exportFilename completion:done];
				return;
			}

			[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
				NSString *ext = url.pathExtension.lowercaseString;
				BOOL isVideo = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];

				PHAssetCreationRequest *request = PHAssetCreationRequest.creationRequestForAsset;
				PHAssetResourceCreationOptions *options = PHAssetResourceCreationOptions.new;
				options.shouldMoveFile = NO;
				options.originalFilename = file.exportFilename;

				[request addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto)
									  fileURL:url
									 options:options];
				request.creationDate = NSDate.date;
			} completionHandler:done];
		};

		next();
		});
	}];
}

- (NSURL *)rygCopyToTemp:(NSURL *)src {
	if (!src) return nil;

	NSString *ext = src.pathExtension.length ? src.pathExtension : @"bin";
	NSURL *dst = [RYGTempFiles claimWithExt:ext ttl:600 tag:@"gal"];

	NSError *error = nil;
	if (![NSFileManager.defaultManager copyItemAtURL:src toURL:dst error:&error]) {
		NSLog(@"[RyukGram] Temp copy failed: %@", error);
		[RYGTempFiles releaseURL:dst];
		return nil;
	}

	return dst;
}

#pragma mark - Menus

- (UIMenu *)fileActionsMenuForFile:(RYGGalleryFile *)file {
	if (!file) return nil;

	__weak typeof(self) weakSelf = self;

	UIAction *(^makeAction)(NSString *, NSString *, UIMenuElementAttributes, void (^)(void)) =
	^UIAction *(NSString *title, NSString *icon, UIMenuElementAttributes attrs, void (^block)(void)) {
		UIAction *action = [UIAction actionWithTitle:title
											   image:RYGGalleryActionIcon(icon)
										  identifier:nil
											 handler:^(UIAction *a) {
			(void)a;
			if (block) block();
		}];
		action.attributes = attrs;
		return action;
	};

	UIAction *favorite = makeAction(file.isFavorite ? RYGLocalized(@"Unfavorite") : RYGLocalized(@"Favorite"),
									file.isFavorite ? @"heart_filled" : @"heart",
									0, ^{
		file.isFavorite = !file.isFavorite;
		[[RYGGalleryCoreDataStack shared] saveContext];
	});

	UIAction *rename = makeAction(RYGLocalized(@"Rename"), @"edit", 0, ^{
		[weakSelf renameFile:file];
	});

	UIAction *move = makeAction(RYGLocalized(@"Move to Folder"), @"folder_move", 0, ^{
		[weakSelf moveFile:file];
	});

	UIAction *save = makeAction(RYGLocalized(@"Save to Photos"), @"download", 0, ^{
		[weakSelf rygSaveGalleryFilesToPhotos:@[file]];
	});

	UIAction *share = makeAction(RYGLocalized(@"Share"), @"share", 0, ^{
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !file.fileURL) return;

		NSURL *shareURL = [self rygShareURLForGalleryFile:file] ?: file.fileURL;
		[RYGPhotoAlbum armWatcherIfEnabled];
		UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[shareURL] applicationActivities:nil];
		[self presentViewController:vc animated:YES completion:nil];
	});

	UIAction *delete = makeAction(RYGLocalized(@"Delete"), @"trash", UIMenuElementAttributesDestructive, ^{
		[weakSelf confirmDeleteFile:file];
	});

	NSMutableArray<UIMenuElement *> *items = NSMutableArray.array;

	if (file.hasOpenableOriginalMedia) {
		[items addObject:makeAction(RYGLocalized(@"Open Original Post"), @"external_link", 0, ^{
			[weakSelf openOriginalPostForFile:file];
		})];
	}

	if (file.hasOpenableProfile) {
		[items addObject:makeAction(RYGLocalized(@"Open profile"), @"profile", 0, ^{
			[weakSelf openProfileForFile:file];
		})];
	}

	if (items.count) {
		[items addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[]]];
	}

	[items addObjectsFromArray:@[favorite, rename, move, save, share, delete]];
	return [UIMenu menuWithTitle:[self menuHeaderForFile:file] children:items];
}

- (NSString *)menuHeaderForFile:(RYGGalleryFile *)file {
	NSMutableArray<NSString *> *parts = NSMutableArray.array;

	if (file.dateAdded) {
		static NSDateFormatter *fmt;
		static dispatch_once_t once;
		dispatch_once(&once, ^{
			fmt = [NSDateFormatter new];
			fmt.dateStyle = NSDateFormatterMediumStyle;
			fmt.timeStyle = NSDateFormatterShortStyle;
		});
		[parts addObject:[fmt stringFromDate:file.dateAdded]];
	}

	NSString *source = [file shortSourceLabel];
	if (source.length) [parts addObject:source];

	if (file.fileSize > 0) {
		[parts addObject:[NSByteCountFormatter stringFromByteCount:file.fileSize countStyle:NSByteCountFormatterCountStyleFile]];
	}

	return [parts componentsJoinedByString:@" · "];
}

- (UIContextMenuConfiguration *)contextMenuForFile:(RYGGalleryFile *)file {
	__weak typeof(self) weakSelf = self;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil
												   previewProvider:nil
													actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		(void)suggested;
		return [weakSelf fileActionsMenuForFile:file];
	}];
}

- (UIContextMenuConfiguration *)contextMenuForUserFolder:(NSString *)username {
	__weak typeof(self) weakSelf = self;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil
												   previewProvider:nil
													actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		(void)suggested;

		UIAction *open = [UIAction actionWithTitle:RYGLocalized(@"Open")
											 image:RYGGalleryActionIcon(@"folder")
										identifier:nil
										   handler:^(UIAction *a) {
			(void)a;
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;

			RYGGalleryViewController *child = [[RYGGalleryViewController alloc] initWithUsernameScope:username];
			[self.navigationController pushViewController:child animated:YES];
		}];

		UIAction *delete = [UIAction actionWithTitle:RYGLocalized(@"Delete all files")
											   image:RYGGalleryActionIcon(@"trash")
										  identifier:nil
											 handler:^(UIAction *a) {
			(void)a;
			[weakSelf confirmDeleteUserFolder:username];
		}];
		delete.attributes = UIMenuElementAttributesDestructive;

		return [UIMenu menuWithTitle:[@"@" stringByAppendingString:username] children:@[open, delete]];
	}];
}

- (void)confirmDeleteUserFolder:(NSString *)username {
	if (!username.length) return;

	NSManagedObjectContext *context = RYGGalleryCoreDataStack.shared.viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];
	request.predicate = [NSPredicate predicateWithFormat:@"sourceUsername == %@", username];
	NSInteger count = [context countForFetchRequest:request error:nil];

	NSString *message = [NSString stringWithFormat:RYGLocalized(@"This will permanently remove %ld file(s)."), (long)count];

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:RYGLocalized(@"Delete %@?"), [@"@" stringByAppendingString:username]]
																  message:message
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete")
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		(void)action;
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		NSArray<RYGGalleryFile *> *files = [context executeFetchRequest:request error:nil] ?: @[];

		for (RYGGalleryFile *file in files) [file removeWithError:nil];

		[context save:nil];
		[self reloadSubfolders];
		[self.collectionView reloadData];
		[self updateEmptyState];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

- (UIContextMenuConfiguration *)contextMenuForFolder:(NSString *)folderPath {
	__weak typeof(self) weakSelf = self;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil
												   previewProvider:nil
													actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		(void)suggested;

		UIAction *rename = [UIAction actionWithTitle:RYGLocalized(@"Rename Folder")
											   image:RYGGalleryActionIcon(@"edit")
										  identifier:nil
											 handler:^(UIAction *a) {
			(void)a;
			[weakSelf renameFolder:folderPath];
		}];

		UIAction *delete = [UIAction actionWithTitle:RYGLocalized(@"Delete Folder")
											   image:RYGGalleryActionIcon(@"trash")
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

- (void)confirmDeleteFile:(RYGGalleryFile *)file {
	if (!file) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Delete from Gallery?")
																  message:RYGLocalized(@"This will permanently remove this file from the gallery.")
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete")
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		(void)action;

		NSError *error = nil;
		[file removeWithError:&error];

		[RYGUtils showToastForActionIdentifier:kRYGFeedbackActionGalleryDeleteFile
									  duration:error ? 2.0 : 1.5
										 title:error ? RYGLocalized(@"Failed to delete") : RYGLocalized(@"Deleted from Gallery")
									  subtitle:error.localizedDescription
								  iconResource:error ? @"error_filled" : @"circle_check_filled"
										  tone:error ? RYGFeedbackPillToneError : RYGFeedbackPillToneSuccess];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - File rename / move

- (void)renameFile:(RYGGalleryFile *)file {
	if (!file) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Rename")
																  message:nil
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.text = file.displayName;
		textField.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;

		NSString *name = RYGGalleryTrimmedName(alert.textFields.firstObject.text);
		file.customName = name.length ? name : nil;

		[[RYGGalleryCoreDataStack shared] saveContext];
		[self.collectionView reloadData];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

- (void)moveFile:(RYGGalleryFile *)file {
	if (file) [self presentMoveSheetForFiles:@[file]];
}

- (void)assignFolderPath:(NSString *)folderPath toFiles:(NSArray<RYGGalleryFile *> *)files {
	if (!files.count) return;

	for (RYGGalleryFile *file in files) file.folderPath = folderPath;

	[[RYGGalleryCoreDataStack shared] saveContext];
	[self refetch];
}

- (void)presentMoveSheetForFiles:(NSArray<RYGGalleryFile *> *)files {
	if (!files.count) return;

	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Move to Folder")
																  message:nil
														   preferredStyle:UIAlertControllerStyleActionSheet];

	__weak typeof(self) weakSelf = self;

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Root")
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

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"New folder…")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;

		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"New Folder")
																	  message:nil
															   preferredStyle:UIAlertControllerStyleAlert];

		[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
			textField.placeholder = RYGLocalized(@"Folder name");
			textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
		}];

		[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

		[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Create & Move")
												  style:UIAlertActionStyleDefault
												handler:^(UIAlertAction *x) {
			(void)x;

			NSString *name = RYGGalleryTrimmedName(alert.textFields.firstObject.text);
			if (!name.length) return;

			[self assignFolderPath:[self folderPathByAppendingComponent:name toBase:self.currentFolderPath] toFiles:files];
		}]];

		[self presentViewController:alert animated:YES completion:nil];
	}]];

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.sourceView = self.view;
		sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
		sheet.popoverPresentationController.permittedArrowDirections = 0;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Folder CRUD

- (void)presentCreateFolder {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"New Folder")
																  message:nil
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.placeholder = RYGLocalized(@"Folder name");
		textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
	}];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Create")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;

		NSString *name = RYGGalleryTrimmedName(alert.textFields.firstObject.text);
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
		[NSUserDefaults.standardUserDefaults setObject:folders forKey:kRYGGalleryFoldersKey];
	}

	[self reloadSubfolders];
	[self.collectionView reloadData];
	[self updateEmptyState];
}

- (NSString *)folderPathByAppendingComponent:(NSString *)component toBase:(NSString *)base {
	NSString *name = [RYGGalleryTrimmedName(component) stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
	if (!name.length) return nil;
	return base.length ? [base stringByAppendingFormat:@"/%@", name] : [@"/" stringByAppendingString:name];
}

- (void)mergePlaceholderSubfolders {
	NSArray<NSString *> *placeholders = [NSUserDefaults.standardUserDefaults arrayForKey:kRYGGalleryFoldersKey] ?: @[];
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

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Rename Folder")
																  message:nil
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.text = folderPath.lastPathComponent;
		textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
		textField.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Rename")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;

		NSString *name = RYGGalleryTrimmedName(alert.textFields.firstObject.text);
		if (name.length) [self performRenameOfFolder:folderPath toName:name];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

- (void)performRenameOfFolder:(NSString *)oldPath toName:(NSString *)newName {
	NSString *parent = oldPath.stringByDeletingLastPathComponent;
	if (!parent.length || ![parent hasPrefix:@"/"]) parent = [@"/" stringByAppendingString:parent ?: @""];

	NSString *cleanName = [RYGGalleryTrimmedName(newName) stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
	NSString *newPath = [parent isEqualToString:@"/"] ? [@"/" stringByAppendingString:cleanName] : [parent stringByAppendingFormat:@"/%@", cleanName];

	if (!cleanName.length || [oldPath isEqualToString:newPath]) return;

	NSManagedObjectContext *context = RYGGalleryCoreDataStack.shared.viewContext;
	NSFetchRequest *request = [self requestForFilesInFolder:oldPath];
	NSArray<RYGGalleryFile *> *files = [context executeFetchRequest:request error:nil] ?: @[];

	for (RYGGalleryFile *file in files) {
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

	NSManagedObjectContext *context = RYGGalleryCoreDataStack.shared.viewContext;
	NSInteger count = [context countForFetchRequest:[self requestForFilesInFolder:folderPath] error:nil];

	NSString *message = count
		? [NSString stringWithFormat:RYGLocalized(@"This folder contains %ld file(s). They will be moved to the parent folder."), (long)count]
		: RYGLocalized(@"This folder is empty.");

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@?", RYGLocalized(@"Delete Folder")]
																  message:message
														   preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete")
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

	NSManagedObjectContext *context = RYGGalleryCoreDataStack.shared.viewContext;
	NSArray<RYGGalleryFile *> *files = [context executeFetchRequest:[self requestForFilesInFolder:folderPath] error:nil] ?: @[];

	for (RYGGalleryFile *file in files) file.folderPath = parent;

	[context save:nil];
	[self rewritePlaceholderFoldersFrom:folderPath to:nil remove:YES];
	[self reloadSubfolders];
	[self.collectionView reloadData];
	[self updateEmptyState];
}

#pragma mark - Folder helpers

- (NSFetchRequest *)requestForFilesInFolder:(NSString *)folderPath {
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];
	request.predicate = [NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@", folderPath, [folderPath stringByAppendingString:@"/"]];
	return request;
}

- (NSMutableArray<NSString *> *)mutablePlaceholderFolders {
	return [[NSUserDefaults.standardUserDefaults arrayForKey:kRYGGalleryFoldersKey] mutableCopy] ?: NSMutableArray.array;
}

- (void)rewritePlaceholderFoldersFrom:(NSString *)oldPath to:(NSString *)newPath remove:(BOOL)remove {
	NSMutableArray<NSString *> *folders = NSMutableArray.array;

	for (NSString *path in [self mutablePlaceholderFolders]) {
		if (!RYGGalleryPathIsInside(path, oldPath)) {
			[folders addObject:path];
			continue;
		}

		if (!remove && newPath.length) {
			NSString *suffix = [path isEqualToString:oldPath] ? @"" : [path substringFromIndex:oldPath.length];
			[folders addObject:[newPath stringByAppendingString:suffix]];
		}
	}

	[NSUserDefaults.standardUserDefaults setObject:folders forKey:kRYGGalleryFoldersKey];
}

- (NSArray<NSString *> *)allFolderPaths {
	NSManagedObjectContext *context = RYGGalleryCoreDataStack.shared.viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];

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

	[set addObjectsFromArray:[NSUserDefaults.standardUserDefaults arrayForKey:kRYGGalleryFoldersKey] ?: @[]];

	return [set.allObjects sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

@end