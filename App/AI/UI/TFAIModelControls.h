#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT UIViewController *TFAIModelControlsController(NSDictionary * _Nullable connection,NSString *effort,void(^chooseModel)(void),void(^changeEffort)(NSString *));
FOUNDATION_EXPORT UIViewController *TFAIPermissionControlsController(NSString *mode,BOOL allowPush,BOOL allowDownload,NSString *projectName,void(^changePermission)(NSString *,BOOL,BOOL));
NS_ASSUME_NONNULL_END
