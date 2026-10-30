#import <Foundation/Foundation.h>
NSDictionary *TFAIBinaryStage(NSData *data,NSString *name,NSError **error);
NSArray<NSDictionary *> *TFAIBinarySchemas(void);
NSDictionary *TFAIBinaryExecute(NSString *identifier,NSDictionary *arguments,NSError **error);
NSDictionary *TFAIBinaryParse(NSData *data,NSDictionary *arguments,NSError **error);

NSSet *TFAIBinarySelectedIDs(NSDictionary *references);
