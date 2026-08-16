#import "RYGDMButtonLayout.h"
#import "../../Utils.h"
#import "../../ActionButton/RYGActionIcon.h"

NSString *const RYGDMBtnAction = @"action";
NSString *const RYGDMBtnEye = @"eye";
NSString *const RYGDMBtnAudio = @"audio";

@implementation RYGDMButtonLayout

+ (NSString *)prefKey { return @"dm_button_positions"; }

+ (NSArray<NSString *> *)allIDs {
	return @[RYGDMBtnAction, RYGDMBtnEye, RYGDMBtnAudio];
}

+ (CGPoint)defaultPositionForID:(NSString *)buttonID {
	NSInteger last = [self slotColumns] - 1;
	if ([buttonID isEqualToString:RYGDMBtnAction]) return [self slotAtColumn:last row:0];
	if ([buttonID isEqualToString:RYGDMBtnEye]) return [self slotAtColumn:last - 1 row:0];
	if ([buttonID isEqualToString:RYGDMBtnAudio]) return [self slotAtColumn:0 row:0];
	return [self slotAtColumn:last / 2 row:2];
}

+ (NSString *)iconForID:(NSString *)buttonID {
	if ([buttonID isEqualToString:RYGDMBtnAction]) return [RYGActionIcon effectiveSymbolNameForSource:RYGActionSourceDM];
	if ([buttonID isEqualToString:RYGDMBtnEye]) return @"eye";
	if ([buttonID isEqualToString:RYGDMBtnAudio]) return @"speaker.wave.2";
	return @"square";
}

+ (CGFloat)diameterForID:(NSString *)buttonID {
	return [buttonID isEqualToString:RYGDMBtnAudio] ? 28.0 : 36.0;
}

+ (BOOL)idEnabled:(NSString *)buttonID {
	if ([buttonID isEqualToString:RYGDMBtnAction]) return [RYGUtils getBoolPref:@"dm_visual_action_button"];
	if ([buttonID isEqualToString:RYGDMBtnEye]) return [RYGUtils getBoolPref:@"dm_visual_seen_button"];
	if ([buttonID isEqualToString:RYGDMBtnAudio]) return [RYGUtils getBoolPref:@"dm_visual_audio_toggle"];
	return NO;
}

@end
