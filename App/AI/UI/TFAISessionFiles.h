#import <UIKit/UIKit.h>
UIViewController *TFAISessionFilesController(NSDictionary *session,NSString *projectRoot);

UIViewController *TFAISessionFilesControllerWithNavigation(NSDictionary *session,NSString *projectRoot,void (^locateMessage)(NSString *messageID));
