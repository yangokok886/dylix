#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// In-memory, user-controlled permissions. Never configure from model/tool/file text.
// Presets: ask / assisted / scoped / full / full_push / full_download / full_network.
// Full presets are explicit, in-memory current-project grants. They never bypass tool preparation,
// path/precondition validation or backups; their optional network grants are independent.
@interface TFAIRuntimePolicy : NSObject
- (instancetype)initWithRoot:(NSString *)root projectID:(NSString *)projectID sessionID:(NSString *)sessionID;
@property(nonatomic,readonly,copy) NSString *preset;
@property(nonatomic,readonly,copy) NSArray<NSString *> *paths;
@property(nonatomic,readonly) NSTimeInterval expiresAt;
// Changing session/preset revokes every old fingerprint grant. Scoped paths are exact files.
- (BOOL)configurePreset:(NSString *)preset paths:(NSArray<NSString *> *)paths session:(NSString *)sessionID error:(NSError **)error;
// decision: allowed | needsApproval | denied; readOnly, separateConfirmation, reason, preset.
// allowed for read/propose; scoped additionally allows build until expiry.
// Full presets also allow prepared project mutations. Upload/download remain separately scoped.
- (NSDictionary *)decisionForPlan:(NSDictionary *)plan;
// Single-use grant ONLY for reviewed safe source edits/create/build; dangerous operations
// (config/delete/network/Git/full replacement) always use their independent UI confirmation.
- (BOOL)grantReviewedPlan:(NSDictionary *)plan session:(NSString *)sessionID error:(NSError **)error;
// Consume immediately before toolbox execution. Toolbox still revalidates source hashes/lease.
- (BOOL)consumeReviewedPlan:(NSDictionary *)plan error:(NSError **)error;
- (void)revoke;
@end
NS_ASSUME_NONNULL_END
