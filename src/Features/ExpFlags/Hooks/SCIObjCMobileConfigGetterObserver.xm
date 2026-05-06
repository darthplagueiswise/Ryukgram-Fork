#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <pthread.h>
#import <dlfcn.h>
#import "../SCIExpFlags.h"
#import "../SCIDexKitNameResolver.h"
#import "../../../Utils.h"

static NSString *const kHooksKey=@"sci_exp_mc_objc_getter_observer_enabled";
static NSString *const kStartupKey=@"sci_exp_mc_objc_startup_hooks_enabled";
static NSString *const kStoreKey=@"sci_exp_overrides_by_name";
static NSString *const kApplyOverridesKey=@"sci_exp_mc_objc_apply_overrides_enabled";

static NSMutableDictionary<NSString*,NSValue*> *gOrig;
static NSDictionary<NSString*,NSNumber*> *gOverrides;
static NSMutableDictionary<NSString*,NSNumber*> *gHits;
static pthread_mutex_t gLock=PTHREAD_MUTEX_INITIALIZER;
static BOOL gInstalled=NO;
static __thread BOOL gInside=NO;

static NSString *K(Class c,SEL s){return [NSString stringWithFormat:@"%@:%@",NSStringFromClass(c),NSStringFromSelector(s)];}
static NSString *Cls(id x){Class c=[x class]; return c?NSStringFromClass(c):@"?";}
static NSString *Broker(id x){NSString *c=Cls(x); if([c containsString:@"Sessionless"])return @"igsl"; if([c hasPrefix:@"FBMobileConfig"])return @"fb"; return @"ig";}
static NSString *HexKey(uint64_t v){return [NSString stringWithFormat:@"mc:0x%016llx",(unsigned long long)v];}

static IMP Orig(id x,SEL s){
    Class c=[x class];
    pthread_mutex_lock(&gLock);
    while(c){NSValue *v=gOrig[K(c,s)]; if(v){IMP imp=(IMP)(uintptr_t)[v pointerValue]; pthread_mutex_unlock(&gLock); return imp;} c=class_getSuperclass(c);}
    pthread_mutex_unlock(&gLock);
    return NULL;
}

static void RefreshOverrides(void){
    NSDictionary *d=[[NSUserDefaults standardUserDefaults] dictionaryForKey:kStoreKey];
    pthread_mutex_lock(&gLock); gOverrides=d?[d copy]:@{}; pthread_mutex_unlock(&gLock);
}

static SCIExpFlagOverride OvKey(NSString *k){
    if(!k.length)return SCIExpFlagOverrideOff;
    pthread_mutex_lock(&gLock); NSNumber *n=gOverrides[k]; pthread_mutex_unlock(&gLock);
    return n?(SCIExpFlagOverride)n.integerValue:SCIExpFlagOverrideOff;
}

static SCIExpFlagOverride OvSpec(uint64_t p,NSString *bid){
    SCIDexKitResolvedName *r=[SCIDexKitNameResolver resolveBrokerID:(bid?:@"ig") value:p];
    if(r.name.length){SCIExpFlagOverride o=OvKey(r.name); if(o!=SCIExpFlagOverrideOff)return o;}
    uint64_t n=[SCIDexKitNameResolver normalizedSpecifierValue:p];
    SCIExpFlagOverride o=OvKey([NSString stringWithFormat:@"mcbr:%@:%016llx",bid?:@"ig",(unsigned long long)p]);
    if(o!=SCIExpFlagOverrideOff)return o;
    o=OvKey([NSString stringWithFormat:@"mcbr:%@:%016llx",bid?:@"ig",(unsigned long long)n]);
    if(o!=SCIExpFlagOverrideOff)return o;
    o=OvKey(HexKey(p)); if(o!=SCIExpFlagOverrideOff)return o;
    return OvKey(HexKey(n));
}

static BOOL SCIApplyOverridesEnabled(void){
    id enabled=[[NSUserDefaults standardUserDefaults] objectForKey:kApplyOverridesKey];
    return enabled&&[enabled boolValue];
}

static BOOL ApplyResolvedOverride(SCIExpFlagOverride o,BOOL v){
    if(o==SCIExpFlagOverrideTrue)return YES;
    if(o==SCIExpFlagOverrideFalse)return NO;
    return v;
}

