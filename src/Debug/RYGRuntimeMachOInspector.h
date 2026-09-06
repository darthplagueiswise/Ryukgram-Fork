#pragma once
#import <Foundation/Foundation.h>
#import "RYGRuntimeBrowserEngine.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGRuntimeMachOEntry : NSObject
@property(nonatomic, copy) NSString *imagePath;
@property(nonatomic, copy) NSString *imageUUID;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *kind;
@property(nonatomic, assign) uint64_t address;
@property(nonatomic, assign, getter=isHookableImport) BOOL hookableImport;
@property(nonatomic, strong, nullable) RYGMachOSymbol *symbol;
@end

FOUNDATION_EXPORT NSString * _Nullable RYGRuntimeMachOImageUUID(NSString *imagePath);
FOUNDATION_EXPORT NSArray<RYGRuntimeMachOEntry *> *RYGRuntimeMachOEntries(NSString *imagePath);
FOUNDATION_EXPORT NSUInteger RYGRuntimeMachOPersistedOverrideCount(void);
FOUNDATION_EXPORT NSNumber * _Nullable RYGRuntimeMachOPersistedOverrideForEntry(RYGRuntimeMachOEntry *entry,
                                                                                RYGCFunctionABI * _Nullable abiOut);
FOUNDATION_EXPORT BOOL RYGRuntimeMachOSetPersistedOverride(RYGRuntimeMachOEntry *entry,
                                                           NSNumber * _Nullable value,
                                                           RYGCFunctionABI abi);
FOUNDATION_EXPORT NSUInteger RYGRuntimeMachOApplyPersistedOverrides(void);

NS_ASSUME_NONNULL_END
