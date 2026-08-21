#import "RYGRuntimeCIndex.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#include <string.h>

@implementation RYGCImportSymbol @end

static dispatch_queue_t RYGCIndexQueue(void){static dispatch_queue_t q;static dispatch_once_t once;dispatch_once(&once,^{q=dispatch_queue_create("com.ryukgram.c-import-index",DISPATCH_QUEUE_SERIAL);dispatch_set_target_queue(q,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));});return q;}
static NSMutableDictionary<NSString*,NSArray<RYGCImportSymbol*>*> *gRYGCIndexes;
static NSMutableDictionary<NSString*,NSValue*> *gRYGCHeaders;

static NSString *RYGCCanonical(NSString *path){if(!path.length)return @"";NSString*s=path.stringByStandardizingPath;NSString*r=s.stringByResolvingSymlinksInPath;return r.length?r.stringByStandardizingPath:s;}
static NSInteger RYGCImageIndex(NSString *path){NSString*w=RYGCCanonical(path);for(uint32_t i=0;i<_dyld_image_count();i++){const char*raw=_dyld_get_image_name(i);if(!raw)continue;NSString*p=RYGCCanonical([NSString stringWithUTF8String:raw]);if([p isEqualToString:w])return (NSInteger)i;}return NSNotFound;}
static NSString *RYGCABIForName(NSString *name){NSString*n=[name hasPrefix:@"_"]?[name substringFromIndex:1]:name;if([n isEqualToString:@"EasyGatingGetBoolean_Internal_DoNotUseOrMock"])return @"uint32(context,u32,u32,uintptr)";return nil;}
static BOOL RYGCManagedName(NSString *name){NSString*n=[name hasPrefix:@"_"]?[name substringFromIndex:1]:name;return [n isEqualToString:@"EasyGatingGetBoolean_Internal_DoNotUseOrMock"];}

