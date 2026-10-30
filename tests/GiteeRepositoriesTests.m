#import <Foundation/Foundation.h>
#import "GitHubRepositories.h"
static NSInteger scenario,requests,checks;
static BOOL wireOK;
static NSString *Token=@"fixture+token&=only";
static NSDictionary *Repo(NSString *url){return @{@"full_name":@"fixture/repo",@"html_url":url,@"private":@YES,@"permission":@{@"pull":@YES,@"push":@YES}};}
static void Check(BOOL ok,NSString *label){checks++;if(!ok){NSLog(@"FAIL %@",label);exit(1);}NSLog(@"PASS %@",label);}
@interface GiteeFixture : NSURLProtocol
@end
@implementation GiteeFixture
+ (BOOL)canInitWithRequest:(NSURLRequest *)r{return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r{return r;}
- (void)stopLoading{}
- (void)startLoading{requests++;id body=nil;NSInteger status=200;NSURLComponents *url=[NSURLComponents componentsWithURL:self.request.URL resolvingAgainstBaseURL:NO];NSMutableDictionary *query=[NSMutableDictionary new];for(NSURLQueryItem *item in url.queryItems)query[item.name]=item.value?:@"";
 wireOK&=[url.host isEqual:@"gitee.com"]&&[url.scheme isEqual:@"https"]&&[url.path isEqual:@"/api/v5/user/repos"]&&![self.request valueForHTTPHeaderField:@"Authorization"]&&![self.request valueForHTTPHeaderField:@"X-GitHub-Api-Version"];
 if(scenario==2||scenario==7){NSData *data=self.request.HTTPBody;if(!data&&self.request.HTTPBodyStream){NSInputStream *stream=self.request.HTTPBodyStream;[stream open];NSMutableData *buffer=[NSMutableData new];uint8_t bytes[1024];NSInteger n;while((n=[stream read:bytes maxLength:sizeof(bytes)])>0)[buffer appendBytes:bytes length:n];[stream close];data=buffer;}NSDictionary *p=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:@{};
 wireOK&=[self.request.HTTPMethod isEqual:@"POST"]&&[p[@"access_token"] isEqual:Token]&&[p[@"name"] isEqual:@"created"]&&[p[@"path"] isEqual:@"created"]&&[p[@"private"] isEqual:@YES]&&[p[@"auto_init"] isEqual:@NO]&&!query[@"access_token"];
 status=201;NSMutableDictionary *repo=[Repo(@"https://gitee.com/fixture/created") mutableCopy];if(scenario==7)repo[@"private"]=@NO;body=repo;
 }else{wireOK&=[query[@"access_token"] isEqual:Token]&&[query[@"per_page"] isEqual:@"100"]&&[query[@"page"] integerValue]==requests;
 if(scenario==1){NSMutableArray *list=[NSMutableArray new];for(int i=0;i<(requests==1?100:1);i++)[list addObject:Repo(@"https://gitee.com/fixture/repo")];body=list;}
 if(scenario==3){NSMutableArray *list=[NSMutableArray new];for(NSString *url in @[@"https://github.com/fixture/repo",@"https://evil.example/fixture/repo",@"http://gitee.com/fixture/repo",@"https://gitee.com:443/fixture/repo",@"https://user@gitee.com/fixture/repo",@"https://gitee.com/fixture/repo?access_token=secret",@"https://gitee.com/fixture/repo#part",@"https://gitee.com/fixture/nested/repo",@"https://gitee.com/fixture/%2E%2E"])[list addObject:Repo(url)];[list addObject:@{@"full_name":@"broken",@"html_url":@"https://gitee.com/fixture/repo",@"private":NSNull.null}];body=list;}
 if(scenario==4)body=@"bad schema";
 if(scenario==5){[self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:@{NSLocalizedDescriptionKey:Token}]];return;}
 if(scenario==6)body=@[Repo(@"https://gitee.com/fixture/repo.git")];
 if(scenario>=400){status=scenario;body=@{@"message":Token};}
 }
 NSData *data=[NSJSONSerialization dataWithJSONObject:body?:@[] options:NSJSONWritingFragmentsAllowed error:nil];NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];[self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];[self.client URLProtocol:self didLoadData:data];[self.client URLProtocolDidFinishLoading:self];}
@end
@interface NSObject (RedirectFixture)
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)q completionHandler:(void (^)(NSURLRequest *))done;
@end
int main(){@autoreleasepool{
 Check([[TFGitHubRepositories new].origin isEqual:@"https://github.com"],@"existing default stays GitHub");Check([[TFGitHubRepositories alloc]initWithOrigin:@"https://evil.example"]==nil,@"API origin whitelist");TFGitHubRepositories *client=[[TFGitHubRepositories alloc]initWithOrigin:@"https://gitee.com"];Check([client.serviceName isEqual:@"Gitee"],@"provider identified");
 NSURLSessionConfiguration *cfg=NSURLSessionConfiguration.ephemeralSessionConfiguration;cfg.protocolClasses=@[GiteeFixture.class];client.session=[NSURLSession sessionWithConfiguration:cfg];
 for(NSNumber *test in @[@1,@2,@3,@4,@5,@6,@7,@401,@403,@404,@422,@429]){scenario=test.integerValue;requests=0;wireOK=YES;__block BOOL done=NO;__block id result=nil;__block NSError *failure=nil;void (^finish)(id,NSError *)=^(id value,NSError *error){result=value;failure=error;done=YES;};if(scenario==2||scenario==7)[client createPrivate:@"created" token:Token completion:finish];else[client listWithToken:Token completion:finish];NSDate *until=[NSDate dateWithTimeIntervalSinceNow:5];while(!done&&until.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(done&&wireOK,@"Gitee endpoint, encoded auth and request fields");if(scenario==1)Check([result count]==101&&requests==2&&[result[0][@"url"] isEqual:@"https://gitee.com/fixture/repo.git"]&&[result[0][@"push"] boolValue],@"pagination plus html_url and singular permission normalization");else if(scenario==2)Check(result&&!failure&&[result[@"private"] boolValue],@"create empty private repository");else if(scenario==3)Check([result count]==0&&!failure,@"malformed and foreign repository URLs rejected");else if(scenario==6)Check([result[0][@"url"] isEqual:@"https://gitee.com/fixture/repo.git"],@"git suffix not duplicated");else{Check(failure!=nil,@"failure is actionable");Check(![failure.localizedDescription containsString:Token]&&![failure.localizedDescription containsString:@"GitHub"],@"error excludes secret, raw server body and wrong provider name");}}
 __block BOOL noToken=NO;NSInteger prior=requests;[client listWithToken:@"" completion:^(NSArray *v,NSError *e){noToken=e!=nil;}];Check(noToken&&requests==prior,@"missing token makes no request");__block BOOL invalid=NO;[client createPrivate:@"../bad" token:Token completion:^(NSDictionary *v,NSError *e){invalid=e!=nil;}];Check(invalid&&requests==prior,@"invalid creation makes no request");
 id delegate=[NSClassFromString(@"TFGitHubRedirectPolicy") new];__block BOOL rejected=NO;[delegate URLSession:nil task:nil willPerformHTTPRedirection:nil newRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://other.example"]] completionHandler:^(NSURLRequest *r){rejected=r==nil;}];Check(rejected,@"credential-bearing API redirect refused");
 [client.session invalidateAndCancel];NSLog(@"PASS %ld Gitee API checks",(long)checks);
}return 0;}
