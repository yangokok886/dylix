#import <Foundation/Foundation.h>
@interface TMCGitAutomation : NSObject
+ (instancetype)shared;
- (void)saved:(NSString *)root;
- (void)buildStarted:(NSString *)root;
- (void)buildFinished:(NSString *)root success:(BOOL)success;
- (void)cancelPending:(NSString *)root;
@end

#if TARGET_OS_SIMULATOR
@class UIViewController;
UIViewController *TMCGitAutomationRegression(void);
#endif
