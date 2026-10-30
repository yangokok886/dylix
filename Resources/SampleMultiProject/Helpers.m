#import "Shared.h"
NSString *FixtureMessage(void) { return [NSString stringWithFormat:@"Built on iPhone: %d/%d", FixtureCValue(), FixtureBridgeValue()]; }
