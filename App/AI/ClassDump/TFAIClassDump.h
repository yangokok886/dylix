#import <Foundation/Foundation.h>
// Import a selected IPA or ARM64 Mach-O, recover ObjC declarations in-process.
// Creates a new output directory; never modifies the input or existing projects.
NSDictionary *TFAIClassDumpFile(NSString *input,NSString *output,NSProgress *cancel,void(^progress)(double,NSString *),NSError **error);
BOOL TFAIClassDumpZip(NSString *directory,NSString *zip,NSError **error);
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
UIViewController *TFAIClassDumpController(void);
#endif
// Caller must authorize jobID from a user-selected attachment before reading.
NSDictionary *TFAIClassDumpRead(NSString *jobID,NSDictionary *arguments,NSError **error);
#if __has_include(<UIKit/UIKit.h>)
UIViewController *TFAIClassDumpControllerWithCompletion(void(^completion)(NSDictionary *));
#endif
