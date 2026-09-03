#import "RYGMessagesOnlySchedule.h"
#import "../../Utils.h"
#import <UIKit/UIKit.h>

static NSString *const kEnabled = @"messages_only_schedule_enabled";
static NSString *const kStart   = @"messages_only_schedule_start";
static NSString *const kEnd     = @"messages_only_schedule_end";
static NSString *const kForced  = @"messages_only_schedule_forced";
static NSString *const kApply   = @"messages_only_schedule_apply";
static NSString *const kMaster  = @"messages_only";

@implementation RYGMessagesOnlySchedule {
    NSTimer *_timer;
    BOOL _started;
    BOOL _hasDeclined;
    BOOL _declinedForWindowIn;
    BOOL _askPending;
}

+ (instancetype)shared {
    static RYGMessagesOnlySchedule *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [RYGMessagesOnlySchedule new]; });
    return s;
}

- (void)start {
    if (_started) return;
    if (![NSUserDefaults.standardUserDefaults boolForKey:kEnabled]) return;
    [self beginObserving];
    [self evaluateAtRuntime:NO];
    [self armTimer];
}

- (void)beginObserving {
    if (_started) return;
    _started = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)appBecameActive {
    [self evaluateAtRuntime:YES];
    [self armTimer];
}

- (void)refreshFromPrefs {
    [self invalidate];
    _hasDeclined = NO;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (![d boolForKey:kEnabled]) {
        // Release a scheduler-forced ON so disabling the schedule is not one-way.
        if ([d boolForKey:kForced]) {
            [d setBool:NO forKey:kForced];
            if ([d boolForKey:kMaster]) [self applyState:NO prompt:YES];
        }
        return;
    }
    [self beginObserving];
    [self evaluateAtRuntime:YES];
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
    if (sm == em) return NO;
    NSDateComponents *c = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[NSDate date]];
    NSInteger now = c.hour * 60 + c.minute;
    if (sm < em) return now >= sm && now < em;
    return now >= sm || now < em;
}

#pragma mark - State machine

- (void)evaluateAtRuntime:(BOOL)runtime {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (![d boolForKey:kEnabled]) return;
    BOOL in = [self isWithinWindowNow];
    BOOL forced = [d boolForKey:kForced];
    BOOL master = [d boolForKey:kMaster];

    if (_hasDeclined && _declinedForWindowIn != in) _hasDeclined = NO;

    BOOL wantsOn = (in && !forced && !master);
    BOOL wantsOff = (!in && forced);
    if (!wantsOn && !wantsOff) return;

    BOOL desired = wantsOn;

    if (!runtime) {
        [self commitState:desired prompt:NO];
        return;
    }
    if (_hasDeclined) return;

    if ([[RYGUtils getStringPref:kApply] isEqualToString:@"ask"]) {
        [self askForState:desired in:in];
        return;
    }
    [self commitState:desired prompt:YES];
}

- (void)commitState:(BOOL)on prompt:(BOOL)prompt {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kForced];
    [self applyState:on prompt:prompt];
}

- (void)applyState:(BOOL)on prompt:(BOOL)prompt {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kMaster];
    BOOL live = RYGMessagesOnlyApplyLive();
    if (live) {
        RYGNotifyInfo(RYG_NOTIF_GENERIC, RYGLocalized(@"Messages only"),
                      on ? RYGLocalized(@"On") : RYGLocalized(@"Off"));
        return;
    }
    if (prompt) [self promptRestartLeaving:!on];
}

- (void)askForState:(BOOL)on in:(BOOL)in {
    if (_askPending) return;
    _askPending = YES;

    NSString *title = on ? RYGLocalized(@"Messages-only starting") : RYGLocalized(@"Messages-only ending");
    NSString *msg = on ? RYGLocalized(@"Your Messages-only window has started. Switch to DM-only now?")
                       : RYGLocalized(@"Your Messages-only window has ended. Bring back the other tabs now?");

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Apply") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        self->_askPending = NO;
        [self commitState:on prompt:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Later") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) {
        self->_askPending = NO;
        self->_hasDeclined = YES;
        self->_declinedForWindowIn = in;
    }]];

    [RYGUtils presentAlertInOwnWindow:alert];
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
    [self evaluateAtRuntime:YES];
    [self armTimer];
}

#pragma mark - Prompt

- (void)promptRestartLeaving:(BOOL)leaving {
    NSString *title = leaving ? RYGLocalized(@"Messages-only ending") : RYGLocalized(@"Messages-only starting");
    NSString *msg = leaving
        ? RYGLocalized(@"Your Messages-only window has ended. Restart Instagram to bring back the other tabs.")
        : RYGLocalized(@"Your Messages-only window has started. Restart Instagram to switch to DM-only.");
    [RYGUtils showRestartConfirmationWithTitle:title message:msg];
}

@end
