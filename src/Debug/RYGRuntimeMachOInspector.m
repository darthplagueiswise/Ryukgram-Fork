#import "RYGRuntimeMachOInspector.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

static NSString *const kRYGCRuntimeOverridesKey = @"ryg_runtime_c_overrides_v2";
static NSString *const kRYGCImageKey = @"image";
static NSString *const kRYGCUUIDKey = @"uuid";
static NSString *const kRYGCSymbolKey = @"symbol";
static NSString *const kRYGCABIKey = @"abi";
static NSString *const kRYGCValueKey = @"value";

@implementation RYGRuntimeMachOEntry @end

static NSString *RYGMachOCanonical(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static NSInteger RYGMachOImageIndex(NSString *path) {
    NSString *wanted = RYGMachOCanonical(path);
    for (uint32_t i=0;i<_dyld_image_count();i++) {
        const char *raw=_dyld_get_image_name(i); if(!raw)continue;
        NSString *loaded=RYGMachOCanonical([NSString stringWithUTF8String:raw]);
        if([loaded isEqualToString:wanted]) return (NSInteger)i;
    }
    return NSNotFound;
}

NSString *RYGRuntimeMachOImageUUID(NSString *imagePath) {
    NSInteger index=RYGMachOImageIndex(imagePath); if(index==NSNotFound)return nil;
    const struct mach_header *generic=_dyld_get_image_header((uint32_t)index);
    if(!generic || generic->magic!=MH_MAGIC_64) return nil;
    const struct mach_header_64 *h=(const struct mach_header_64 *)generic;
    const uint8_t *cursor=(const uint8_t *)h+sizeof(*h);
    for(uint32_t i=0;i<h->ncmds;i++) {
        const struct load_command *lc=(const struct load_command *)cursor;
        if(lc->cmdsize<sizeof(*lc)) break;
        if(lc->cmd==LC_UUID && lc->cmdsize>=sizeof(struct uuid_command)) {
            NSUUID *uuid=[[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)lc)->uuid];
            return uuid.UUIDString.uppercaseString;
        }
        cursor+=lc->cmdsize;
    }
    return nil;
}

static void RYGAddMachOEntry(NSMutableArray *rows, NSMutableSet *seen, NSString *imagePath, NSString *uuid,
                             NSString *name, NSString *kind, uint64_t address, BOOL hookable, RYGMachOSymbol *symbol) {
    if(!name.length)return;
    NSString *key=[NSString stringWithFormat:@"%@|%@|%llx",kind?:@"",name,(unsigned long long)address];
    if([seen containsObject:key])return; [seen addObject:key];
    RYGRuntimeMachOEntry *row=[RYGRuntimeMachOEntry new];
    row.imagePath=imagePath?:@""; row.imageUUID=uuid?:@""; row.name=name; row.kind=kind?:@"symbol"; row.address=address;
    row.hookableImport=hookable; row.symbol=symbol; [rows addObject:row];
}

static uint64_t RYGReadULEB128(const uint8_t **cursor,const uint8_t *end) {
    uint64_t result=0; unsigned shift=0;
    while(*cursor<end && shift<64) { uint8_t byte=*(*cursor)++; result|=((uint64_t)(byte&0x7f))<<shift; if(!(byte&0x80))break; shift+=7; }
    return result;
}

