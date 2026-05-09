#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <pthread.h>
#import <dlfcn.h>
#import "../SCIDexKitNameResolver.h"
#import "../SCIMobileConfigBrokerStore.h"

static NSString *const kStartupKey=@"sci_exp_mc_objc_startup_hooks_enabled";
static NSString *const kApplyKey=@"sci_exp_mc_objc_apply_overrides_enabled";
static NSString *const kAliasKey=@"sci_exp_mc_objc_alias_observer_enabled";
static NSMutableDictionary<NSString*,NSValue*> *gOrig;
static pthread_mutex_t gLock=PTHREAD_MUTEX_INITIALIZER;
static __thread BOOL gInside=NO;

static NSString *K(Class c,SEL s){return [NSString stringWithFormat:@"%@:%@",NSStringFromClass(c),NSStringFromSelector(s)];}
static NSString *CN(id o){Class c=o?[o class]:Nil;return c?NSStringFromClass(c):@"?";}
static NSString *BIDForCN(NSString *n){if([n isEqualToString:@"IGMobileConfigContextManager"])return @"ig";if([n isEqualToString:@"IGMobileConfigSessionlessContextManager"])return @"igsl";return @"";}
static NSString *BID(id o){return BIDForCN(CN(o));}
static NSString *ClassForBID(NSString *b){if([b isEqualToString:@"ig"])return @"IGMobileConfigContextManager";if([b isEqualToString:@"igsl"])return @"IGMobileConfigSessionlessContextManager";return @"";}
static BOOL On(NSString *k){id o=[[NSUserDefaults standardUserDefaults] objectForKey:k];return o&&[o boolValue];}
static BOOL Should(NSString *b){return b.length&&([SCIMobileConfigBrokerStore isBrokerHookEnabledForID:b]||[SCIMobileConfigBrokerStore activeOverrideKeysForBrokerID:b].count>0);} 
static IMP Orig(id o,SEL s){Class c=o?[o class]:Nil;pthread_mutex_lock(&gLock);while(c){NSValue*v=gOrig[K(c,s)];if(v){IMP i=(IMP)(uintptr_t)v.pointerValue;pthread_mutex_unlock(&gLock);return i;}c=class_getSuperclass(c);}pthread_mutex_unlock(&gLock);return NULL;}
static BOOL TSize(const char*t,NSUInteger*out){if(!t||!t[0])return NO;NSUInteger z=0;NSGetSizeAndAlignment(t,&z,NULL);if(out)*out=z;return YES;}
static BOOL BoolRet(const char*t){return t&&(t[0]=='B'||t[0]=='c'||t[0]=='C');}
static BOOL I64(const char*t){return t&&(t[0]=='Q'||t[0]=='q'||t[0]=='L'||t[0]=='l');}
static BOOL SCITypeIsPointerLike(const char*t){return t&&(t[0]=='@'||t[0]=='#'||t[0]=='^'||t[0]==':'||t[0]=='*');}
static BOOL LooksBoolU64Opt(Class c,SEL s){Method m=class_getInstanceMethod(c,s);if(!m||method_getNumberOfArguments(m)!=4)return NO;char r[64]={0},a2[64]={0},a3[64]={0};method_getReturnType(m,r,sizeof(r));method_getArgumentType(m,2,a2,sizeof(a2));method_getArgumentType(m,3,a3,sizeof(a3));NSUInteger z2=0,z3=0;return BoolRet(r)&&TSize(a2,&z2)&&TSize(a3,&z3)&&I64(a2)&&z2==8&&SCITypeIsPointerLike(a3)&&z3==sizeof(void*);}
static BOOL LooksU64U64(Class c,SEL s){Method m=class_getInstanceMethod(c,s);if(!m||method_getNumberOfArguments(m)!=3)return NO;char r[64]={0},a2[64]={0};method_getReturnType(m,r,sizeof(r));method_getArgumentType(m,2,a2,sizeof(a2));NSUInteger zr=0,z2=0;return TSize(r,&zr)&&TSize(a2,&z2)&&I64(r)&&I64(a2)&&zr==8&&z2==8;}
static void Caller(void*a,NSString**img,NSString**sym){if(img)*img=nil;if(sym)*sym=nil;if(!a)return;Dl_info i={0};if(!dladdr(a,&i))return;if(img&&i.dli_fname)*img=[@(i.dli_fname) lastPathComponent];if(sym&&i.dli_sname)*sym=@(i.dli_sname);} 
static BOOL Direct(NSString*k,BOOL*out){id o=[[NSUserDefaults standardUserDefaults] objectForKey:k];if([o isKindOfClass:NSNumber.class]){if(out)*out=[o boolValue];return YES;}return NO;}
static BOOL FinalFor(uint64_t p,NSString*b,BOOL orig){if(!On(kApplyKey)||!b.length)return orig;uint64_t n=[SCIDexKitNameResolver normalizedSpecifierValue:p];BOOL v=orig;if(Direct([NSString stringWithFormat:@"mcbr:%@:%016llx",b,(unsigned long long)p],&v))return v;if(Direct([NSString stringWithFormat:@"mcbr:%@:%016llx",b,(unsigned long long)n],&v))return v;return orig;}
static void Rec(id o,SEL s,uint64_t p,BOOL orig,BOOL fin,void*c){NSString*b=BID(o);if(!Should(b))return;NSString*ci=nil,*cs=nil;Caller(c,&ci,&cs);[SCIDexKitNameResolver noteMobileConfigBoolReadWithClassName:CN(o) selector:NSStringFromSelector(s) specifier:p defaultValue:orig originalValue:orig finalValue:fin source:@"objc-getBool:withOptions" callerImage:ci callerSymbol:cs callerAddress:(uint64_t)(uintptr_t)c];NSString*k=[SCIMobileConfigBrokerStore overrideKeyForBrokerID:b value:p];[SCIMobileConfigBrokerStore noteObservedValue:orig forOverrideKey:k];[SCIMobileConfigBrokerStore noteHitForBrokerID:b value:p forced:(orig!=fin)];}
static BOOL HBoolOpt(id o,SEL s,uint64_t p,void*opt){void*c=__builtin_return_address(0);BOOL(*orig)(id,SEL,uint64_t,void*)=(BOOL(*)(id,SEL,uint64_t,void*))Orig(o,s);if(gInside)return orig?orig(o,s,p,opt):NO;gInside=YES;BOOL ov=orig?orig(o,s,p,opt):NO;BOOL fv=FinalFor(p,BID(o),ov);Rec(o,s,p,ov,fv,c);gInside=NO;return fv;}
static uint64_t HAlias(id o,SEL s,uint64_t raw){uint64_t(*orig)(id,SEL,uint64_t)=(uint64_t(*)(id,SEL,uint64_t))Orig(o,s);if(gInside)return orig?orig(o,s,raw):raw;gInside=YES;uint64_t t=orig?orig(o,s,raw):raw;gInside=NO;if(raw&&t&&raw!=t)[SCIDexKitNameResolver noteAliasFromSpecifier:raw toSpecifier:t source:[NSString stringWithFormat:@"%@ %@",CN(o),NSStringFromSelector(s)]];return t;}
static BOOL One(Class c,NSString*n,IMP r){SEL s=NSSelectorFromString(n);if(!class_getInstanceMethod(c,s))return NO;NSString*k=K(c,s);pthread_mutex_lock(&gLock);BOOL a=gOrig[k]!=nil;pthread_mutex_unlock(&gLock);if(a)return YES;IMP old=NULL;MSHookMessageEx(c,s,r,&old);if(!old)return NO;pthread_mutex_lock(&gLock);if(!gOrig)gOrig=[NSMutableDictionary dictionary];gOrig[k]=[NSValue valueWithPointer:(const void*)(uintptr_t)old];pthread_mutex_unlock(&gLock);return YES;}
static BOOL InstallB(NSString*b){NSString*cn=ClassForBID(b);if(!cn.length){[SCIMobileConfigBrokerStore noteLastError:@"canary unsupported broker" brokerID:b];return NO;}Class c=NSClassFromString(cn);if(!c){[SCIMobileConfigBrokerStore noteLastError:[NSString stringWithFormat:@"class not loaded: %@",cn] brokerID:b];return NO;}SEL s=NSSelectorFromString(@"getBool:withOptions:");if(!LooksBoolU64Opt(c,s)){[SCIMobileConfigBrokerStore noteLastError:@"getBool:withOptions: ABI mismatch" brokerID:b];return NO;}BOOL ok=One(c,@"getBool:withOptions:",(IMP)HBoolOpt);[SCIMobileConfigBrokerStore noteLastError:(ok?@"canary live: getBool:withOptions: only; alias off":@"canary install failed") brokerID:b];return ok;}
static BOOL InstallAliasB(NSString*b){if(!On(kAliasKey))return NO;NSString*cn=ClassForBID(b);Class c=cn.length?NSClassFromString(cn):Nil;if(!c)return NO;BOOL any=NO;for(NSString*n in @[@"_getTranslatedSpecifier:",@"getTranslatedSpecifier:",@"getStableIdFromParamSpecifier:"]){SEL s=NSSelectorFromString(n);if(LooksU64U64(c,s))any=One(c,n,(IMP)HAlias)||any;}return any;}
static NSUInteger Count(void){pthread_mutex_lock(&gLock);NSUInteger c=gOrig.count;pthread_mutex_unlock(&gLock);return c;}
static void InstallBroker(NSString*b){InstallB(b);if(On(kAliasKey))InstallAliasB(b);} 
static void InstallEnabled(void){for(NSString*b in @[@"ig",@"igsl"]){if(Should(b))InstallBroker(b);}}
static void InstallPersistedIfNeeded(void){if(!Should(@"ig")&&!Should(@"igsl"))return;InstallEnabled();dispatch_async(dispatch_get_main_queue(),^{InstallEnabled();});dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{InstallEnabled();});dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{InstallEnabled();});}

