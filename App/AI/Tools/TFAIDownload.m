#import "TFAIDownload.h"
#import "../Permissions/TFAIPolicy.h"
@interface TFAIDownload ()
@property NSURLSession *session;
@property NSURLSessionDataTask *task;
@property NSMutableData *buffer;
@property NSError *failure;
@property dispatch_semaphore_t signal;
@end
@implementation TFAIDownload
- (NSData *)fetch:(NSURL *)url error:(NSError **)error {
 if(self.cancelled){if(error)*error=TFAIToolError(@"下载已取消");return nil;}
 self.signal=dispatch_semaphore_create(0);self.buffer=[NSMutableData new];NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
#if defined(TFAI_TOOL_TEST)
 Class fixture=NSClassFromString(@"FixtureProtocol");if(fixture)config.protocolClasses=@[fixture];
#endif
 config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=45;config.HTTPCookieStorage=nil;config.URLCredentialStorage=nil;config.URLCache=nil;self.session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];self.task=[self.session dataTaskWithURL:url];[self.task resume];
 if(dispatch_semaphore_wait(self.signal,dispatch_time(DISPATCH_TIME_NOW,46*NSEC_PER_SEC))){self.failure=TFAIToolError(@"下载超时，请检查网络后重新预览");[self.task cancel];}
 [self.session invalidateAndCancel];self.session=nil;self.task=nil;
 if(self.cancelled&&!self.failure)self.failure=TFAIToolError(@"下载已取消");if(error)*error=self.failure;return self.failure?nil:[self.buffer copy];
}
- (void)cancel{self.cancelled=YES;[self.task cancel];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler{self.failure=TFAIToolError(@"下载地址发生重定向，请使用最终 HTTPS 地址重新预览批准");completionHandler(nil);}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
 NSInteger status=[r isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)r statusCode]:0;
 if(status<200||status>=300||r.expectedContentLength>20*1024*1024){self.failure=TFAIToolError(status<200||status>=300?[NSString stringWithFormat:@"下载 HTTP %ld",(long)status]:@"下载超过 20 MB 上限");completion(NSURLSessionResponseCancel);return;}completion(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)data{if(self.cancelled||self.buffer.length+data.length>20*1024*1024){self.failure=TFAIToolError(self.cancelled?@"下载已取消":@"下载超过 20 MB 上限");[t cancel];return;}[self.buffer appendData:data];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)error{if(error&&!self.failure)self.failure=TFAIToolError(@"下载连接中断或超时，目标文件未写入");dispatch_semaphore_signal(self.signal);}
@end
