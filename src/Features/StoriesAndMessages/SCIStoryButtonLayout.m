#import "SCIStoryButtonLayout.h"
#import "../../Utils.h"
#import "../../ActionButton/SCIActionIcon.h"

NSString *const SCIStoryBtnAction = @"action";
NSString *const SCIStoryBtnAudio = @"audio";
NSString *const SCIStoryBtnEye = @"eye";
NSString *const SCIStoryBtnMentions = @"mentions";

@implementation SCIStoryButtonLayout

+ (NSString *)prefKey { return @"story_button_positions"; }

+ (NSArray<NSString *> *)allIDs {
	return @[SCIStoryBtnAction, SCIStoryBtnEye, SCIStoryBtnMentions, SCIStoryBtnAudio];
}

+ (CGPoint)defaultPositionForID:(NSString *)buttonID {
	if ([buttonID isEqualToString:SCIStoryBtnAction]) return [self slotAtColumn:9 row:0];
	if ([buttonID isEqualToString:SCIStoryBtnEye]) return [self slotAtColumn:8 row:0];
	if ([buttonID isEqualToString:SCIStoryBtnMentions]) return [self slotAtColumn:7 row:0];
	if ([buttonID isEqualToString:SCIStoryBtnAudio]) return [self slotAtColumn:0 row:0];
	return [self slotAtColumn:4 row:2];
}

+ (NSString *)iconForID:(NSString *)buttonID {
	if ([buttonID isEqualToString:SCIStoryBtnAction]) return [SCIActionIcon effectiveSymbolNameForSource:SCIActionSourceStories];
	if ([buttonID isEqualToString:SCIStoryBtnAudio]) return @"speaker.wave.2";
	if ([buttonID isEqualToString:SCIStoryBtnEye]) return @"eye";
	if ([buttonID isEqualToString:SCIStoryBtnMentions]) return @"at";
	return @"square";
}

+ (CGFloat)diameterForID:(NSString *)buttonID {
	return [buttonID isEqualToString:SCIStoryBtnAudio] ? 28.0 : 36.0;
}

+ (BOOL)idEnabled:(NSString *)buttonID {
	if ([buttonID isEqualToString:SCIStoryBtnAction]) return [SCIUtils getBoolPref:@"stories_action_button"];
	if ([buttonID isEqualToString:SCIStoryBtnAudio]) return [SCIUtils getBoolPref:@"story_audio_toggle"];
	if ([buttonID isEqualToString:SCIStoryBtnEye]) return [SCIUtils getBoolPref:@"no_seen_receipt"] && [SCIUtils getBoolPref:@"show_story_seen_button"];
	if ([buttonID isEqualToString:SCIStoryBtnMentions]) return [SCIUtils getBoolPref:@"story_mentions_button"];
	return NO;
}

@end
