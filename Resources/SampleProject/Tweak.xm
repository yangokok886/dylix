#import <Foundation/Foundation.h>

@interface MobileLogosFixture : NSObject
- (NSString *)message;
@end

%hook MobileLogosFixture
- (NSString *)message {
    return @"Compiled locally by Logos";
}
%end