#ifdef __cplusplus
extern "C" {
#endif
__attribute__((visibility("default"))) void SCIInstallObjCMobileConfigGetterObserverForBrokerID(NSString*b){InstallBroker(b);} 
__attribute__((visibility("default"))) void SCIInstallObjCMobileConfigAliasResolverObserverForBrokerID(NSString*b){[[NSUserDefaults standardUserDefaults] setBool:YES forKey:kAliasKey];InstallAliasB(b);} 
__attribute__((visibility("default"))) void SCIInstallFocusedObjCGetterObserver(void){InstallEnabled();}
__attribute__((visibility("default"))) void SCIInstallObjCMobileConfigGetterObserver(void){InstallEnabled();}
__attribute__((visibility("default"))) BOOL SCIObjCMobileConfigObserverIsInstalledForBrokerID(NSString*b){if(!b.length)return NO;pthread_mutex_lock(&gLock);NSArray*ks=[gOrig.allKeys copy];pthread_mutex_unlock(&gLock);for(NSString*k in ks){NSString*cn=[[k componentsSeparatedByString:@":"] firstObject]?:@"";if([BIDForCN(cn) isEqualToString:b])return YES;}return NO;}
__attribute__((visibility("default"))) NSUInteger SCIObjCMobileConfigObserverInstalledCount(void){return Count();}
__attribute__((visibility("default"))) void SCIObjCMobileConfigObserverInstallEnabled(void){InstallEnabled();}
#ifdef __cplusplus
}
#endif

%ctor{NSUserDefaults*ud=[NSUserDefaults standardUserDefaults];[ud registerDefaults:@{kStartupKey:@NO,kApplyKey:@NO,kAliasKey:@NO,@"sci_exp_mc_c_hooks_enabled":@NO,@"sci_exp_mc_hooks_enabled":@NO,@"sci_exp_mc_legacy_getter_hooks_enabled":@NO}];if(![ud boolForKey:@"sci_exp_default_observers_v10_preserve_persistence_done"]){for(NSString*k in @[@"sci_exp_mc_hooks_enabled",@"sci_exp_mc_c_hooks_enabled",@"sci_exp_mc_c_broker_body_hooks_enabled",@"sci_exp_mc_legacy_getter_hooks_enabled"])[ud setBool:NO forKey:k];[ud setBool:YES forKey:@"sci_exp_default_observers_v10_preserve_persistence_done"];[ud synchronize];}InstallPersistedIfNeeded();}
