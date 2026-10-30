#import <Foundation/Foundation.h>
// Local presentation metadata only; never changes model conversation content.
NSArray<NSDictionary *> *TFAIConversationTimeline(NSArray *messages,NSArray *records,NSDictionary *summaries,NSString *legacySummary,NSDictionary *folds);
// Ephemeral progress belongs to the message stream, never the model transcript.
NSArray<NSDictionary *> *TFAIConversationWithStatus(NSArray *timeline,BOOL active,NSString *status,NSString *activeMessageID);

// One turn-level disclosure; tool records remain nested disclosures.
NSArray<NSDictionary *> *TFAIConversationGrouped(NSArray *timeline,NSDictionary *folds);

NSArray<NSDictionary *> *TFAIConversationTimed(NSArray *timeline,NSDictionary *timings,NSTimeInterval now);