NSArray<RYGRuntimeMachOEntry *> *RYGRuntimeMachOEntries(NSString *imagePath) {
    if(!imagePath.length)return @[];
    NSString *uuid=RYGRuntimeMachOImageUUID(imagePath)?:@"";
    NSMutableArray *rows=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];

    for(RYGMachOSymbol *symbol in [RYGRuntimeBrowserEngine machOSymbolsForImagePath:imagePath]?:@[]) {
        NSString *kind=symbol.kind.length?symbol.kind:@"symbol";
        RYGAddMachOEntry(rows,seen,imagePath,uuid,symbol.name,kind,symbol.address,symbol.isRebindableImport,symbol);
    }

    NSInteger imageIndex=RYGMachOImageIndex(imagePath); if(imageIndex==NSNotFound)return rows.copy;
    const struct mach_header *generic=_dyld_get_image_header((uint32_t)imageIndex);
    if(!generic || generic->magic!=MH_MAGIC_64)return rows.copy;
    const struct mach_header_64 *h=(const struct mach_header_64 *)generic;
    intptr_t slide=_dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    const uint8_t *cursor=(const uint8_t *)h+sizeof(*h);
    const uint8_t *commandsEnd=cursor+h->sizeofcmds;
    const struct symtab_command *symtab=NULL; const struct dysymtab_command *dysym=NULL;
    const struct segment_command_64 *linkedit=NULL; uint64_t textVM=0;
    const struct linkedit_data_command *functionStarts=NULL;

    for(uint32_t i=0;i<h->ncmds;i++) {
        if(cursor+sizeof(struct load_command)>commandsEnd)break;
        const struct load_command *lc=(const struct load_command *)cursor;
        if(lc->cmdsize<sizeof(*lc)||cursor+lc->cmdsize>commandsEnd)break;
        if(lc->cmd==LC_SYMTAB)symtab=(const struct symtab_command *)cursor;
        else if(lc->cmd==LC_DYSYMTAB)dysym=(const struct dysymtab_command *)cursor;
        else if(lc->cmd==LC_FUNCTION_STARTS)functionStarts=(const struct linkedit_data_command *)cursor;
        else if(lc->cmd==LC_SEGMENT_64) {
            const struct segment_command_64 *seg=(const struct segment_command_64 *)cursor;
            if(!strncmp(seg->segname,SEG_LINKEDIT,sizeof(seg->segname)))linkedit=seg;
            if(!strncmp(seg->segname,SEG_TEXT,sizeof(seg->segname)))textVM=seg->vmaddr;
        }
        cursor+=lc->cmdsize;
    }
    if(!linkedit)return rows.copy;
    uintptr_t linkeditBase=(uintptr_t)slide+(uintptr_t)linkedit->vmaddr-(uintptr_t)linkedit->fileoff;

    if(symtab&&dysym&&dysym->nindirectsyms&&dysym->nindirectsyms<4000000) {
        const struct nlist_64 *symbols=(const struct nlist_64 *)(linkeditBase+symtab->symoff);
        const char *strings=(const char *)(linkeditBase+symtab->stroff);
        const uint32_t *indirect=(const uint32_t *)(linkeditBase+dysym->indirectsymoff);
        cursor=(const uint8_t *)h+sizeof(*h);
        for(uint32_t ci=0;ci<h->ncmds;ci++) {
            const struct load_command *lc=(const struct load_command *)cursor;
            if(lc->cmd==LC_SEGMENT_64) {
                const struct segment_command_64 *seg=(const struct segment_command_64 *)cursor;
                const struct section_64 *sects=(const struct section_64 *)(seg+1);
                for(uint32_t si=0;si<seg->nsects;si++) {
                    const struct section_64 *s=&sects[si]; uint32_t st=s->flags&SECTION_TYPE;
                    if(st!=S_SYMBOL_STUBS || !s->reserved2)continue;
                    uint64_t count=s->size/s->reserved2; uint64_t first=s->reserved1;
                    if(first+count>dysym->nindirectsyms)continue;
                    for(uint64_t j=0;j<count;j++) {
                        uint32_t symIndex=indirect[first+j];
                        if(symIndex&(INDIRECT_SYMBOL_LOCAL|INDIRECT_SYMBOL_ABS) || symIndex>=symtab->nsyms)continue;
                        struct nlist_64 n=symbols[symIndex];
                        if(!n.n_un.n_strx || n.n_un.n_strx>=symtab->strsize)continue;
                        const char *raw=strings+n.n_un.n_strx; if(!raw||!*raw)continue;
                        NSString *name=[NSString stringWithUTF8String:raw]?:@"stub";
                        uint64_t address=(uint64_t)((intptr_t)s->addr+slide+(intptr_t)(j*s->reserved2));
                        RYGAddMachOEntry(rows,seen,imagePath,uuid,name,@"stub",address,NO,nil);
                    }
                }
            }
            cursor+=lc->cmdsize;
        }
    }

    if(functionStarts&&functionStarts->datasize&&functionStarts->datasize<64*1024*1024&&textVM) {
        const uint8_t *p=(const uint8_t *)(linkeditBase+functionStarts->dataoff);
        const uint8_t *end=p+functionStarts->datasize; uint64_t offset=0; NSUInteger emitted=0;
        while(p<end && emitted<250000) {
            uint64_t delta=RYGReadULEB128(&p,end); if(!delta)break; offset+=delta;
            uint64_t address=(uint64_t)((intptr_t)textVM+slide+(intptr_t)offset);
            NSString *name=[NSString stringWithFormat:@"sub_%llx",(unsigned long long)address];
            RYGAddMachOEntry(rows,seen,imagePath,uuid,name,@"function",address,NO,nil); emitted++;
        }
    }

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeMachOEntry *a, RYGRuntimeMachOEntry *b) {
        if(a.isHookableImport!=b.isHookableImport)return a.isHookableImport?NSOrderedAscending:NSOrderedDescending;
        NSComparisonResult r=[a.kind localizedCaseInsensitiveCompare:b.kind]; if(r!=NSOrderedSame)return r;
        if(a.address!=b.address)return a.address<b.address?NSOrderedAscending:NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return rows.copy;
}

