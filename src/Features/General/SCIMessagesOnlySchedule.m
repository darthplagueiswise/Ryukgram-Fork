#import "SCIMessagesOnlySchedule.h"
#import "../../Utils.h"
#import <UIKit/UIKit.h>

static NSString *const kEnabled = @"messages_only_schedule_enabled";
static NSString *const kStart   = @"messages_only_schedule_start";
static NSString *const kEnd     = @"messages_only_schedule_end";
static NSString *const kForced  = @"messages_only_schedule_forced"; // scheduler currently owns the ON state
static NSString *const kMaster  = @"messages_only";

@implementation SCIMessagesOnlySchedule {
    NSTimer *_timer;
    BOOL _started;
}

+ (instancetype)shared {
    static SCIMessagesOnlySchedule *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SCIMessagesOnlySchedule new]; });
    return s;
}

- (void)start {
    if (_started) return;
    _started = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [self evaluateWithPrompt:NO];
    [self armTimer];
}

- (void)appBecameActive {
    [self evaluateWithPrompt:YES];
    [self armTimer];
}

- (void)refreshFromPrefs {
    [self invalidate];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (![d boolForKey:kEnabled]) {
        // Release a scheduler-forced ON so disabling the schedule isn't a one-way trip.
        if ([d boolForKey:kForced]) {
            [d setBool:NO forKey:kForced];
            if ([d boolForKey:kMaster]) {
                [d setBool:NO forKey:kMaster];
                [self promptRestartLeaving:YES];
            }
        }
        return;
    }
    [self evaluateWithPrompt:YES];
    [self armTimer];
}

#pragma mark - Window math

- (NSInteger)minutesFromString:(NSString *)s fallback:(NSInteger)fb {
    NSArray<NSString *> *p = [s componentsSeparatedByString:@":"];
    if (p.count != 2) return fb;
    NSInteger h = p[0].integerValue, m = p[1].integerValue;
    if (h < 0 || h > 23 || m < 0 || m > 59) return fb;
    return h * 60 + m;
}

- (NSInteger)startMinutes { return [self minutesFromString:[NSUserDefaults.standardUserDefaults stringForKey:kStart] fallback:22 * 60]; }
- (NSInteger)endMinutes   { return [self minutesFromString:[NSUserDefaults.standardUserDefaults stringForKey:kEnd]   fallback:6  * 60]; }

- (BOOL)isWithinWindowNow {
    NSInteger sm = [self startMinutes], em = [self endMinutes];
    if (sm == em) return NO; // empty/ambiguous window — treat as never
    NSDateComponents *c = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[NSDate date]];
    NSInteger now = c.hour * 60 + c.minute;
    if (sm < em) return now >= sm && now < em;
    return now >= sm || now < em; // crosses midnight
}

#pragma mark - State machine

- (void)evaluateWithPrompt:(BOOL)prompt {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (![d boolForKey:kEnabled]) return;
    BOOL in = [self isWithinWindowNow];
    BOOL forced = [d boolForKey:kForced];
    BOOL master = [d boolForKey:kMaster];

    if (in && !forced && !master) {
        [d setBool:YES forKey:kMaster];
        [d setBool:YES forKey:kForced];
        if (prompt) [self promptRestartLeaving:NO];
    } else if (!in && forced) {
        [d setBool:NO forKey:kForced];
        if (master) {
            [d setBool:NO forKey:kMaster];
            if (prompt) [self promptRestartLeaving:YES];
        }
    }
}

#pragma mark - Timer

- (void)invalidate {
    [_timer invalidate];
    _timer = nil;
}

- (NSDate *)nextBoundaryAfter:(NSDate *)date {
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSInteger sm = [self startMinutes], em = [self endMinutes];
    NSDate *ns = [cal nextDateAfterDate:date matchingHour:sm / 60 minute:sm % 60 second:0 options:NSCalendarMatchNextTime];
    NSDate *ne = [cal nextDateAfterDate:date matchingHour:em / 60 minute:em % 60 second:0 options:NSCalendarMatchNextTime];
    if (!ns) return ne;
    if (!ne) return ns;
    return [ns earlierDate:ne];
}

- (void)armTimer {
    [self invalidate];
    if (![NSUserDefaults.standardUserDefaults boolForKey:kEnabled]) return;
    NSDate *next = [self nextBoundaryAfter:[NSDate date]];
    if (!next) return;
    _timer = [[NSTimer alloc] initWithFireDate:next interval:0 target:self selector:@selector(timerFired) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)timerFired {
    [self evaluateWithPrompt:YES];
    [self armTimer];
}

#pragma mark - Prompt

- (void)promptRestartLeaving:(BOOL)leaving {
    NSString *title = leaving ? SCILocalized(@"Messages-only ending") : SCILocalized(@"Messages-only starting");
    NSString *msg = leaving
        ? SCILocalized(@"Your Messages-only window has ended. Restart Instagram to bring back the other tabs.")
        : SCILocalized(@"Your Messages-only window has started. Restart Instagram to switch to DM-only.");
    [SCIUtils showRestartConfirmationWithTitle:title message:msg];
}

@end
