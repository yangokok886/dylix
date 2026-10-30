#import <Foundation/Foundation.h>
// Main-thread API. One system task covers all active conversations in this process.
void TFAIBackgroundRegister(void);
NSString *TFAIBackgroundBegin(void (^expired)(NSString *reason));
void TFAIBackgroundUpdate(NSString *token,NSDictionary *event);
void TFAIBackgroundEnd(NSString *token,BOOL success);
NSString *TFAIBackgroundStatus(void);

NSDictionary *TFAIBackgroundDiagnostics(void);

void TFAIBackgroundSetAudioEnabled(BOOL enabled);
