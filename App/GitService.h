#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Synchronous methods; caller schedules on the shared serial queue, never main.
@interface TMCGitService : NSObject
@property(nonatomic,copy) NSString *root;
@property(atomic) BOOL cancelled;
@property(nonatomic,copy,nullable) void (^progress)(NSString *message,double fraction);
+ (dispatch_queue_t)queue;
- (instancetype)initWithRoot:(NSString *)root;
- (nullable NSDictionary *)status:(NSError **)error;
- (BOOL)initialize:(NSError **)error;
- (BOOL)stage:(NSArray<NSString *> *)paths remove:(BOOL)remove error:(NSError **)error;
- (nullable NSString *)commit:(NSString *)message name:(NSString *)name email:(NSString *)email error:(NSError **)error;
- (nullable NSArray *)history:(NSError **)error;
- (nullable NSString *)diff:(nullable NSString *)path revision:(nullable NSString *)revision staged:(BOOL)staged error:(NSError **)error;
- (nullable NSDictionary *)restorePreview:(NSString *)path revision:(NSString *)revision error:(NSError **)error;
- (nullable NSDictionary *)revisionRestorePreview:(NSString *)revision error:(NSError **)error;
- (nullable NSDictionary *)archive:(NSString *)message protection:(BOOL)protection name:(NSString *)name email:(NSString *)email error:(NSError **)error;
- (NSDictionary *)pushArchive:(NSString *)commitID foreground:(BOOL)foreground;
- (nullable NSString *)checkpoint:(NSString *)reason error:(NSError **)error;
- (BOOL)applyRestore:(NSDictionary *)plan error:(NSError **)error;
- (BOOL)undoRestore:(NSError **)error;
- (nullable NSArray *)branches:(NSError **)error;
- (BOOL)branch:(NSString *)name action:(NSString *)action error:(NSError **)error;
- (BOOL)setUpstream:(NSString *)name error:(NSError **)error;
- (BOOL)setRemote:(NSString *)url error:(NSError **)error;
- (BOOL)cloneURL:(NSString *)url error:(NSError **)error;
- (BOOL)network:(NSString *)action name:(NSString *)name email:(NSString *)email error:(NSError **)error;
- (nullable NSArray *)conflicts:(NSError **)error;
- (BOOL)resolve:(NSString *)path choice:(NSString *)choice text:(nullable NSString *)text expected:(NSString *)fingerprint error:(NSError **)error;
- (BOOL)mergeBranch:(NSString *)branch error:(NSError **)error;
- (BOOL)abortMerge:(NSError **)error;
+ (BOOL)saveCredentialForURL:(NSString *)url username:(NSString *)username token:(NSString *)token error:(NSError **)error;
+ (NSDictionary *)credentialForURL:(NSString *)url;
+ (void)deleteCredentialForURL:(NSString *)url;
@end
NS_ASSUME_NONNULL_END
