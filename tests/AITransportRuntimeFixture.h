#import <Foundation/Foundation.h>
// Register/unregister on main while no other AI request is active. Entirely synthetic.
// Use connection {protocol:chat,baseURL:https://ai-runtime-fixture.invalid/v1,model:fixture}.
// The first round asks read_file; a following tool result receives final text.
@interface TFAIRuntimeFixtureProtocol : NSURLProtocol
@end
@implementation TFAIRuntimeFixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request{return [request.URL.host isEqual:@"ai-runtime-fixture.invalid"];}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request{return request;}
- (void)startLoading{
 NSData *body=self.request.HTTPBody;if(!body&&self.request.HTTPBodyStream){NSInputStream *input=self.request.HTTPBodyStream;[input open];NSMutableData *buffer=[NSMutableData new];uint8_t bytes[4096];NSInteger n;while((n=[input read:bytes maxLength:sizeof(bytes)])>0)[buffer appendBytes:bytes length:n];[input close];body=buffer;}
 NSDictionary *request=body?[NSJSONSerialization JSONObjectWithData:body options:0 error:nil]:@{};BOOL hasResult=NO;for(NSDictionary *m in request[@"messages"])if([m[@"role"] isEqual:@"tool"])hasResult=YES;
 NSDictionary *delta=hasResult?@{@"content":@"已读取测试文件；这是离线协议夹具响应。"}:@{@"tool_calls":@[@{@"index":@0,@"id":@"fixture-read-1",@"type":@"function",@"function":@{@"name":@"read_file",@"arguments":@"{\"path\":\"Tweak.xm\"}"}}]};
 NSDictionary *frame=@{@"choices":@[@{@"index":@0,@"delta":delta,@"finish_reason":hasResult?@"stop":@"tool_calls"}]};NSData *json=[NSJSONSerialization dataWithJSONObject:frame options:0 error:nil];NSMutableData *data=[NSMutableData new];[data appendData:[@"data: " dataUsingEncoding:NSUTF8StringEncoding]];[data appendData:json];[data appendData:[@"\n\ndata: [DONE]\n\n" dataUsingEncoding:NSUTF8StringEncoding]];
 NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"text/event-stream"}];[self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];for(NSUInteger i=0;i<data.length;i+=7)[self.client URLProtocol:self didLoadData:[data subdataWithRange:NSMakeRange(i,MIN((NSUInteger)7,data.length-i))]];[self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading{}
@end
