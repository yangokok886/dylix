#import "../AIContracts.h"
FOUNDATION_EXPORT void TFAIAddContext(UIViewController *controller,NSString *text,NSString *title);
// "availability" checks menu sources: {build_log: BOOL, diagnostics: BOOL}.
// User-selected "build_log" / "diagnostics" returns {text, title, available}.
// Empty sources must not return placeholder text or a whole build-result report.
FOUNDATION_EXPORT void TFAISetContextProvider(UIViewController *controller,void (^provider)(NSString *kind,TFAIResult completion));