static NSString *OText(SCIExpFlagOverride o){
    if(o==SCIExpFlagOverrideTrue)return @"ForceON";
    if(o==SCIExpFlagOverrideFalse)return @"ForceOFF";
    return @"Off";
}

static BOOL ShouldRecord(uint64_t p,SEL s){
    NSString *k=[NSString stringWithFormat:@"%@:%016llx",NSStringFromSelector(s),(unsigned long long)p];
    pthread_mutex_lock(&gLock);
    if(!gHits)gHits=[NSMutableDictionary dictionary];
    NSUInteger c=gHits[k].unsignedIntegerValue+1;
    gHits[k]=@(c);
    pthread_mutex_unlock(&gLock);
    return c<=2||(c%2048)==0;
}

static void SCIResolveCaller(void *addr, NSString **imageOut, NSString **symbolOut){
    if(imageOut)*imageOut=nil; if(symbolOut)*symbolOut=nil;
    if(!addr)return;
    Dl_info info={0};
    if(!dladdr(addr,&info))return;
    if(imageOut && info.dli_fname)*imageOut=[@(info.dli_fname) lastPathComponent];
    if(symbolOut && info.dli_sname)*symbolOut=@(info.dli_sname);
}

static void Rec(id x,SEL s,uint64_t p,BOOL def,BOOL orig,BOOL fin,SCIExpFlagOverride ov,NSString *src,void *caller){
    NSString *cls=Cls(x), *sel=NSStringFromSelector(s), *bid=Broker(x);
    NSString *callerImage=nil, *callerSymbol=nil;
    SCIResolveCaller(caller,&callerImage,&callerSymbol);
    [SCIDexKitNameResolver noteMobileConfigBoolReadWithClassName:cls selector:sel specifier:p defaultValue:def originalValue:orig finalValue:fin source:(src.length?src:@"objc-getBool") callerImage:callerImage callerSymbol:callerSymbol callerAddress:(uint64_t)(uintptr_t)caller];
    if(!ShouldRecord(p,s))return;
    SCIDexKitResolvedName *r=[SCIDexKitNameResolver resolveBrokerID:bid value:p];
    NSString *title=(r.name.length?r.name:(r.title?:@""));
    NSString *resolvedDetail=r.detail?:@"";
    NSString *detail=[NSString stringWithFormat:@"source=%@ · context=%@ · selector=%@ · broker=%@ · caller=%@/%@ · title=%@ · detail=%@ · default=%d · original=%d · final=%d · override=%@",
                      src.length?src:@"objc-getBool",cls,sel,bid,callerImage?:@"",callerSymbol?:@"",title,resolvedDetail,def?1:0,orig?1:0,fin?1:0,OText(ov)];
    [SCIExpFlags recordMCParamID:p type:SCIExpMCTypeBool defaultValue:detail originalValue:orig?@"YES":@"NO" contextClass:cls selectorName:sel];
}

static BOOL H1(id x,SEL s,uint64_t p){
    void *caller=__builtin_return_address(0);
    BOOL(*orig)(id,SEL,uint64_t)=(BOOL(*)(id,SEL,uint64_t))Orig(x,s);
    if(gInside)return orig?orig(x,s,p):NO;
    gInside=YES; BOOL ov=orig?orig(x,s,p):NO; BOOL apply=SCIApplyOverridesEnabled(); SCIExpFlagOverride o=apply?OvSpec(p,Broker(x)):SCIExpFlagOverrideOff; BOOL fv=apply?ApplyResolvedOverride(o,ov):ov; Rec(x,s,p,ov,ov,fv,o,@"objc-getBool",caller); gInside=NO; return fv;
}

static BOOL H2(id x,SEL s,uint64_t p,BOOL def){
    void *caller=__builtin_return_address(0);
    BOOL(*orig)(id,SEL,uint64_t,BOOL)=(BOOL(*)(id,SEL,uint64_t,BOOL))Orig(x,s);
    if(gInside)return orig?orig(x,s,p,def):def;
    gInside=YES; BOOL ov=orig?orig(x,s,p,def):def; BOOL apply=SCIApplyOverridesEnabled(); SCIExpFlagOverride o=apply?OvSpec(p,Broker(x)):SCIExpFlagOverrideOff; BOOL fv=apply?ApplyResolvedOverride(o,ov):ov; Rec(x,s,p,def,ov,fv,o,@"objc-getBool",caller); gInside=NO; return fv;
}

