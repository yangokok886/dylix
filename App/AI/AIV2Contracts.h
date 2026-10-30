#import "AIContracts.h"
NS_ASSUME_NONNULL_BEGIN
// v2 session identity: storage scope is project UUID or "general"; association is metadata.
// Records returned by summaries contain storageProjectID, id,title,summary,updatedAt,pinned,projectName,projectRoot.
@interface TFAISessions (V2)
+ (NSArray<NSDictionary *> *)summaries:(nullable NSString *)scope;
+ (nullable NSMutableDictionary *)loadSession:(NSString *)identifier project:(NSString *)scope;
+ (BOOL)saveMetadata:(NSDictionary *)metadata identifier:(NSString *)identifier project:(NSString *)scope error:(NSError **)error;
@end
#if __has_include(<UIKit/UIKit.h>)
FOUNDATION_EXPORT UIViewController *TFAISessionHomeController(NSString * _Nullable scope, NSArray<NSDictionary *> *(^projects)(void), void (^open)(NSDictionary *record), void (^associate)(NSDictionary *record, NSDictionary *project));
// Main owns implementations. Explicit selection affects next request only.
@protocol TFAIRuntimeV2 <TFAIRuntime>
- (void)setNextConnection:(nullable NSDictionary *)connection;
- (void)setInteractionMode:(NSString *)mode; // ask (read tools only) | develop (existing approval)
@end
// UI owns configure existing factory result before loading view. session = selected record, no new empty session.
FOUNDATION_EXPORT UIViewController *TFAIConfigureChat(UIViewController *controller, NSDictionary *session, BOOL standalone, void (^associate)(NSDictionary *));
FOUNDATION_EXPORT void TFAIRebindRuntime(id<TFAIRuntime> runtime,void (^bridge)(NSString *,NSDictionary *,TFAIResult));
FOUNDATION_EXPORT void TFAISetProjectContext(UIViewController *controller,id owner,void (^bridge)(NSString *,NSDictionary *,TFAIResult));
// Attachment package owns native source browser + import staging. Entries lazy references, never direct grants.
FOUNDATION_EXPORT UIViewController *TFAIAttachmentBrowser(NSString * _Nullable currentRoot, NSArray<NSDictionary *> *projects, void (^selected)(NSArray<NSDictionary *> *entries));
FOUNDATION_EXPORT void TFAIImportAttachmentURLs(NSArray<NSURL *> *urls, void (^completion)(NSArray<NSDictionary *> *,NSError * _Nullable));
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable TFAIResolveAttachments(NSArray<NSDictionary *> *entries,NSError **error);
FOUNDATION_EXPORT UIViewController *TFAIAttachmentPreview(NSDictionary *entry);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TFAIInternalProjects(void); // main, roots only inside app Documents/Projects
#endif
NS_ASSUME_NONNULL_END

@class UIViewController;
FOUNDATION_EXPORT void TFAISetSessionOpener(UIViewController *controller,void(^open)(NSDictionary *record));