static NSArray<RYGCImportSymbol*> *RYGCBuild(NSString *imagePath){
    NSInteger imageIndex=RYGCImageIndex(imagePath);if(imageIndex==NSNotFound)return @[];
    const struct mach_header *generic=_dyld_get_image_header((uint32_t)imageIndex);if(!generic||generic->magic!=MH_MAGIC_64)return @[];
    const struct mach_header_64 *header=(const struct mach_header_64*)generic;if(!header->sizeofcmds||header->sizeofcmds>64*1024*1024||header->ncmds>65535)return @[];
    const uint8_t*cursor=(const uint8_t*)(header+1),*end=cursor+header->sizeofcmds;const struct symtab_command*symtab=NULL;const struct dysymtab_command*dysym=NULL;const struct segment_command_64*linkedit=NULL;NSMutableArray<NSValue*>*sections=[NSMutableArray array];
    for(uint32_t i=0;i<header->ncmds;i++){if(cursor+sizeof(struct load_command)>end)return @[];const struct load_command*cmd=(const struct load_command*)cursor;if(cmd->cmdsize<sizeof(*cmd)||cursor+cmd->cmdsize>end)return @[];if(cmd->cmd==LC_SYMTAB)symtab=(const struct symtab_command*)cursor;else if(cmd->cmd==LC_DYSYMTAB)dysym=(const struct dysymtab_command*)cursor;else if(cmd->cmd==LC_SEGMENT_64){const struct segment_command_64*seg=(const struct segment_command_64*)cursor;if(!strncmp(seg->segname,SEG_LINKEDIT,sizeof(seg->segname)))linkedit=seg;if(seg->nsects&&cmd->cmdsize>=sizeof(*seg)+seg->nsects*sizeof(struct section_64)){const struct section_64*sec=(const struct section_64*)(seg+1);for(uint32_t s=0;s<seg->nsects;s++){uint32_t type=sec[s].flags&SECTION_TYPE;if(type==S_LAZY_SYMBOL_POINTERS||type==S_NON_LAZY_SYMBOL_POINTERS||type==S_LAZY_DYLIB_SYMBOL_POINTERS)[sections addObject:[NSValue valueWithBytes:&sec[s] objCType:@encode(struct section_64)]];}}}cursor+=cmd->cmdsize;}
    if(!symtab||!dysym||!linkedit||!dysym->nindirectsyms||symtab->nsyms>2000000)return @[];
    intptr_t slide=_dyld_get_image_vmaddr_slide((uint32_t)imageIndex);uintptr_t linkeditBase=(uintptr_t)slide+(uintptr_t)linkedit->vmaddr-(uintptr_t)linkedit->fileoff;const struct nlist_64*symbols=(const struct nlist_64*)(linkeditBase+symtab->symoff);const char*strings=(const char*)(linkeditBase+symtab->stroff);const uint32_t*indirect=(const uint32_t*)(linkeditBase+dysym->indirectsymoff);
    NSMutableDictionary<NSString*,RYGCImportSymbol*>*unique=[NSMutableDictionary dictionary];
    for(NSValue*v in sections){struct section_64 sec={0};[v getValue:&sec];NSUInteger count=(NSUInteger)(sec.size/sizeof(uintptr_t));uint32_t type=sec.flags&SECTION_TYPE;NSString*kind=type==S_LAZY_SYMBOL_POINTERS?@"lazy import":(type==S_NON_LAZY_SYMBOL_POINTERS?@"non-lazy import":@"lazy-dylib import");for(NSUInteger i=0;i<count;i++){uint64_t indirectIndex=(uint64_t)sec.reserved1+i;if(indirectIndex>=dysym->nindirectsyms)break;uint32_t symIndex=indirect[indirectIndex];if(symIndex&(INDIRECT_SYMBOL_LOCAL|INDIRECT_SYMBOL_ABS)||symIndex>=symtab->nsyms)continue;struct nlist_64 entry=symbols[symIndex];if(!entry.n_un.n_strx||entry.n_un.n_strx>=symtab->strsize)continue;const char*raw=strings+entry.n_un.n_strx;size_t remain=symtab->strsize-entry.n_un.n_strx;if(!raw||!*raw||!memchr(raw,0,remain))continue;NSString*name=[NSString stringWithUTF8String:raw];if(!name.length)continue;uintptr_t slot=(uintptr_t)((intptr_t)sec.addr+slide)+(i*sizeof(uintptr_t));uintptr_t target=0;memcpy(&target,(const void*)slot,sizeof(target));NSString*key=[NSString stringWithFormat:@"%@:%llx",name,(unsigned long long)slot];RYGCImportSymbol*row=[RYGCImportSymbol new];row.imagePath=RYGCCanonical(imagePath);row.name=name;row.pointerSection=kind;row.pointerSlot=slot;row.currentTarget=target;row.rebindable=YES;row.knownABI=RYGCABIForName(name);row.managed=RYGCManagedName(name);unique[key]=row;}}
    NSArray*rows=unique.allValues;return[rows sortedArrayUsingComparator:^NSComparisonResult(RYGCImportSymbol*a,RYGCImportSymbol*b){NSComparisonResult n=[a.name localizedCaseInsensitiveCompare:b.name];if(n!=NSOrderedSame)return n;return a.pointerSlot==b.pointerSlot?NSOrderedSame:(a.pointerSlot<b.pointerSlot?NSOrderedAscending:NSOrderedDescending);}];
}

@implementation RYGRuntimeCIndex
+ (void)requestImportsForImagePath:(NSString*)imagePath completion:(RYGCIndexCompletion)completion{NSString*requested=imagePath.copy?:@"";dispatch_async(RYGCIndexQueue(),^{if(!gRYGCIndexes)gRYGCIndexes=[NSMutableDictionary dictionary];if(!gRYGCHeaders)gRYGCHeaders=[NSMutableDictionary dictionary];NSString*key=RYGCCanonical(requested);NSInteger idx=RYGCImageIndex(key);const struct mach_header*h=idx==NSNotFound?NULL:_dyld_get_image_header((uint32_t)idx);NSValue*hv=h?[NSValue valueWithPointer:h]:nil;NSArray*rows=gRYGCIndexes[key];if(!rows||![gRYGCHeaders[key] isEqual:hv]){rows=RYGCBuild(requested);if(key.length&&hv){gRYGCIndexes[key]=rows?:@[];gRYGCHeaders[key]=hv;}}dispatch_async(dispatch_get_main_queue(),^{if(completion)completion(rows?:@[]);});});}
+ (NSArray<RYGCImportSymbol*>*)cachedImportsForImagePath:(NSString*)imagePath{__block NSArray*rows=nil;NSString*key=RYGCCanonical(imagePath);dispatch_sync(RYGCIndexQueue(),^{rows=gRYGCIndexes[key];});return rows;}
+ (void)invalidate{dispatch_async(RYGCIndexQueue(),^{[gRYGCIndexes removeAllObjects];[gRYGCHeaders removeAllObjects];});}
@end
