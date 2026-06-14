#import <Foundation/Foundation.h>

// Template → ICU pattern. {DD}-style tokens map to date fields; everything
// else (incl. unknown {…}) is emitted as a quoted literal.
NSString *SCIDateFormatPatternFromTemplate(NSString *tpl);

// Ordered token list for the editor UI: @[userToken, icuField].
NSArray<NSArray<NSString *> *> *SCIDateFormatTemplateTokens(void);

// Saved custom templates — JSON array of {"id","tpl"} in the
// feed_date_custom_templates pref; a format key of "custom:<id>" selects one.
NSArray<NSDictionary<NSString *, NSString *> *> *SCIDateFormatCustomList(void);
void SCIDateFormatCustomSaveList(NSArray<NSDictionary<NSString *, NSString *> *> *list);
NSString *SCIDateFormatCustomTemplateForKey(NSString *fmtKey);
