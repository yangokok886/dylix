#import <Foundation/Foundation.h>
#define TFShareGroup @"group.com.xuegao.tweakforge.share"
NSDictionary *TFIncomingStage(NSURL *url,NSError **error);
NSDictionary *TFIncomingIdentify(NSString *path,NSError **error);
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
void TFIncomingReceive(UIViewController *host,NSURL *url);
void TFIncomingDrain(UIViewController *host);
void TFIncomingPresent(UIViewController *host,NSDictionary *record);
UIViewController *TFIncomingHistory(void);
UIViewController *TFBinaryWorkbench(NSDictionary *entry);
void TFStudioImportReceived(UIViewController *host,NSURL *url,BOOL archive);
void TFStudioReceiveAttachments(UIViewController *host,NSArray *entries,NSDictionary *session);
void TFStudioOpenReceivedProject(UIViewController *host,NSString *root);
#endif
