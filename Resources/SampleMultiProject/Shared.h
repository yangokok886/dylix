#pragma once
#ifdef __cplusplus
extern "C" {
#endif
int FixtureCValue(void);
int FixtureCppValue(void);
int FixtureBridgeValue(void);
#ifdef __OBJC__
#import <Foundation/Foundation.h>
NSString *FixtureMessage(void);
#endif
#ifdef __cplusplus
}
#endif
