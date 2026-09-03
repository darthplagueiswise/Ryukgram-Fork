#import "RYGStoriesArchivePaths.h"

@implementation RYGStoriesArchivePaths

+ (void)ensureDir:(NSString *)path {
	NSFileManager *fm = NSFileManager.defaultManager;
	if (![fm fileExistsAtPath:path])
		[fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

+ (NSString *)rootDirectory {
	static NSString *dir;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
		dir = [docs stringByAppendingPathComponent:@"StoriesArchive"];
		[self ensureDir:dir];
	});
	return dir;
}

+ (NSString *)sanitizePK:(NSString *)pk {
	if (!pk.length) return @"anon";
	NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
	return [pk rangeOfCharacterFromSet:bad].location == NSNotFound ? pk : @"anon";
}

+ (NSString *)accountDirectoryForPK:(NSString *)pk {
	NSString *dir = [[self rootDirectory] stringByAppendingPathComponent:[self sanitizePK:pk]];
	[self ensureDir:dir];
	return dir;
}

+ (NSString *)sqlitePathForPK:(NSString *)pk {
	return [[self accountDirectoryForPK:pk] stringByAppendingPathComponent:@"Stories.sqlite"];
}

+ (NSString *)mediaDirectoryForPK:(NSString *)pk {
	NSString *dir = [[self accountDirectoryForPK:pk] stringByAppendingPathComponent:@"Media"];
	[self ensureDir:dir];
	return dir;
}

+ (NSString *)mediaRelPathForMediaID:(NSString *)mediaID ext:(NSString *)ext {
	return [NSString stringWithFormat:@"Media/%@.%@", mediaID, ext.length ? ext : @"jpg"];
}

+ (NSString *)thumbRelPathForMediaID:(NSString *)mediaID {
	return [NSString stringWithFormat:@"Media/%@.thumb", mediaID];
}

@end
