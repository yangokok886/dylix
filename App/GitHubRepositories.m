#import "GitHubRepositories.h"
static NSError *GHError(NSString *message){return [NSError errorWithDomain:@"TweakForge.GitHub" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
@interface TFGitHubRedirectPolicy : NSObject <NSURLSessionTaskDelegate>
@end
@implementation TFGitHubRedirectPolicy
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion{completion(nil);}
@end
@implementation TFGitHubRepositories
- (instancetype)init{return [self initWithOrigin:@"https://github.com"];}
- (instancetype)initWithOrigin:(NSString *)origin{if(![@[@"https://github.com",@"https://gitee.com"] containsObject:origin])return nil;if((self=[super init])){_origin=[origin copy];_serviceName=[origin isEqual:@"https://gitee.com"]?@"Gitee":@"GitHub";NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.timeoutIntervalForRequest=30;c.timeoutIntervalForResource=60;c.URLCache=nil;c.HTTPCookieStorage=nil;c.URLCredentialStorage=nil;_session=[NSURLSession sessionWithConfiguration:c delegate:[TFGitHubRedirectPolicy new] delegateQueue:nil];}return self;}
- (BOOL)isGitee{return [self.origin isEqual:@"https://gitee.com"];}
- (void)dealloc{[_session invalidateAndCancel];}
+ (BOOL)validRepositoryName:(NSString *)name{if(![name isKindOfClass:NSString.class]||!name.length||name.length>100||[@[@".",@".."] containsObject:name])return NO;return [name rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"] invertedSet]].location==NSNotFound;}
- (void)request:(NSString *)path method:(NSString *)method body:(NSDictionary *)body token:(NSString *)token completion:(void (^)(id,NSError *))completion{
 if(!token.length){completion(nil,GHError(@"此账号没有可用 PAT，请到设置 → Git → 服务账号更新令牌。"));return;}
 NSString *base=self.isGitee?@"https://gitee.com/api/v5":@"https://api.github.com";
 NSURLComponents *url=[NSURLComponents componentsWithString:[base stringByAppendingString:path]];
 NSMutableDictionary *payload=[body mutableCopy];
 if(self.isGitee){if([method isEqual:@"GET"]){NSMutableArray *query=[url.queryItems mutableCopy]?:[NSMutableArray new];[query addObject:[NSURLQueryItem queryItemWithName:@"access_token" value:token]];url.queryItems=query;}else{if(!payload)payload=[NSMutableDictionary new];payload[@"access_token"]=token;}}
 NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:url.URL];r.HTTPMethod=method;
 if(!self.isGitee){[r setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];[r setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];}
 [r setValue:self.isGitee?@"application/json":@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];[r setValue:@"Dylix" forHTTPHeaderField:@"User-Agent"];
 if(payload){r.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];}

 [[self.session dataTaskWithRequest:r completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){if(error){completion(nil,GHError([NSString stringWithFormat:@"连接 %@ 未完成，请检查网络后重试。创建操作如超时，请先刷新仓库列表确认结果，避免重复创建。",self.serviceName]));return;}NSInteger status=[(NSHTTPURLResponse *)response statusCode];if(status<200||status>=300){NSString *message=status==401?@"GitHub 认证未通过：PAT 可能过期或已撤销，请更新服务账号。":status==403?@"GitHub 拒绝此操作：请检查令牌仓库范围、创建仓库权限、组织策略或 API 频率限制。细粒度 PAT 创建个人仓库通常需要 Administration 写权限；后续推送还需 Contents 写权限。":status==422?@"仓库创建未完成：名称可能已被占用或不符合 GitHub 要求。请刷新列表检查已有仓库，或使用其他名称。":status==404?@"GitHub 资源未找到，或此账号没有访问权限。":status==429?@"GitHub 请求过于频繁，请稍后再试。":@"GitHub 服务暂未完成操作，请稍后重试。";if(self.isGitee){message=[message stringByReplacingOccurrencesOfString:@"GitHub" withString:@"Gitee"];if(status==403)message=@"Gitee 拒绝此操作：请检查账号仓库权限、令牌 projects 范围、账号限制或 API 频率限制。";}completion(nil,GHError(message));return;}if(data.length>10*1024*1024){completion(nil,GHError(@"仓库服务返回数据过大，请稍后重试。"));return;}id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];if(!value){completion(nil,GHError(@"仓库服务返回的内容格式有误。"));return;}completion(value,nil);}] resume];
}
- (NSDictionary *)repository:(id)value{if(![value isKindOfClass:NSDictionary.class])return nil;
 NSString *name=value[@"full_name"],*url=self.isGitee?value[@"html_url"]:value[@"clone_url"];
 NSURLComponents *c=[url isKindOfClass:NSString.class]?[NSURLComponents componentsWithString:url]:nil;
 NSString *host=self.isGitee?@"gitee.com":@"github.com";
 if(![name isKindOfClass:NSString.class]||!name.length||![c.scheme isEqual:@"https"]||![c.host isEqual:host]||c.user.length||c.password.length||c.query.length||c.fragment.length||c.port||c.path.pathComponents.count!=3||![value[@"private"] isKindOfClass:NSNumber.class])return nil;
 for(NSString *part in c.path.pathComponents)if([@[@".",@".."] containsObject:part]||[part containsString:@"%"]||[part containsString:@"\\"]||[part containsString:@"?"]||[part containsString:@"#"])return nil;
 if(self.isGitee&&![url hasSuffix:@".git"])url=[url stringByAppendingString:@".git"];
 id permissions=value[self.isGitee?@"permission":@"permissions"];
 BOOL push=[permissions isKindOfClass:NSDictionary.class]&&[permissions[@"push"] isKindOfClass:NSNumber.class]&&[permissions[@"push"] boolValue];
 return @{@"name":name,@"url":url,@"private":@([value[@"private"] boolValue]),@"push":@(push)};
}
- (void)page:(NSUInteger)page token:(NSString *)token results:(NSMutableArray *)results completion:(void (^)(NSArray *,NSError *))completion{[self request:[NSString stringWithFormat:@"/user/repos?per_page=100&page=%lu&sort=updated&affiliation=owner,collaborator,organization_member",(unsigned long)page] method:@"GET" body:nil token:token completion:^(id value,NSError *error){if(error){completion(nil,error);return;}if(![value isKindOfClass:NSArray.class]){completion(nil,GHError(@"仓库列表格式有误。"));return;}for(id item in value){NSDictionary *repo=[self repository:item];if(repo)[results addObject:repo];}if([value count]==100&&page<20){[self page:page+1 token:token results:results completion:completion];return;}if([value count]==100&&page==20){completion(nil,GHError(@"此账号仓库超过当前列表上限（2000）；请使用手动地址连接。"));return;}completion(results,nil);}];}
- (void)listWithToken:(NSString *)token completion:(void (^)(NSArray *,NSError *))completion{[self page:1 token:token results:[NSMutableArray new] completion:completion];}
- (void)createPrivate:(NSString *)name token:(NSString *)token completion:(void (^)(NSDictionary *,NSError *))completion{if(![self.class validRepositoryName:name]){completion(nil,GHError(@"仓库名使用 1～100 个英文字母、数字、点、下划线或短横线。"));return;}[self request:@"/user/repos" method:@"POST" body:self.isGitee?@{@"name":name,@"path":name,@"private":@YES,@"auto_init":@NO}:@{@"name":name,@"private":@YES,@"auto_init":@NO} token:token completion:^(id value,NSError *error){if(error){completion(nil,error);return;}NSDictionary *repo=[self repository:value];if(!repo||![repo[@"private"] boolValue]){completion(nil,GHError(@"仓库返回信息异常。请到对应服务检查创建结果，暂未连接本项目。"));return;}completion(repo,nil);}];}
@end
