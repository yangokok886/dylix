#import <Foundation/Foundation.h>
@class UIViewController;
typedef NSUInteger UIBackgroundTaskIdentifier;
static const UIBackgroundTaskIdentifier UIBackgroundTaskInvalid=NSUIntegerMax;
typedef NS_ENUM(NSInteger,UIApplicationState){UIApplicationStateActive,UIApplicationStateInactive,UIApplicationStateBackground};
extern NSString *UIApplicationDidBecomeActiveNotification;
extern NSString *UIApplicationDidEnterBackgroundNotification;
@interface UIApplication : NSObject
@property(class,readonly) UIApplication *sharedApplication;
@property UIApplicationState applicationState;
@property NSTimeInterval backgroundTimeRemaining;
@property NSMutableDictionary<NSNumber *,void (^)(void)> *expirations;
@property NSUInteger counter,ended;
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithName:(NSString *)name expirationHandler:(void (^)(void))handler;
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)task;
@end