static BOOL H3(id x,SEL s,uint64_t p,void *opt){
    void *caller=__builtin_return_address(0);
    BOOL(*orig)(id,SEL,uint64_t,void*)=(BOOL(*)(id,SEL,uint64_t,void*))Orig(x,s);
    if(gInside)return orig?orig(x,s,p,opt):NO;
    gInside=YES; BOOL ov=orig?orig(x,s,p,opt):NO; BOOL apply=SCIApplyOverridesEnabled(); SCIExpFlagOverride o=apply?OvSpec(p,Broker(x)):SCIExpFlagOverrideOff; BOOL fv=apply?ApplyResolvedOverride(o,ov):ov; Rec(x,s,p,ov,ov,fv,o,@"objc-getBool",caller); gInside=NO; return fv;
}

static BOOL H4(id x,SEL s,uint64_t p,void *opt,BOOL def){
    void *caller=__builtin_return_address(0);
    BOOL(*orig)(id,SEL,uint64_t,void*,BOOL)=(BOOL(*)(id,SEL,uint64_t,void*,BOOL))Orig(x,s);
    if(gInside)return orig?orig(x,s,p,opt,def):def;
    gInside=YES; BOOL ov=orig?orig(x,s,p,opt,def):def; BOOL apply=SCIApplyOverridesEnabled(); SCIExpFlagOverride o=apply?OvSpec(p,Broker(x)):SCIExpFlagOverrideOff; BOOL fv=apply?ApplyResolvedOverride(o,ov):ov; Rec(x,s,p,def,ov,fv,o,@"objc-getBool",caller); gInside=NO; return fv;
}

static NSString *Str(id x){if(!x)return nil; NSString *s=[x isKindOfClass:NSString.class]?(NSString*)x:[x description]; return s.length?s:nil;}
static BOOL HName(id x,SEL s,id name,BOOL def){
    void *caller=__builtin_return_address(0);
    BOOL(*orig)(id,SEL,id,BOOL)=(BOOL(*)(id,SEL,id,BOOL))Orig(x,s);
    if(gInside)return orig?orig(x,s,name,def):def;
    gInside=YES;
    BOOL ov=orig?orig(x,s,name,def):def; NSString *n=Str(name); BOOL apply=SCIApplyOverridesEnabled(); SCIExpFlagOverride o=(apply&&n.length)?OvKey(n):SCIExpFlagOverrideOff; BOOL fv=apply?ApplyResolvedOverride(o,ov):ov;
    if(n.length){uint64_t pseudo=(uint64_t)n.hash; Rec(x,s,pseudo,def,ov,fv,o,@"objc-startup-name-bool",caller);}
    gInside=NO; return fv;
}

static BOOL SizeOK(Class c,SEL s,NSUInteger argc,NSUInteger retsz,NSUInteger arg2sz){
    if(!c||!s)return NO; Method m=class_getInstanceMethod(c,s); if(!m)return NO; if(method_getNumberOfArguments(m)!=argc)return NO;
    char ret[128]={0},arg[128]={0}; method_getReturnType(m,ret,sizeof(ret)); method_getArgumentType(m,2,arg,sizeof(arg));
    NSUInteger rs=0,as=0; NSGetSizeAndAlignment(ret,&rs,NULL); NSGetSizeAndAlignment(arg,&as,NULL);
    return rs==retsz&&as==arg2sz;
}
static BOOL BoolU64(Class c,SEL s,NSUInteger argc){return SizeOK(c,s,argc,sizeof(BOOL),sizeof(uint64_t));}
static BOOL U64ToU64(Class c,SEL s){return SizeOK(c,s,3,sizeof(uint64_t),sizeof(uint64_t));}

static uint64_t HAlias(id x,SEL s,uint64_t raw){
    uint64_t(*orig)(id,SEL,uint64_t)=(uint64_t(*)(id,SEL,uint64_t))Orig(x,s);
    if(gInside)return orig?orig(x,s,raw):raw;
    gInside=YES; uint64_t tr=orig?orig(x,s,raw):raw; gInside=NO;
    if(raw&&tr&&raw!=tr){NSString *src=[NSString stringWithFormat:@"%@ %@",Cls(x),NSStringFromSelector(s)]; [SCIDexKitNameResolver noteAliasFromSpecifier:raw toSpecifier:tr source:src];}
    return tr;
}

