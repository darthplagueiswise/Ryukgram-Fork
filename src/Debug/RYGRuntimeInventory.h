#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGRuntimeInventory : NSObject
+ (NSDictionary *)manifest;
+ (NSDictionary *)inventoryNamed:(NSString *)name;
+ (NSArray<NSString *> *)availableInventoryNames;
+ (NSArray<NSDictionary *> *)candidatesForImagePath:(NSString *)imagePath;
+ (NSString *)diagnosticText;
@end

NS_ASSUME_NONNULL_END
