#import <Foundation/Foundation.h>
#import "SCIExpFlags.h"

/*
 This file intentionally no longer implements SCIExpFlags methods through a
 category.

 recordMCParamID:type:defaultValue:originalValue:contextClass:selectorName:
 belongs in SCIExpFlags.m, inside the primary @implementation SCIExpFlags.

 Keeping the old category implementation here makes clang fail with:
 -Wobjc-protocol-method-implementation
 because the selector is declared on the primary class.
 */
