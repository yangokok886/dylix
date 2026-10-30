// Simulator-only end-to-end protocol fixture. No real network, key, or original project writes.
#import "../App/AI/AIContracts.h"
#import "../tests/AITransportKeychain.inc"
#import "../tests/AIUIRegression.inc"
@interface TFAIFixtureProtocol : NSURLProtocol
@end
static NSMutableArray *TFAIFixtureRequests;
static NSString *TFAIFixtureMode;
@implementation TFAIFixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request{return [request.URL.host isEqual:@"ai-fixture.example.invalid"];}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request{return request;}
- (void)stopLoading{}
- (void)startLoading {
 NSData *body=self.request.HTTPBody;
 if(!body&&self.request.HTTPBodyStream){NSInputStream *stream=self.request.HTTPBodyStream;[stream open];NSMutableData *data=[NSMutableData new];uint8_t b[4096];NSInteger n;while((n=[stream read:b maxLength:sizeof(b)])>0)[data appendBytes:b length:n];[stream close];body=data;}
 NSDictionary *request=[NSJSONSerialization JSONObjectWithData:body?:NSData.data options:0 error:nil];[TFAIFixtureRequests addObject:request?:@{}];
 NSArray *messages=request[@"messages"];NSUInteger callCount=0;NSString *proposal=nil;
 for(NSDictionary *m in messages){if([m[@"role"] isEqual:@"tool"]){callCount++;NSDictionary *result=[NSJSONSerialization JSONObjectWithData:[m[@"content"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];if(result[@"proposal_id"])proposal=result[@"proposal_id"];}}
 NSString *name=nil;NSDictionary *args=@{};NSString *text=nil;
 if([TFAIFixtureMode isEqual:@"repair"]){switch(callCount){case 0:name=@"build_project";break;case 1:name=@"read_file";args=@{@"path":@"Test.c"};break;case 2:name=@"propose_patch";args=@{@"edits":@[@{@"path":@"Test.c",@"before":@"return broken_value;",@"after":@"return 42;"}]};break;case 3:name=@"apply_approved_patch";args=@{@"proposal_id":proposal?:@"missing"};break;case 4:name=@"build_project";break;default:text=@"已完成本机编译验证；宿主注入仍需真机测试。";}}
 else if([TFAIFixtureMode isEqual:@"deny"]){if(callCount==0){name=@"create_file";args=@{@"path":@"denied.c",@"content":@"int denied;"};}else text=@"用户已拒绝，文件未创建。";}
 else if([TFAIFixtureMode isEqual:@"stop"]){name=@"create_file";args=@{@"path":@"stopped.c",@"content":@"int stopped;"};}
 else text=@"fixture answer";
 NSDictionary *delta;
 if(name){NSString *arguments=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:args options:0 error:nil] encoding:NSUTF8StringEncoding];delta=@{@"tool_calls":@[@{@"index":@0,@"id":[NSString stringWithFormat:@"%@-%lu",TFAIFixtureMode,(unsigned long)callCount],@"type":@"function",@"function":@{@"name":name,@"arguments":arguments}}]};}else delta=@{@"content":text?:@""};
 NSDictionary *chunk=@{@"choices":@[@{@"index":@0,@"delta":delta,@"finish_reason":NSNull.null}]};
 NSString *json=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:chunk options:0 error:nil] encoding:NSUTF8StringEncoding];NSString *payload=[NSString stringWithFormat:@"data: %@\n\ndata: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"%@\"}]}\n\ndata: [DONE]\n\n",json,name?@"tool_calls":@"stop"];
 NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"text/event-stream"}];[self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
 NSData *data=[payload dataUsingEncoding:NSUTF8StringEncoding];for(NSUInteger offset=0;offset<data.length;offset+=7)[self.client URLProtocol:self didLoadData:[data subdataWithRange:NSMakeRange(offset,MIN(7,data.length-offset))]];[self.client URLProtocolDidFinishLoading:self];
}
@end
@interface TFAIIntegrationFixture : NSObject
@property StudioEditor *editor;
@property id<TFAIRuntime> runtime;
@property NSMutableArray *checks,*builds;
@property NSDictionary *savedPreferences;
@property NSString *connectionID,*projectID,*sessionID;
@property NSUInteger approvals;
@end
static TFAIIntegrationFixture *TFAIActiveFixture;
@implementation TFAIIntegrationFixture
- (void)check:(BOOL)ok name:(NSString *)name{[self.checks addObject:@{@"name":name,@"ok":@(ok)}];}
- (void)finish {
 [self.runtime stop];[NSURLProtocol unregisterClass:TFAIFixtureProtocol.class];[TFAIConnections remove:self.connectionID];
 for(NSString *key in self.savedPreferences){id v=self.savedPreferences[key];if(v==NSNull.null)[NSUserDefaults.standardUserDefaults removeObjectForKey:key];else[NSUserDefaults.standardUserDefaults setObject:v forKey:key];}
 NSUInteger passed=0;for(NSDictionary *r in self.checks)if([r[@"ok"] boolValue])passed++;
 TFAIRunUIRegressionAsync(^(NSDictionary *ui){
 JSONWrite(@{@"checks":self.checks,@"passed":@(passed),@"total":@(self.checks.count),@"builds":self.builds,@"requests":@(TFAIFixtureRequests.count),@"keychain":TFAITransportRunKeychainRegression(),@"ui":ui},[Docs() stringByAppendingPathComponent:@"ai-integration-test.json"],nil);
 self.editor.navigationItem.prompt=[NSString stringWithFormat:@"AI regression %lu/%lu",(unsigned long)passed,(unsigned long)self.checks.count];TFAIActiveFixture=nil;
 });
}
- (void)runPhase:(NSString *)mode {
 TFAIFixtureMode=mode;TFAIFixtureRequests=[NSMutableArray new];self.sessionID=NSUUID.UUID.UUIDString;
 [self.runtime activateSession:self.sessionID];__weak typeof(self) weak=self;
 self.runtime.approval=^(NSDictionary *plan,void (^decision)(BOOL,NSArray *)){weak.approvals++;if([mode isEqual:@"stop"]){[weak.runtime stop];decision(YES,nil);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[weak check:![NSFileManager.defaultManager fileExistsAtPath:[weak.editor.root stringByAppendingPathComponent:@"stopped.c"]] name:@"stale approval after stop has no effects"];[weak finish];});return;}decision(![mode isEqual:@"deny"],nil);};
 self.runtime.event=^(NSDictionary *event){TFAIIntegrationFixture *s=weak;if(!s)return;if([event[@"type"] isEqual:@"tool_result"]&&[event[@"name"] isEqual:@"build_project"])[s.builds addObject:event[@"result"]];if([event[@"type"] isEqual:@"error"])[s check:NO name:[@"unexpected runtime error: " stringByAppendingString:event[@"message"]?:@""]];if(![event[@"type"] isEqual:@"done"])return;
  if([mode isEqual:@"repair"]){[s check:s.builds.count==2&&![[s.builds.firstObject objectForKey:@"success"] boolValue]&&[[s.builds.lastObject objectForKey:@"success"] boolValue] name:@"actual embedded build fails then succeeds after approved patch"];NSString *text=[NSString stringWithContentsOfFile:[s.editor.root stringByAppendingPathComponent:@"Test.c"] encoding:NSUTF8StringEncoding error:nil];[s check:[text containsString:@"return 42;"] name:@"approved patch changed project copy"];[s check:s.approvals==3 name:@"two builds and patch separately approved"];[s check:[event[@"messages"] count]>=11 name:@"tool conversation retained for continuation"];[s.runtime undo:^(NSDictionary *r,NSError *e){NSString *undo=[NSString stringWithContentsOfFile:[s.editor.root stringByAppendingPathComponent:@"Test.c"] encoding:NSUTF8StringEncoding error:nil];[s check:!e&&[undo containsString:@"return broken_value;"] name:@"undo restores pre-patch source"];dispatch_async(dispatch_get_main_queue(),^{[s runPhase:@"deny"];});}];}
  else if([mode isEqual:@"deny"]){[s check:![NSFileManager.defaultManager fileExistsAtPath:[s.editor.root stringByAppendingPathComponent:@"denied.c"]] name:@"denied operation no side effects"];dispatch_async(dispatch_get_main_queue(),^{[s runPhase:@"stop"];});}
 };
 [self.runtime send:@[@{@"role":@"user",@"content":@"Fixture task; inspect and fix compile error with explicit local approval."}] session:self.sessionID];
}
- (void)start {
 self.checks=[NSMutableArray new];self.builds=[NSMutableArray new];self.projectID=TFAIProjectID(self.editor.root);self.connectionID=NSUUID.UUID.UUIDString;
 NSMutableDictionary *prefs=[NSMutableDictionary new];for(NSString *key in @[@"TFAI.Connections.v1",@"TFAI.DefaultConnection.v1",@"TFAI.ProjectConnections.v1"])prefs[key]=[NSUserDefaults.standardUserDefaults objectForKey:key]?:NSNull.null;self.savedPreferences=prefs;
 NSError *error=nil;[TFAIConnections save:@{@"id":self.connectionID,@"name":@"Fixture",@"baseURL":@"https://ai-fixture.example.invalid/v1",@"protocol":@"chat",@"model":@"fixture",@"models":@[]} secret:nil error:&error];[TFAIConnections setConnection:self.connectionID project:self.projectID];[self check:!error name:@"fixture connection configured without real credentials"];
 [NSURLProtocol registerClass:TFAIFixtureProtocol.class];__weak typeof(self) weak=self;
 self.runtime=TFAICreateRuntime(self.editor.root,self.projectID,^(NSString *name,NSDictionary *args,TFAIResult completion){[weak.editor aiTool:name arguments:args completion:completion];});[self runPhase:@"repair"];
}
@end
UIViewController *TFAIIntegrationRegression(void){
 NSString *root=[Projects() stringByAppendingPathComponent:[@"AI-CopyFixture-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 // Synthetic copy: full tool/compiler integration needs no user project mutation.
 [@"int fixture(void) { return broken_value; }\n" writeToFile:[root stringByAppendingPathComponent:@"Test.c"] atomically:YES encoding:NSUTF8StringEncoding error:nil];JSONWrite(@{@"name":@"AI 编译闭环测试副本",@"productName":@"AIFixture",@"sources":@[@"Test.c"],@"frameworks":@[],@"package":@NO,@"exportDylib":@YES},[root stringByAppendingPathComponent:@"MobileCompiler.json"],nil);
 StudioEditor *editor=[StudioEditor new];editor.root=root;TFAIActiveFixture=[TFAIIntegrationFixture new];TFAIActiveFixture.editor=editor;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{[TFAIActiveFixture start];});return editor;
}
