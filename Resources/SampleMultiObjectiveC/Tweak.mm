#line 1 "TheosMobileCompiler/Resources/SampleMultiProject/Tweak.xm"
#import "Shared.h"

#include <substrate.h>
#if defined(__clang__)
#if __has_feature(objc_arc)
#define _LOGOS_SELF_TYPE_NORMAL __unsafe_unretained
#define _LOGOS_SELF_TYPE_INIT __attribute__((ns_consumed))
#define _LOGOS_SELF_CONST const
#define _LOGOS_RETURN_RETAINED __attribute__((ns_returns_retained))
#else
#define _LOGOS_SELF_TYPE_NORMAL
#define _LOGOS_SELF_TYPE_INIT
#define _LOGOS_SELF_CONST
#define _LOGOS_RETURN_RETAINED
#endif
#else
#define _LOGOS_SELF_TYPE_NORMAL
#define _LOGOS_SELF_TYPE_INIT
#define _LOGOS_SELF_CONST
#define _LOGOS_RETURN_RETAINED
#endif

__asm__(".linker_option \"-framework\", \"CydiaSubstrate\"");

@class MobileMultiFixture; 
static NSString * (*_logos_orig$_ungrouped$MobileMultiFixture$message)(_LOGOS_SELF_TYPE_NORMAL MobileMultiFixture* _LOGOS_SELF_CONST, SEL); static NSString * _logos_method$_ungrouped$MobileMultiFixture$message(_LOGOS_SELF_TYPE_NORMAL MobileMultiFixture* _LOGOS_SELF_CONST, SEL); 

#line 2 "TheosMobileCompiler/Resources/SampleMultiProject/Tweak.xm"
@interface MobileMultiFixture : NSObject
- (NSString *)message;
@end

static NSString * _logos_method$_ungrouped$MobileMultiFixture$message(_LOGOS_SELF_TYPE_NORMAL MobileMultiFixture* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd) {
    return [FixtureMessage() stringByAppendingString:_logos_orig$_ungrouped$MobileMultiFixture$message(self, _cmd)];
}

static __attribute__((constructor)) void _logosLocalCtor_03738126(int __unused argc, char __unused **argv, char __unused **envp) {
    {Class _logos_class$_ungrouped$MobileMultiFixture = objc_getClass("MobileMultiFixture"); { MSHookMessageEx(_logos_class$_ungrouped$MobileMultiFixture, @selector(message), (IMP)&_logos_method$_ungrouped$MobileMultiFixture$message, (IMP*)&_logos_orig$_ungrouped$MobileMultiFixture$message);}}
}
