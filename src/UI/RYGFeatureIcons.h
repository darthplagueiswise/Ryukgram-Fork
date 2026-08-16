// One icon per feature. Point call sites here instead of repeating asset strings.
// In-app rows use the outline set; Backup & Restore and Storage use the filled one.

#import <UIKit/UIKit.h>
#import "../Settings/RYGSymbol.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGFeatureIcons : NSObject

+ (RYGSymbol *)deletedMessages;
+ (RYGSymbol *)readReceipts;
+ (RYGSymbol *)callRecordings;
+ (RYGSymbol *)followRequests;
+ (RYGSymbol *)gallery;
+ (RYGSymbol *)chatBackgrounds;
+ (RYGSymbol *)profileAnalyzer;
+ (RYGSymbol *)storiesArchive;
+ (RYGSymbol *)instants;
+ (RYGSymbol *)downloads;
+ (RYGSymbol *)settings;
+ (RYGSymbol *)hiddenLockedChats;
+ (RYGSymbol *)revealHidden;
+ (RYGSymbol *)filters;
+ (RYGSymbol *)featureData;
+ (RYGSymbol *)storage;

+ (RYGSymbol *)deletedMessagesFilled;
+ (RYGSymbol *)readReceiptsFilled;
+ (RYGSymbol *)callRecordingsFilled;
+ (RYGSymbol *)chatBackgroundsFilled;
+ (RYGSymbol *)hiddenLockedChatsFilled;
+ (RYGSymbol *)instantsFilled;
+ (RYGSymbol *)downloadsFilled;

@end

NS_ASSUME_NONNULL_END