static NSString *RYGCOverrideID(RYGRuntimeMachOEntry *entry) {
    return entry.imageUUID.length&&entry.name.length?[NSString stringWithFormat:@"%@|%@",entry.imageUUID,entry.name]:@"";
}

static NSDictionary *RYGCStoredSpecs(void) { return [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGCRuntimeOverridesKey]?:@{}; }
static void RYGCWriteSpecs(NSDictionary *specs) {
    if(specs.count)[NSUserDefaults.standardUserDefaults setObject:specs forKey:kRYGCRuntimeOverridesKey];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:kRYGCRuntimeOverridesKey];
}

NSUInteger RYGRuntimeMachOPersistedOverrideCount(void) { return RYGCStoredSpecs().count; }

NSNumber *RYGRuntimeMachOPersistedOverrideForEntry(RYGRuntimeMachOEntry *entry, RYGCFunctionABI *abiOut) {
    if(abiOut)*abiOut=RYGCFunctionABIUnknown;
    NSDictionary *spec=RYGCStoredSpecs()[RYGCOverrideID(entry)];
    if(![spec isKindOfClass:NSDictionary.class])return nil;
    if(abiOut)*abiOut=(RYGCFunctionABI)[spec[kRYGCABIKey] integerValue];
    id value=spec[kRYGCValueKey]; return [value isKindOfClass:NSNumber.class]?value:nil;
}

BOOL RYGRuntimeMachOSetPersistedOverride(RYGRuntimeMachOEntry *entry, NSNumber *value, RYGCFunctionABI abi) {
    if(!entry.isHookableImport || !entry.symbol || !entry.imageUUID.length || !entry.name.length)return NO;
    NSString *identifier=RYGCOverrideID(entry); if(!identifier.length)return NO;
    NSMutableDictionary *all=RYGCStoredSpecs().mutableCopy?:[NSMutableDictionary dictionary];
    if(!value) {
        BOOL ok=[RYGRuntimeBrowserEngine setCOverride:nil forSymbol:entry.symbol abi:abi];
        if(ok){[all removeObjectForKey:identifier];RYGCWriteSpecs(all);} return ok;
    }
    if(abi<RYGCFunctionABIBool0||abi>RYGCFunctionABIBool4)return NO;
    NSDictionary *spec=@{kRYGCImageKey:entry.imagePath?:@"",kRYGCUUIDKey:entry.imageUUID,kRYGCSymbolKey:entry.name,kRYGCABIKey:@(abi),kRYGCValueKey:@(value.boolValue)};
    all[identifier]=spec; RYGCWriteSpecs(all); // persist first, WAT semantics
    return [RYGRuntimeBrowserEngine setCOverride:@(value.boolValue) forSymbol:entry.symbol abi:abi];
}

NSUInteger RYGRuntimeMachOApplyPersistedOverrides(void) {
    NSDictionary *all=RYGCStoredSpecs(); NSUInteger installed=0;
    for(NSDictionary *spec in all.allValues) {
        if(![spec isKindOfClass:NSDictionary.class])continue;
        NSString *path=spec[kRYGCImageKey], *uuid=spec[kRYGCUUIDKey], *name=spec[kRYGCSymbolKey];
        NSNumber *value=spec[kRYGCValueKey]; RYGCFunctionABI abi=(RYGCFunctionABI)[spec[kRYGCABIKey] integerValue];
        if(!path.length||!uuid.length||!name.length||![value isKindOfClass:NSNumber.class])continue;
        NSString *current=RYGRuntimeMachOImageUUID(path); if(!current.length||[current caseInsensitiveCompare:uuid]!=NSOrderedSame)continue;
        for(RYGMachOSymbol *symbol in [RYGRuntimeBrowserEngine machOSymbolsForImagePath:path]?:@[]) {
            if(!symbol.isRebindableImport||![symbol.name isEqualToString:name])continue;
            if([RYGRuntimeBrowserEngine setCOverride:value forSymbol:symbol abi:abi])installed++;
            break;
        }
    }
    return installed;
}
