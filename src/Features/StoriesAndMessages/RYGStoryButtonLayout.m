#import "RYGStoryButtonLayout.h"
#import "../../Utils.h"
#import "../../ActionButton/RYGActionIcon.h"

NSString *const RYGStoryBtnAction = @"action";
NSString *const RYGStoryBtnAudio = @"audio";
NSString *const RYGStoryBtnEye = @"eye";
NSString *const RYGStoryBtnMentions = @"mentions";

@implementation RYGStoryButtonLayout

+ (NSString *)prefKey { return @"story_button_positions"; }

+ (NSArray<NSString *> *)allIDs {
	return @[RYGStoryBtnAction, RYGStoryBtnEye, RYGStoryBtnMentions, RYGStoryBtnAudio];
}

+ (CGPoint)defaultPositionForID:(NSString *)buttonID {
	NSInteger last = [self slotColumns] - 1;
	if ([buttonID isEqualToString:RYGStoryBtnAction]) return [self slotAtColumn:last row:0];
	if ([buttonID isEqualToString:RYGStoryBtnEye]) return [self slotAtColumn:last - 1 row:0];
	if ([buttonID isEqualToString:RYGStoryBtnMentions]) return [self slotAtColumn:last - 2 row:0];
	if ([buttonID isEqualToString:RYGStoryBtnAudio]) return [self slotAtColumn:0 row:0];
	return [self slotAtColumn:last / 2 row:2];
}

+ (NSString *)iconForID:(NSString *)buttonID {
	if ([buttonID isEqualToString:RYGStoryBtnAction]) return [RYGActionIcon effectiveSymbolNameForSource:RYGActionSourceStories];
	if ([buttonID isEqualToString:RYGStoryBtnAudio]) return @"speaker.wave.2";
	if ([buttonID isEqualToString:RYGStoryBtnEye]) return @"eye";
	if ([buttonID isEqualToString:RYGStoryBtnMentions]) return @"at";
	return @"square";
}

+ (CGFloat)diameterForID:(NSString *)buttonID {
	return [buttonID isEqualToString:RYGStoryBtnAudio] ? 28.0 : 36.0;
}

+ (BOOL)idEnabled:(NSString *)buttonID {
	if ([buttonID isEqualToString:RYGStoryBtnAction]) return [RYGUtils getBoolPref:@"stories_action_button"];
	if ([buttonID isEqualToString:RYGStoryBtnAudio]) return [RYGUtils getBoolPref:@"story_audio_toggle"];
	if ([buttonID isEqualToString:RYGStoryBtnEye]) return [RYGUtils getBoolPref:@"no_seen_receipt"] && [RYGUtils getBoolPref:@"show_story_seen_button"];
	if ([buttonID isEqualToString:RYGStoryBtnMentions]) return [RYGUtils getBoolPref:@"story_mentions_button"];
	return NO;
}

@end