static void InstallOne(Class c,NSString *selName,IMP repl){
    if(!c||!selName.length||!repl)return; SEL s=NSSelectorFromString(selName); if(!class_getInstanceMethod(c,s))return;
    NSString *k=K(c,s); pthread_mutex_lock(&gLock); BOOL done=gOrig[k]!=nil; pthread_mutex_unlock(&gLock); if(done)return;
    IMP old=NULL; MSHookMessageEx(c,s,repl,&old); if(!old)return;
    pthread_mutex_lock(&gLock); if(!gOrig)gOrig=[NSMutableDictionary dictionary]; gOrig[k]=[NSValue valueWithPointer:(const void*)(uintptr_t)old]; pthread_mutex_unlock(&gLock);
}
static void InstallBool(Class c,NSString *selName,NSUInteger argc,IMP repl){SEL s=NSSelectorFromString(selName); if(BoolU64(c,s,argc))InstallOne(c,selName,repl);}
static void InstallAlias(Class c,NSString *selName){SEL s=NSSelectorFromString(selName); if(U64ToU64(c,s))InstallOne(c,selName,(IMP)HAlias);}

static void InstallCommon(NSString *cn){
    Class c=NSClassFromString(cn); if(!c)return;
    InstallBool(c,@"getBool:",3,(IMP)H1);
    InstallBool(c,@"getBool:withDefault:",4,(IMP)H2);
    InstallBool(c,@"getBool:withOptions:",4,(IMP)H3);
    InstallBool(c,@"getBool:withOptions:withDefault:",5,(IMP)H4);
    InstallBool(c,@"getBoolWithoutLogging:",3,(IMP)H1);
    InstallBool(c,@"getBoolWithoutLogging:withDefault:",4,(IMP)H2);
    InstallAlias(c,@"_getTranslatedSpecifier:");
    InstallAlias(c,@"getStableIdFromParamSpecifier:");
}

static void InstallAll(void){
    if(gInstalled)return; gInstalled=YES; RefreshOverrides();
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *n){RefreshOverrides();}];
    for(NSString *cn in @[@"IGMobileConfigContextManager",@"IGMobileConfigSessionlessContextManager",@"IGMobileConfigUserSessionContextManager",@"FBMobileConfigContextManager",@"FBMobileConfigSessionlessContextManager",@"FBMobileConfigUserSessionContextManager",@"FBMobileConfigContextObjcImpl"])InstallCommon(cn);
    if([SCIUtils getBoolPref:kStartupKey]){
        Class s=NSClassFromString(@"FBMobileConfigStartupConfigs");
        InstallBool(s,@"getBool:withDefault:",4,(IMP)H2); InstallBool(s,@"getBool:withOptions:withDefault:",5,(IMP)H4); InstallOne(s,@"getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:",(IMP)HName);
        Class d=NSClassFromString(@"FBMobileConfigStartupConfigsDeprecated"); InstallOne(d,@"getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:",(IMP)HName);
    }
    NSLog(@"[RyukGram][MCObjCObserver] installed early pass-through ObjC MobileConfig observer feeding SCIDexKitNameResolver + runtime callsites");
}

static BOOL ShouldInstallObserver(void){
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    NSArray *keys=@[kHooksKey,@"sci_exp_mc_c_hooks_enabled",@"sci_exp_mc_hooks_enabled",@"sci_exp_mc_broker_enabled",@"sci_exp_mc_broker_observer_enabled"];
    for(NSString *k in keys){id v=[ud objectForKey:k]; if(v&&[v boolValue])return YES;}
    return NO;
}

%ctor{
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kHooksKey:@NO,kStartupKey:@NO,kApplyOverridesKey:@NO,@"sci_exp_mc_c_hooks_enabled":@NO,@"sci_exp_mc_hooks_enabled":@NO}];
    if(ShouldInstallObserver()){
        dispatch_async(dispatch_get_main_queue(),^{InstallAll();});
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *n){if(ShouldInstallObserver())InstallAll();}];
}
