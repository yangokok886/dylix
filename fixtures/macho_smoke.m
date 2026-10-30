#import <Foundation/Foundation.h>

@interface MobileCompilerSmoke : NSObject
- (NSString *)message;
@end

@implementation MobileCompilerSmoke
- (NSString *)message {
    return @"arm64 Mach-O compile smoke test";
}
@end
