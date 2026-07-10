#import "SCIDMButtonLayout.h"
#import "../../Utils.h"
#import "../../ActionButton/SCIActionIcon.h"

NSString *const SCIDMBtnAction = @"action";
NSString *const SCIDMBtnEye = @"eye";
NSString *const SCIDMBtnAudio = @"audio";

@implementation SCIDMButtonLayout

+ (NSString *)prefKey { return @"dm_button_positions"; }

+ (NSArray<NSString *> *)allIDs {
	return @[SCIDMBtnAction, SCIDMBtnEye, SCIDMBtnAudio];
}

+ (CGPoint)defaultPositionForID:(NSString *)buttonID {
	if ([buttonID isEqualToString:SCIDMBtnAction]) return [self slotAtColumn:9 row:0];
	if ([buttonID isEqualToString:SCIDMBtnEye]) return [self slotAtColumn:8 row:0];
	if ([buttonID isEqualToString:SCIDMBtnAudio]) return [self slotAtColumn:0 row:0];
	return [self slotAtColumn:4 row:2];
}

+ (NSString *)iconForID:(NSString *)buttonID {
	if ([buttonID isEqualToString:SCIDMBtnAction]) return [SCIActionIcon effectiveSymbolNameForSource:SCIActionSourceDM];
	if ([buttonID isEqualToString:SCIDMBtnEye]) return @"eye";
	if ([buttonID isEqualToString:SCIDMBtnAudio]) return @"speaker.wave.2";
	return @"square";
}

+ (CGFloat)diameterForID:(NSString *)buttonID {
	return [buttonID isEqualToString:SCIDMBtnAudio] ? 28.0 : 36.0;
}

+ (BOOL)idEnabled:(NSString *)buttonID {
	if ([buttonID isEqualToString:SCIDMBtnAction]) return [SCIUtils getBoolPref:@"dm_visual_action_button"];
	if ([buttonID isEqualToString:SCIDMBtnEye]) return [SCIUtils getBoolPref:@"dm_visual_seen_button"];
	if ([buttonID isEqualToString:SCIDMBtnAudio]) return [SCIUtils getBoolPref:@"dm_visual_audio_toggle"];
	return NO;
}

@end
