#import <Foundation/Foundation.h>

%ctor {
    NSDictionary *defaults = @{
        @"igt_homecoming": @(NO),
        @"igt_quicksnap": @(NO),
        @"igt_directnotes_friendmap": @(NO),
        @"igt_directnotes_audio_reply": @(NO),
        @"igt_directnotes_avatar_reply": @(NO),
        @"igt_directnotes_gifs_reply": @(NO),
        @"igt_directnotes_photo_reply": @(NO),
        @"igt_prism": @(NO),
        @"igt_reels_first": @(NO),
        @"igt_friends_feed": @(NO),
        @"igt_tab_swiping": @(NO),
        @"igt_audio_ramping": @(NO),
        @"igt_feed_culling": @(NO),
        @"igt_feed_dedup": @(NO),
        @"igt_pull_to_carrera": @(NO),
        @"igt_screenshot_block": @(NO),
        @"igt_employee": @(NO),
        @"igt_internal": @(NO)
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}
