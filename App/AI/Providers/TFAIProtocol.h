#import "../AIContracts.h"
NS_ASSUME_NONNULL_BEGIN
NSArray<NSDictionary *> *TFAIProtocolCatalog(void);
NSDictionary *TFAIModelPage(id payload);
NSArray<NSDictionary *> *TFAIReasoningOptions(NSDictionary *connection);
NSString *TFAIThinkingScope(NSDictionary *connection);
NSDictionary *TFAIThinkingConfiguration(NSDictionary *connection);
NSString *TFAIValidatedReasoningEffort(NSDictionary *connection, NSString * _Nullable effort);
NSString *TFAIReasoningRequestSummary(NSDictionary *body, NSDictionary *connection);
NSDictionary *TFAISanitizeProbeDiagnostics(NSDictionary *diagnostics, NSString * _Nullable secret);
NSError *TFAIError(NSInteger code, NSString *message);
NSURL * _Nullable TFAIEndpoint(NSDictionary *connection, BOOL models, NSError **error);
NSDictionary * _Nullable TFAIRequestBody(NSArray *messages,NSDictionary *connection,NSArray *tools,BOOL stream,NSError **error);
@interface TFAIStreamDecoder : NSObject
- (instancetype)initWithProtocol:(NSString *)protocol event:(TFAIEvent)event;
- (void)appendData:(NSData *)data;
- (void)finish;
- (void)acceptJSON:(NSDictionary *)json;
@property(nonatomic,readonly) BOOL ended;
@end
NS_ASSUME_NONNULL_END
