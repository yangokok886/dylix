#import "Shared.h"
@interface MobileMultiFixture : NSObject
- (NSString *)message;
@end
%hook MobileMultiFixture
- (NSString *)message {
    return [FixtureMessage() stringByAppendingString:%orig];
}
%end
%ctor {
    %init;
}
