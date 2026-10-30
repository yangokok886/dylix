#import <Foundation/Foundation.h>
// Repairs unfinished tool-call transcripts without executing any operation.
NSArray *TFAIRecoveryTranscript(NSArray *messages);
NSDictionary *TFAIRecoveryContinuation(void);
