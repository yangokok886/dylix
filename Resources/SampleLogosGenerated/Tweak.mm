#line 1 "TheosMobileCompiler/Resources/SampleProject/Tweak.xm"
#import <Foundation/Foundation.h>

@interface MobileLogosFixture : NSObject
- (NSString *)message;
@end


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

@class MobileLogosFixture; 
static NSString * (*_logos_orig$_ungrouped$MobileLogosFixture$message)(_LOGOS_SELF_TYPE_NORMAL MobileLogosFixture* _LOGOS_SELF_CONST, SEL); static NSString * _logos_method$_ungrouped$MobileLogosFixture$message(_LOGOS_SELF_TYPE_NORMAL MobileLogosFixture* _LOGOS_SELF_CONST, SEL); 

#line 7 "TheosMobileCompiler/Resources/SampleProject/Tweak.xm"

static NSString * _logos_method$_ungrouped$MobileLogosFixture$message(_LOGOS_SELF_TYPE_NORMAL MobileLogosFixture* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd) {
    return @"Compiled locally by Logos";
}

static __attribute__((constructor)) void _logosLocalInit() {
{Class _logos_class$_ungrouped$MobileLogosFixture = objc_getClass("MobileLogosFixture"); { MSHookMessageEx(_logos_class$_ungrouped$MobileLogosFixture, @selector(message), (IMP)&_logos_method$_ungrouped$MobileLogosFixture$message, (IMP*)&_logos_orig$_ungrouped$MobileLogosFixture$message);}} }
#line 12 "TheosMobileCompiler/Resources/SampleProject/Tweak.xm"
