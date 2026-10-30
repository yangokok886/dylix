#import <Foundation/Foundation.h>
NSString *UIApplicationDidEnterBackgroundNotification=@"FixtureBackground";
#import "../App/AI/AIContracts.h"
#import "../App/AI/AIV2Contracts.h"
#import "../App/AI/Tools/TFAIWebTools.h"
#import "../App/AI/Core/AIPolicy.h"
static NSUInteger requests,executions;static NSString *mode;static NSMutableArray *events;static NSDictionary *terminal;
static void Check(BOOL yes,NSString *name){if(!yes){NSLog(@"FAIL %@",name);exit(1);}NSLog(@"PASS %@",name);}
@implementation TFAITransport
- (void)cancel{}
- (void)send:(NSArray *)messages connection:(NSDictionary *)connection tools:(NSArray *)tools event:(TFAIEvent)event{requests++;if([mode isEqual:@"empty"]){event(@{@"type":@"done"});return;}if([mode isEqual:@"wait"])return;Check(tools.count>0,@"tools remain available beyond old count limits");
 if(requests>40){for(NSDictionary *m in messages)for(NSDictionary *c in m[@"tool_calls"]){NSUInteger matched=0;for(NSDictionary *r in messages)if([r[@"tool_call_id"] isEqual:c[@"id"]])matched++;Check(matched==1,@"each tool has exactly one result");}event(@{@"type":@"text",@"text":@"分析完成。"});event(@{@"type":@"done"});return;}
 NSUInteger count=[mode isEqual:@"batch"]?30:1;for(NSUInteger i=0;i<count;i++)event(@{@"type":@"tool_call",@"id":[NSString stringWithFormat:@"call-%lu-%lu",requests,i],@"name":@"read_file",@"arguments":@{@"path":@"Fixture.m"}});event(@{@"type":@"done"});}
@end
@implementation TFAIToolbox
+ (NSArray *)schemas{return @[@{@"name":@"read_file",@"parameters":@{}}];}
- (instancetype)initWithRoot:(NSString *)r projectID:(NSString *)p sessionID:(NSString *)s{return [super init];}
- (void)cancel{}
- (void)setBridge:(void(^)(NSString *,NSDictionary *,TFAIResult))b{}
- (void)prepare:(NSDictionary *)request completion:(TFAIResult)done{done(@{@"request":request,@"readOnly":@YES},nil);}
- (void)setApprovalContext:(NSString *)context{}
- (void)execute:(NSDictionary *)plan approved:(BOOL)approved completion:(TFAIResult)done{executions++;done(@{@"text":@"fixture"},nil);}
- (void)selectEdits:(NSArray *)a plan:(NSDictionary *)p completion:(TFAIResult)c{c(p,nil);}
- (void)undo:(TFAIResult)c{c(@{},nil);}
@end
@implementation TFAIConnections
+ (NSDictionary *)effectiveForProject:(NSString *)p{return @{@"model":@"fixture"};}
@end
@implementation TFAIWebTools
+ (BOOL)enabled{return NO;}
+ (NSArray *)schemas{return @[];}
- (void)cancel{}
@end
@implementation TFAIRuntimePolicy
- (instancetype)initWithRoot:(NSString *)r projectID:(NSString *)p sessionID:(NSString *)s{return [super init];}
- (NSTimeInterval)expiresAt{return NSDate.date.timeIntervalSince1970+1800;}
- (NSString *)preset{return @"assisted";}
- (void)revoke{}
- (NSDictionary *)decisionForPlan:(NSDictionary *)p{return @{@"decision":@"allowed",@"readOnly":@YES};}
@end
NSArray *TFAIMessageMetadata(NSArray *a,NSDictionary *b){return a;}
BOOL TFAIContainsSecret(NSString *s){return NO;}
NSSet *TFAIBinarySelectedIDs(NSDictionary *r){return [NSSet set];}
NSArray *TFAIBinarySchemas(void){return @[];}
NSDictionary *TFAIBinaryExecute(NSString *a,NSDictionary *b,NSError **e){return @{};}
NSDictionary *TFAIClassDumpExecute(NSString *a,NSProgress *b,void(^p)(double,NSString *),NSError **e){return @{};}
NSDictionary *TFAIClassDumpRead(NSString *a,NSDictionary *b,NSError **e){return @{};}
NSDictionary *TFAIReadDirectoryReference(NSDictionary *a,NSDictionary *b,NSError **e){return @{@"valid":@YES};}
NSDictionary *TFAIReadAttachmentReferences(NSDictionary *a,NSDictionary *b,NSError **e){return @{};}
#import "../App/GitPreferences.h"
@implementation TMCGitLease
+ (instancetype)tryWrite{return [self new];}
@end
static void (^backgroundExpired)(NSString *);
void TFAIBackgroundRegister(void){}
NSString *TFAIBackgroundBegin(void (^expired)(NSString *)){backgroundExpired=[expired copy];return @"lease";}
void TFAIBackgroundUpdate(NSString *token,NSDictionary *event){}
void TFAIBackgroundEnd(NSString *token,BOOL success){backgroundExpired=nil;}
NSString *TFAIBackgroundStatus(void){return @"系统持续后台任务已启用";}
#import "../App/AI/Core/AIRuntime.m"
int main(){@autoreleasepool{for(NSString *m in @[@"rounds",@"batch"]){mode=m;requests=executions=0;terminal=nil;events=[NSMutableArray new];id<TFAIRuntime> r=TFAICreateRuntime(@"/tmp/fixture",@"fixture",nil);r.event=^(NSDictionary *e){[events addObject:e];if([e[@"type"] isEqual:@"done"])terminal=e;};[r activateSession:@"fixture"];[r send:@[@{@"role":@"user",@"content":@"inspect"}] session:@"fixture"];Check([terminal[@"state"] isEqual:@"completed"],@"task completes naturally");Check(requests==41&&executions==([m isEqual:@"batch"]?1200:40),@"all 40 rounds and tools executed");Check([terminal[@"messages"] lastObject]&&[[terminal[@"messages"] lastObject][@"content"] isEqual:@"分析完成。"],@"natural final answer retained");}for(NSString *end in @[@"empty",@"stop",@"background"]){mode=[end isEqual:@"empty"]?@"empty":@"wait";terminal=nil;id<TFAIRuntime> r=TFAICreateRuntime(@"/tmp/fixture",@"fixture",^(NSString *n,NSDictionary *a,TFAIResult c){});r.event=^(NSDictionary *e){if([e[@"type"] isEqual:@"done"])terminal=e;};[r activateSession:@"fixture"];[r send:@[@{@"role":@"user",@"content":@"inspect"}] session:@"fixture"];if([end isEqual:@"stop"])[r stop];else if([end isEqual:@"background"]){[NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];Check(!terminal,@"entering background does not stop task");void (^expire)(NSString *)=[backgroundExpired copy];expire(@"系统后台执行结束");}Check([terminal[@"state"] isEqual:[end isEqual:@"stop"]?@"stopped":@"interrupted"],[@"terminal state: " stringByAppendingString:end]);Check([terminal[@"message"] length]>0,[@"terminal reason: " stringByAppendingString:end]);}NSLog(@"Runtime unlimited-loop tests passed");}return 0;}
