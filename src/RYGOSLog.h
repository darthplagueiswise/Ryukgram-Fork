#import <Foundation/Foundation.h>

// os_log under com.ryuk.ryukgram with %{public} formatting so dynamic strings stay
// readable in Console. Foundation-only, so it links into the appex dylibs too.

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void RYGOSLogWrite(const char *category, NSString *message);

#ifdef __cplusplus
}
#endif

#define RYGOSLog(cat, fmt, ...) RYGOSLogWrite((cat), [NSString stringWithFormat:(fmt), ##__VA_ARGS__])

NS_ASSUME_NONNULL_END
