#import <Foundation/Foundation.h>

__attribute__((constructor(65535)))
static void RYDNInstallDirectNotesMenuCleanup(void) {
    // Intentionally inert. Direct Notes rows are left untouched.
}
