#import <UIKit/UIKit.h>
UIViewController *TFAIModelPicker(NSDictionary *selected,void (^selection)(NSDictionary *connection));
NSArray<NSDictionary *> *TFAIAvailableModels(void);
NSString *TFAIModelKey(NSDictionary *connection);
