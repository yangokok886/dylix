#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
UIViewController *TMCGitSettingsController(NSString * _Nullable root);
UIViewController *TMCGitController(NSString *root,void (^ _Nullable changed)(void));
UIViewController *TMCGitCloneController(NSString *projects,void (^completion)(NSString *root));
#if TARGET_OS_SIMULATOR
UIViewController *TMCGitRegression(void);
#endif

NS_ASSUME_NONNULL_END
