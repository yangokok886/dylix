#import <Foundation/Foundation.h>
#import "GitHubRepositories.h"
static NSInteger scenario,requests;static BOOL payloadChecked;
@interface GHFixture : NSURLProtocol
@end
@implementation GHFixture
+ (BOOL)canInitWithRequest:(NSURLRequest *)r{return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r{return r;}
- (void)startLoading{requests++;NSInteger status=200;id body=nil;
 if(scenario==1){NSMutableArray *list=[NSMutableArray new];NSUInteger count=requests==1?100:1;for(NSUInteger i=0;i<count;i++)[list addObject:@{@"full_name":[NSString stringWithFormat:@"fixture/repo%lu",(unsigned long)i],@"clone_url":@"https://github.com/fixture/repo.git",@"private":@YES,@"permissions":@{@"push":@YES}}];body=list;}
 if(scenario==2){status=201;body=@{@"full_name":@"fixture/created",@"clone_url":@"https://github.com/fixture/created.git",@"private":@YES,@"permissions":@{@"push":@YES}};NSData *data=self.request.HTTPBody;if(!data&&self.request.HTTPBodyStream){NSInputStream *stream=self.request.HTTPBodyStream;[stream open];NSMutableData *buffer=[NSMutableData new];uint8_t bytes[1024];NSInteger n;while((n=[stream read:bytes maxLength:sizeof(bytes)])>0)[buffer appendBytes:bytes length:n];[stream close];data=buffer;}NSDictionary *p=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:@{};payloadChecked=[p[@"private"] boolValue]&&[p[@"auto_init"] isEqual:@NO]&&[p[@"name"] isEqual:@"created"]&&[self.request.HTTPMethod isEqual:@"POST"]&&[[self.request valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer fixture-only"];
 }
 if(scenario>=400){status=scenario;body=@{@"message":@"fixture server text must not appear"};}
 if(scenario==3)body=@[@{@"full_name":@"fixture/bad",@"clone_url":@"https://other.example/x.git",@"private":@YES}];
 if(scenario==6)body=@[@{@"full_name":@"fixture/bad",@"clone_url":@"https://github.com/fixture/bad.git",@"private":NSNull.null},@{@"full_name":@"fixture/port",@"clone_url":@"https://github.com:999/fixture/bad.git",@"private":@YES}];
 if(scenario==4)body=@"bad schema";
 if(scenario==5){[self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];return;}
 NSData *data=[NSJSONSerialization dataWithJSONObject:body?:@[] options:NSJSONWritingFragmentsAllowed error:nil];NSHTTPURLResponse *r=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];[self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];[self.client URLProtocol:self didLoadData:data];[self.client URLProtocolDidFinishLoading:self];}
- (void)stopLoading{}
@end
static void check(BOOL v,NSString *label){if(!v){NSLog(@"FAIL %@",label);exit(1);}printf("PASS %s\n",label.UTF8String);}
int main(){@autoreleasepool{check([TFGitHubRepositories validRepositoryName:@"my-plugin_1.0"],@"valid name");for(NSString *n in @[@"",@"..",@"a/b",@"a b",@"中文"] )check(![TFGitHubRepositories validRepositoryName:n],@"invalid name");
 TFGitHubRepositories *client=[TFGitHubRepositories new];NSURLSessionConfiguration *cfg=NSURLSessionConfiguration.ephemeralSessionConfiguration;cfg.protocolClasses=@[GHFixture.class];client.session=[NSURLSession sessionWithConfiguration:cfg];
 for(NSNumber *test in @[@1,@2,@401,@403,@422,@429,@3,@4,@5,@6]){scenario=test.integerValue;requests=0;__block BOOL done=NO;__block id result=nil;__block NSError *failure=nil;void (^finish)(id,NSError *)=^(id value,NSError *error){result=value;failure=error;done=YES;};if(scenario==2)[client createPrivate:@"created" token:@"fixture-only" completion:finish];else [client listWithToken:@"fixture-only" completion:finish];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];while(!done&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];check(done,@"request completes");if(scenario==1)check([result count]==101&&requests==2,@"pagination");else if(scenario==2)check(payloadChecked&&result&&!failure,@"private empty creation body and credential header");else if(scenario==3||scenario==6)check([result count]==0&&!failure,@"external clone URL rejected");else {check(failure!=nil,@"actionable API/network error");check(![failure.localizedDescription containsString:@"fixture server text"],@"raw response excluded");}}
 puts("GitHub repository API fixtures passed");}}
