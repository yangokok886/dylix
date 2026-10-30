#import <Foundation/Foundation.h>
NSDictionary *TFAIClassDumpStage(NSURL *url,NSError **error);
NSDictionary *TFAIClassDumpExecute(NSString *inputID,NSProgress *cancel,void(^progress)(double,NSString *),NSError **error);
NSURL *TFAIClassDumpExportURL(NSString *jobID);
