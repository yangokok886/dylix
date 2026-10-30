#import <UIKit/UIKit.h>
// Local test samples only. No credentials or user conversation content in reports.
NSDictionary *TFAIRecordProbeResult(NSMutableDictionary *connection,NSString *capability,NSDictionary *result,NSError *error);
NSString *TFAIProbeReport(NSDictionary *record,NSString *capability);
UIViewController *TFAITestDetailController(NSMutableDictionary *connection,NSString *capability,NSDictionary *record,BOOL allowRetest);
