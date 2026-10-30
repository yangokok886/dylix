#import <Foundation/Foundation.h>
@interface TFGitHubRepositories : NSObject <NSURLSessionTaskDelegate>
@property(nonatomic) NSURLSession *session;
@property(nonatomic,readonly) NSString *origin;
@property(nonatomic,readonly) NSString *serviceName;
// Only GitHub.com and Gitee.com API endpoints; token never follows redirects.
- (instancetype)initWithOrigin:(NSString *)origin;
- (void)listWithToken:(NSString *)token completion:(void (^)(NSArray *,NSError *))completion;
- (void)createPrivate:(NSString *)name token:(NSString *)token completion:(void (^)(NSDictionary *,NSError *))completion;
+ (BOOL)validRepositoryName:(NSString *)name;
@end
