#import <Foundation/Foundation.h>

NSDictionary *RYGDefaultsDictionary(void);
void RYGRegisterDefaultsOnce(void);
void RYGMigrateLegacyDefaults(void);
void RYGMigrateActivityModes(void);
void RYGDropMistypedStoredDefaults(void);
