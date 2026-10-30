#import "TFAILiveActivity.h"
#import <objc/message.h>
#import <dlfcn.h>
static NSString *bridgeError;
static Class ActivityBridge(void){if(@available(iOS 16.2,*)){static Class cls;static dispatch_once_t once;dispatch_once(&once,^{NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"TFTaskActivity.framework/TFTaskActivity"];if(dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL)){cls=NSClassFromString(@"TFTaskLiveActivity");if(!cls)bridgeError=@"实时活动类未加载";}else{const char *error=dlerror();bridgeError=error?@(error):@"实时活动框架未加载";NSLog(@"[AI Live Activity] %@",bridgeError);}});return cls;}return Nil;}
void TFAILiveUpdate(NSString *stage,NSUInteger count,NSUInteger steps){Class cls=ActivityBridge();if(cls)((void(*)(id,SEL,id,NSInteger,NSInteger))objc_msgSend)(cls,NSSelectorFromString(@"update:count:steps:"),stage,count,steps);}
void TFAILiveEnd(BOOL success){Class cls=ActivityBridge();if(cls)((void(*)(id,SEL,BOOL))objc_msgSend)(cls,NSSelectorFromString(@"finish:"),success);}

NSString *TFAILiveStatus(void){Class cls=ActivityBridge();if(cls)return ((id(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"status"));return bridgeError?:@"当前系统未启用实时活动";}
