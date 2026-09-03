#import "RYGOSLog.h"
#import <os/log.h>

void RYGOSLogWrite(const char *category, NSString *message) {
    static os_log_t lg;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lg = os_log_create("com.ryuk.ryukgram", "ryg"); });
    os_log(lg, "[%{public}s] %{public}s", category ?: "ryg", message.UTF8String ?: "");
}
