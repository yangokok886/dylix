#import "TFShareLauncher.h"
@interface TFShareLauncher()
@property NSUInteger generation;
@property NSString *state;
@property NSMutableArray *attempts;
@property BOOL fallbackStarted;
@property NSURL *url;
@property NSString *reason;
@end
@implementation TFShareLauncher
- (instancetype)init{if((self=[super init])){_state=@"idle";_attempts=[NSMutableArray new];_timeout=3;}return self;}
- (NSDictionary *)snapshot{return @{@"state":self.state?:@"idle",@"attempts":[self.attempts copy]?:@[],@"reason":self.reason?:@""};}
- (void)notify{if(self.updated)self.updated(self.snapshot);}
- (BOOL)pending:(NSUInteger)token{return self.generation==token&&[self.state isEqual:@"opening"];}
- (void)finish:(BOOL)success token:(NSUInteger)token reason:(NSString *)reason{if(![self pending:token])return;self.state=success?@"opened":@"failed";self.reason=reason;[self notify];}
- (void)call:(TFShareOpenAction)action name:(NSString *)name token:(NSUInteger)token fallback:(BOOL)isFallback{
 [self.attempts addObject:name];[self notify];
 void(^done)(BOOL)=^(BOOL success){void(^deliver)(void)=^{if(![self pending:token])return;if(success)[self finish:YES token:token reason:@"systemAcceptedURL"];else if(isFallback)[self finish:NO token:token reason:@"bothOpenMethodsDeclined"];else[self tryFallback:token];};if(NSThread.isMainThread)deliver();else dispatch_async(dispatch_get_main_queue(),deliver);};
 if(action)action(self.url,done);else done(NO);
}
- (void)tryFallback:(NSUInteger)token{if(![self pending:token]||self.fallbackStarted)return;self.fallbackStarted=YES;[self call:self.fallback name:@"extensionContext" token:token fallback:YES];}
- (BOOL)openIncomingJob:(NSString *)job{
 NSAssert(NSThread.isMainThread,@"Launcher runs on main thread");
 if([self.state isEqual:@"opening"]||[self.state isEqual:@"opened"]||![[NSUUID alloc]initWithUUIDString:job])return NO;
 self.generation++;NSUInteger token=self.generation;self.state=@"opening";self.reason=@"";self.fallbackStarted=NO;self.attempts=[NSMutableArray new];
 NSURLComponents *parts=[NSURLComponents new];parts.scheme=@"tweakforge";parts.host=@"incoming";parts.queryItems=@[[NSURLQueryItem queryItemWithName:@"job" value:job]];self.url=parts.URL;
 NSTimeInterval timeout=MAX(.01,MIN(10,self.timeout));
 [self call:self.primary name:@"modernResponder" token:token fallback:NO];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(MIN(.7,timeout/2)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self tryFallback:token];});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(timeout*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self finish:NO token:token reason:@"openCallbackTimeout"];});return YES;
}
@end
