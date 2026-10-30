#import <Foundation/Foundation.h>
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#endif
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL TFAISessionHasLiveRun(NSString *projectID,NSString *sessionID);
FOUNDATION_EXPORT void TFAISetSessionLiveRun(NSString *projectID,NSString *sessionID,BOOL active);
// v1: all UI callbacks on main. JSON dictionaries only across module boundaries.
// Message: {role: user|assistant|tool, content: string, images:[{data:base64,mime:string}],
// tool_calls:[{id,name,arguments:object}], tool_call_id:string}.
// Event: {type:text|tool_call|usage|done|error, text?, id?, name?, arguments?, message?}.
typedef void (^TFAIEvent)(NSDictionary *event);
typedef void (^TFAIResult)(NSDictionary * _Nullable result, NSError * _Nullable error);
// Settings connection: {id,name,protocol:chat|responses|anthropic,baseURL,model,models:[],allowLANHTTP:false}.
// Never store secrets in settings; keychain keyed by connection id.
@interface TFAIConnections : NSObject
+ (NSArray<NSDictionary *> *)all;
+ (BOOL)save:(NSDictionary *)connection secret:(nullable NSString *)secret error:(NSError **)error;
+ (void)remove:(NSString *)identifier;
+ (NSString *)secret:(NSString *)identifier;
+ (nullable NSDictionary *)effectiveForProject:(nullable NSString *)projectID;
+ (void)setConnection:(nullable NSString *)identifier project:(nullable NSString *)projectID;
@end
@interface TFAITransport : NSObject
- (void)send:(NSArray<NSDictionary *> *)messages connection:(NSDictionary *)connection tools:(NSArray<NSDictionary *> *)tools event:(TFAIEvent)event;
- (void)cancel;
- (void)discover:(NSDictionary *)connection completion:(TFAIResult)completion;
- (void)probe:(NSDictionary *)connection capability:(NSString *)capability completion:(TFAIResult)completion;
@end
// Tool schemas are OpenAI function objects {name,description,parameters}; no type:function wrapper.
// Requests: {id,name,arguments:object}. prepare has NO side effects.
// Plan: {id,request,approval:bool,summary,edits:[{path,before,after,kind}],...opaque preconditions}.
// Only execute a plan returned by prepare; exact fingerprint checked after approval.
@interface TFAIToolbox : NSObject
- (instancetype)initWithRoot:(NSString *)root projectID:(NSString *)projectID sessionID:(NSString *)sessionID;
@property(nonatomic,copy,nullable) void (^bridge)(NSString *name, NSDictionary *arguments,TFAIResult completion);
+ (NSArray<NSDictionary *> *)schemas;
- (void)prepare:(NSDictionary *)request completion:(TFAIResult)completion;
- (void)selectEdits:(NSArray<NSNumber *> *)indexes plan:(NSDictionary *)plan completion:(TFAIResult)completion;
- (void)setApprovalContext:(NSString *)context; // local UI/runtime provenance; never supplied by model
- (void)execute:(NSDictionary *)plan approved:(BOOL)approved completion:(TFAIResult)completion;
- (void)undo:(TFAIResult)completion;
- (void)cancel;
@end
// Session stores outside project; UUID provided by main is stable across rename.
@interface TFAISessions : NSObject
+ (NSArray<NSDictionary *> *)sessions:(NSString *)projectID;
+ (NSMutableDictionary *)create:(NSString *)projectID title:(NSString *)title;
+ (BOOL)save:(NSDictionary *)session project:(NSString *)projectID error:(NSError **)error;
+ (void)remove:(NSString *)sessionID project:(NSString *)projectID;
+ (NSArray<NSDictionary *> *)contextForPaths:(NSArray<NSString *> *)paths root:(NSString *)root error:(NSError **)error;
@end
#if __has_include(<UIKit/UIKit.h>)
// UI owns conversation persistence. Runtime sends events, requests approval on main,
// and receives a decision exactly once. Do not persist grants on session restoration.
@protocol TFAIRuntime <NSObject>
@property(nonatomic,copy,nullable) TFAIEvent event;
@property(nonatomic,copy,nullable) void (^approval)(NSDictionary *plan, void (^decision)(BOOL approved, NSArray<NSNumber *> * _Nullable selectedEditIndexes));
- (void)send:(NSArray<NSDictionary *> *)messages session:(NSString *)sessionID;
- (void)stop;
- (void)setBuildAllowed:(BOOL)allowed;
- (void)activateSession:(NSString *)sessionID;
- (BOOL)configurePermissionPreset:(NSString *)preset paths:(NSArray<NSString *> *)paths error:(NSError **)error;
- (void)undo:(TFAIResult)completion;
@end
FOUNDATION_EXPORT UIViewController *TFAISettingsController(NSString * _Nullable projectID);
FOUNDATION_EXPORT UIViewController *TFAIChatController(NSString *root, NSString *projectID, id<TFAIRuntime> runtime, void (^openFile)(NSString *,NSUInteger));
// Main-owned factory / integration.
FOUNDATION_EXPORT id<TFAIRuntime> TFAICreateRuntime(NSString *root,NSString *projectID,void (^bridge)(NSString *,NSDictionary *,TFAIResult));
FOUNDATION_EXPORT NSString *TFAIProjectID(NSString *root);
#endif
NS_ASSUME_NONNULL_END
