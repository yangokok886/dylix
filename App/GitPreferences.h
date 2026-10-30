#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Hold a lease for the complete file transaction, on the acquiring thread.
@interface TMCGitLease : NSObject
+ (nullable instancetype)tryWrite NS_RETURNS_RETAINED;
+ (instancetype)acquire NS_RETURNS_RETAINED;
+ (void)setBuilding:(BOOL)building root:(NSString *)root;
+ (BOOL)hasActiveBuilds;
+ (BOOL)isBuilding:(NSString *)root;
@end
@interface TMCGitPreferences : NSObject
+ (NSDictionary *)global;
+ (void)saveGlobal:(NSDictionary *)settings;
+ (NSDictionary *)project:(NSString *)root;
+ (BOOL)saveProject:(NSDictionary *)settings root:(NSString *)root error:(NSError **)error;
+ (void)confirmPushURL:(NSString *)url branch:(NSString *)branch root:(NSString *)root;
+ (NSDictionary *)effective:(NSString *)root;
+ (NSArray<NSDictionary *> *)accounts;
+ (NSString *)origin:(NSString *)url;
+ (NSString *)repositoryKey:(NSString *)url;
+ (BOOL)saveAccount:(NSDictionary *)account token:(NSString *)token error:(NSError **)error;
+ (void)deleteAccount:(NSString *)identifier;
+ (NSDictionary *)credential:(NSString *)url root:(NSString *)root;
+ (NSArray *)records:(NSString *)root;
+ (void)record:(NSDictionary *)event root:(NSString *)root;
@end
NS_ASSUME_NONNULL_END
