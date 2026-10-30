// Project-full permissions: local fixtures only; no real services or original project writes.
#import "../App/AI/Core/AIPolicy.h"
#import "../App/AI/AIContracts.h"
static void TFAIPermissionV4PolicyRegression(void(^check)(BOOL,NSString *)) {
 NSFileManager *fm=NSFileManager.defaultManager;NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"permission-v4-" stringByAppendingString:NSUUID.UUID.UUIDString]];[fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];[@"int a=1;" writeToFile:[root stringByAppendingPathComponent:@"A.m"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 TFAIRuntimePolicy *policy=[[TFAIRuntimePolicy alloc]initWithRoot:root projectID:@"p" sessionID:@"s"];
 NSMutableDictionary *(^plan)(NSString *,NSDictionary *)=^NSMutableDictionary *(NSString *name,NSDictionary *arguments){return [@{@"id":NSUUID.UUID.UUIDString,@"project":@"p",@"session":@"s",@"expires":@(NSDate.date.timeIntervalSince1970+600),@"request":@{@"id":NSUUID.UUID.UUIDString,@"name":name,@"arguments":arguments?:@{}}} mutableCopy];};
 NSDictionary *(^edit)(NSString *,NSString *)=^NSDictionary *(NSString *path,NSString *kind){return @{@"path":path,@"kind":kind,@"before":@"int a=1;",@"after":@"int a=2;"};};
 NSMutableDictionary *patch=plan(@"apply_approved_patch",@{});patch[@"edits"]=@[edit(@"A.m",@"source")];NSMutableDictionary *forged=[patch mutableCopy];forged[@"preset"]=@"full";forged[@"approved"]=@YES;
 check([[policy decisionForPlan:forged][@"decision"] isEqual:@"needsApproval"],@"plan cannot grant itself full-project permission");
 for(NSString *preset in @[@"full",@"full_push",@"full_download",@"full_network"]){check([policy configurePreset:preset paths:@[] session:@"s" error:nil],[@"configure explicit " stringByAppendingString:preset]);
 for(NSString *tool in @[@"build_project",@"cancel_build",@"git_save_version"]){check([[policy decisionForPlan:plan(tool,@{})][@"decision"] isEqual:@"allowed"],[NSString stringWithFormat:@"%@ permits prepared local %@",preset,tool]);}
 BOOL push=[@[@"full_push",@"full_network"] containsObject:preset],download=[@[@"full_download",@"full_network"] containsObject:preset];
 check([[policy decisionForPlan:plan(@"git_upload",@{})][@"decision"] isEqual:push?@"allowed":@"needsApproval"],[preset stringByAppendingString:@": independent push grant"]);
 for(NSString *tool in @[@"download_file",@"git_download_updates",@"extract_archive"]){check([[policy decisionForPlan:plan(tool,@{})][@"decision"] isEqual:download?@"allowed":@"needsApproval"],[NSString stringWithFormat:@"%@: independent download grant for %@",preset,tool]);}
 }
 [policy configurePreset:@"full" paths:@[] session:@"s" error:nil];check([[policy decisionForPlan:patch][@"decision"] isEqual:@"allowed"],@"full permits exact prepared source patch");
 NSMutableDictionary *config=[patch mutableCopy];config[@"edits"]=@[edit(@"MobileCompiler.json",@"configuration")];check([[policy decisionForPlan:config][@"decision"] isEqual:@"allowed"],@"full permits prepared project config patch");
 for(NSString *tool in @[@"create_file",@"request_delete"]){NSMutableDictionary *change=plan(tool,@{@"path":@"A.m"});change[@"edits"]=@[edit(@"A.m",[tool isEqual:@"create_file"]?@"create":@"delete")];check([[policy decisionForPlan:change][@"decision"] isEqual:@"allowed"],[tool stringByAppendingString:@" respects explicit local full grant"]);}
 for(NSString *path in @[@"../other.m",@"/etc/hosts",@".git/HEAD",@".env",@"credentials.json",@".studio-ai-identity.json",@"build/A.m"]){NSMutableDictionary *outside=[patch mutableCopy];outside[@"edits"]=@[edit(path,@"source")];check([[policy decisionForPlan:outside][@"decision"] isEqual:@"denied"],[path stringByAppendingString:@" denied even with full project grant"]);}
 [fm createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"Link.m"] withDestinationPath:@"/etc/hosts" error:nil];NSMutableDictionary *linked=[patch mutableCopy];linked[@"edits"]=@[edit(@"Link.m",@"source")];check([[policy decisionForPlan:linked][@"decision"] isEqual:@"denied"],@"full rejects symlink targets");
 for(NSString *field in @[@"project",@"session"]){NSMutableDictionary *other=[patch mutableCopy];other[field]=@"other";check([[policy decisionForPlan:other][@"decision"] isEqual:@"denied"],[field stringByAppendingString:@" mismatch denies full grant"]);}
 NSMutableDictionary *expired=[patch mutableCopy];expired[@"expires"]=@0;check([[policy decisionForPlan:expired][@"decision"] isEqual:@"denied"],@"expired plan denied under full");
 check([[policy decisionForPlan:plan(@"shell",@{})][@"decision"] isEqual:@"denied"],@"full does not introduce arbitrary shell tools");
 [policy setValue:@0 forKey:@"expiresAt"];check([[policy decisionForPlan:patch][@"decision"] isEqual:@"denied"],@"expired full session denied");[policy configurePreset:@"full" paths:@[] session:@"s" error:nil];[policy revoke];check([[policy decisionForPlan:patch][@"decision"] isEqual:@"denied"],@"revoked full session denied");
 [policy configurePreset:@"full" paths:@[] session:@"s" error:nil];[policy configurePreset:@"assisted" paths:@[] session:@"s" error:nil];check([[policy decisionForPlan:patch][@"decision"] isEqual:@"needsApproval"],@"downgrading full immediately restores preview approvals");[policy configurePreset:@"full" paths:@[] session:@"next-session" error:nil];check([[policy decisionForPlan:patch][@"decision"] isEqual:@"denied"],@"previous session plans denied after reconfiguration");
 TFAIRuntimePolicy *ordinary=[[TFAIRuntimePolicy alloc]initWithRoot:@"" projectID:@"general" sessionID:@"s"];check(![ordinary configurePreset:@"full" paths:@[] session:@"s" error:nil],@"ordinary chat cannot obtain project full permission");
 [policy configurePreset:@"full" paths:@[] session:@"s" error:nil];NSString *moved=[root stringByAppendingString:@"-moved"];[fm moveItemAtPath:root toPath:moved error:nil];[fm createSymbolicLinkAtPath:root withDestinationPath:NSHomeDirectory() error:nil];check([[policy decisionForPlan:plan(@"build_project",@{})][@"decision"] isEqual:@"denied"],@"root replaced by external symlink revokes full operation");[fm removeItemAtPath:root error:nil];[fm removeItemAtPath:moved error:nil];
}
#if __has_include(<UIKit/UIKit.h>)
#import "../App/AI/AIV2Contracts.h"
@interface NSObject (TFAIPermissionV4Calls)
- (void)runCall:(NSUInteger)index;
- (NSArray *)requestSchemas;
- (void)background;
@end
@interface TFAIPermissionV4RuntimeFixture : NSObject
@property id<TFAIRuntimeV2> runtime;
@property NSMutableArray *checks;
@property NSString *root,*session,*project;
@property NSUInteger phase,approvals;
@property BOOL finished;
@property(copy) void(^completion)(NSDictionary *);
@end
static TFAIPermissionV4RuntimeFixture *TFAIPermissionV4Active;
@implementation TFAIPermissionV4RuntimeFixture
- (void)check:(BOOL)ok name:(NSString *)name{[self.checks addObject:@{@"pass":@(ok),@"name":name}];}
- (void)finish{if(self.finished)return;self.finished=YES;self.runtime.event=nil;[self.runtime stop];[NSFileManager.defaultManager removeItemAtPath:self.root error:nil];BOOL pass=YES;for(NSDictionary *c in self.checks)pass&=[c[@"pass"] boolValue];self.completion(@{@"pass":@(pass),@"checks":self.checks});TFAIPermissionV4Active=nil;}
- (void)phaseComplete:(NSDictionary *)event {
 NSString *path=[self.root stringByAppendingPathComponent:[NSString stringWithFormat:@"Phase%lu.m",(unsigned long)self.phase]];BOOL exists=[NSFileManager.defaultManager fileExistsAtPath:path];BOOL full=self.phase==0||self.phase==4||self.phase==5;
 [self check:exists==(self.phase==4?NO:full) name:[NSString stringWithFormat:@"runtime phase %lu mutation %@",(unsigned long)self.phase,full?@"uses full grant":@"stays blocked"]];[self check:self.approvals==(self.phase==1?1:0) name:[NSString stringWithFormat:@"runtime phase %lu correct preview count",(unsigned long)self.phase]];
 self.runtime.event=nil;[self.runtime stop];
 if(full){__weak typeof(self) weak=self;NSUInteger phase=self.phase;[self.runtime undo:^(NSDictionary *result,NSError *error){NSString *restored=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];BOOL restoredCorrectly=phase==0?![NSFileManager.defaultManager fileExistsAtPath:path]:[restored isEqual:@"int fixture = 1;\n"];[weak check:!error&&restoredCorrectly name:[NSString stringWithFormat:@"full automatic mutation phase %lu retains backup and undo",(unsigned long)phase]];weak.phase++;[weak runPhase];}];}else{self.phase++;[self runPhase];}
}
- (void)runPhase {
 if(self.phase>=6){[self finish];return;}self.approvals=0;self.session=NSUUID.UUID.UUIDString;self.project=[@"permission-v4-" stringByAppendingString:NSUUID.UUID.UUIDString];self.runtime=(id<TFAIRuntimeV2>)TFAICreateRuntime(self.root,self.project,^(NSString *name,NSDictionary *arguments,TFAIResult done){done(nil,[NSError errorWithDomain:@"PermissionFixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Unexpected bridge call"}]);});[self.runtime activateSession:self.session];[self.runtime setInteractionMode:self.phase==2?@"ask":@"develop"];
 NSError *error=nil;BOOL full=self.phase!=1;[self check:[self.runtime configurePermissionPreset:full?@"full":@"assisted" paths:@[] error:&error] name:@"runtime accepts local user permission preset"];
 if(self.phase==3)[[(NSObject *)self.runtime valueForKey:@"policy"] setValue:@0 forKey:@"expiresAt"];
 NSObject *runtime=(id)self.runtime;[runtime setValue:@YES forKey:@"running"];[runtime setValue:self.phase==2?@"ask":@"develop" forKey:@"requestMode"];[runtime setValue:[NSMutableArray new] forKey:@"messages"];[runtime setValue:[NSMutableDictionary new] forKey:@"toolStarts"];NSString *relative=[NSString stringWithFormat:@"Phase%lu.m",(unsigned long)self.phase];if(self.phase>=4)[@"int fixture = 1;\n" writeToFile:[self.root stringByAppendingPathComponent:relative] atomically:YES encoding:NSUTF8StringEncoding error:nil];NSDictionary *call=@{@"id":NSUUID.UUID.UUIDString,@"name":self.phase==4?@"request_delete":self.phase==5?@"propose_patch":@"create_file",@"arguments":self.phase==4?@{@"path":relative}:self.phase==5?@{@"edits":@[@{@"path":relative,@"before":@"int fixture = 1;",@"after":@"int fixture = 2;"}]}:@{@"path":relative,@"content":@"int fixture = 1;\n"}};NSMutableArray *calls=[NSMutableArray arrayWithObject:call];if(self.phase==5)[calls addObject:@{@"id":NSUUID.UUID.UUIDString,@"name":@"apply_approved_patch",@"arguments":@{@"proposal_id":@"pending"}}];[runtime setValue:calls forKey:@"calls"];
 __weak typeof(self) weak=self;self.runtime.approval=^(NSDictionary *plan,void(^decision)(BOOL,NSArray *)){weak.approvals++;decision(NO,nil);};
 self.runtime.event=^(NSDictionary *event){TFAIPermissionV4RuntimeFixture *s=weak;if(!s||s.finished)return;if([event[@"type"] isEqual:@"tool_started"]&&((s.phase==0||s.phase==4)||[event[@"name"] isEqual:@"apply_approved_patch"]))[s check:[event[@"authorization"] isEqual:@"project-full"] name:@"automatic full write records project-full authorization"];if([event[@"type"] isEqual:@"permission_revoked"]&&s.phase==3)[s check:[event[@"preset"] isEqual:@"assisted"] name:@"expiry informs UI of restored per-action approval"];if([event[@"type"] isEqual:@"done"]&&s.phase==3){[s check:[event[@"state"] isEqual:@"interrupted"] name:@"expiry pauses active turn and cancels queued toolbox work"];[s phaseComplete:event];return;}if([event[@"type"] isEqual:@"tool_result"]){if(s.phase==5&&[event[@"name"] isEqual:@"propose_patch"]){NSMutableArray *calls=[(NSObject *)s.runtime valueForKey:@"calls"];NSMutableDictionary *next=[calls[1] mutableCopy];next[@"arguments"]=@{@"proposal_id":event[@"result"][@"proposal_id"]?:@"missing"};calls[1]=next;return;}if(s.phase==5)[s check:[[NSString stringWithContentsOfFile:[s.root stringByAppendingPathComponent:@"Phase5.m"] encoding:NSUTF8StringEncoding error:nil] isEqual:@"int fixture = 2;\n"] name:@"full patch executes exact prepared proposal"];[s phaseComplete:event];}};
 [(NSObject *)self.runtime runCall:0];
}
@end
@interface TFAIPermissionV4UploadToolbox : TFAIToolbox
@property NSString *fixtureProject,*fixtureSession;
@property NSMutableArray *contexts;
@property NSString *fixtureContext;
@end
@implementation TFAIPermissionV4UploadToolbox
- (void)cancel{}
- (void)setApprovalContext:(NSString *)context{self.fixtureContext=context;}
- (void)prepare:(NSDictionary *)request completion:(TFAIResult)completion{NSString *branch=[request[@"id"] isEqual:@"upload-three"]?@"feature":@"main";completion(@{@"id":NSUUID.UUID.UUIDString,@"project":self.fixtureProject,@"session":self.fixtureSession,@"expires":@(NSDate.date.timeIntervalSince1970+600),@"request":request,@"approval":@YES,@"remote":@"https://upload-fixture.example.invalid/project.git",@"branch":branch,@"upstream":[@"origin/" stringByAppendingString:branch],@"summary":[@"Upload to fixture branch " stringByAppendingString:branch]},nil);}
- (void)execute:(NSDictionary *)plan approved:(BOOL)approved completion:(TFAIResult)completion{[self.contexts addObject:self.fixtureContext?:@"missing"];completion(@{@"status":@"fixture-only"},nil);}
@end
static void TFAIPermissionV4UploadRegression(void(^completion)(NSDictionary *)){
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"permission-upload-fixture-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];id<TFAIRuntimeV2> runtime=(id)TFAICreateRuntime(root,@"upload-project",^(NSString *name,NSDictionary *arguments,TFAIResult done){done(nil,[NSError errorWithDomain:@"PermissionFixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Unexpected bridge call"}]);});[runtime activateSession:@"upload-session"];[runtime setInteractionMode:@"develop"];[runtime configurePermissionPreset:@"full_push" paths:@[] error:nil];NSObject *object=(id)runtime;TFAIPermissionV4UploadToolbox *toolbox=[TFAIPermissionV4UploadToolbox new];toolbox.contexts=[NSMutableArray new];toolbox.fixtureProject=@"upload-project";toolbox.fixtureSession=@"upload-session";[object setValue:toolbox forKey:@"toolbox"];[object setValue:@YES forKey:@"running"];[object setValue:@"develop" forKey:@"requestMode"];[object setValue:[NSMutableArray new] forKey:@"messages"];[object setValue:[NSMutableDictionary new] forKey:@"toolStarts"];NSMutableArray *calls=[NSMutableArray new];for(NSString *identifier in @[@"upload-one",@"upload-two",@"upload-three"])[calls addObject:@{@"id":identifier,@"name":@"git_upload",@"arguments":@{}}];[object setValue:calls forKey:@"calls"];
 NSMutableArray *checks=[NSMutableArray new];void(^check)(BOOL,NSString *)=^(BOOL ok,NSString *name){[checks addObject:@{@"pass":@(ok),@"name":name}];};__block NSUInteger approvals=0;__weak NSObject *weak=object;
 runtime.approval=^(NSDictionary *plan,void(^decision)(BOOL,NSArray *)){approvals++;check([plan[@"remote"] isEqual:@"https://upload-fixture.example.invalid/project.git"]&&[plan[@"branch"] length]>0,@"upload confirmation contains exact prepared remote and branch");decision(YES,nil);};
 runtime.event=^(NSDictionary *event){if(![event[@"type"] isEqual:@"tool_result"]||![event[@"id"] isEqual:@"upload-three"])return;id<TFAIRuntimeV2> active=(id)weak;check(approvals==2,@"first upload and changed branch ask approval; unchanged target auto-uploads");check([toolbox.contexts isEqual:@[@"explicit-preview",@"project-full",@"explicit-preview"]],@"upload audit distinguishes target confirmation from session auto grant");active.event=nil;[active stop];check([weak valueForKey:@"approvedUploadTarget"]==nil,@"stop clears approved upload target");[NSFileManager.defaultManager removeItemAtPath:root error:nil];BOOL pass=YES;for(NSDictionary *row in checks)pass&=[row[@"pass"] boolValue];completion(@{@"pass":@(pass),@"checks":checks});};
 [object runCall:0];
}
static void TFAIRunPermissionV4Regression(void(^completion)(NSDictionary *)) {
 TFAIPermissionV4RuntimeFixture *fixture=[TFAIPermissionV4RuntimeFixture new];fixture.checks=[NSMutableArray new];fixture.completion=^(NSDictionary *local){TFAIPermissionV4UploadRegression(^(NSDictionary *upload){NSArray *checks=[local[@"checks"] arrayByAddingObjectsFromArray:upload[@"checks"]];completion(@{@"pass":@([local[@"pass"] boolValue]&&[upload[@"pass"] boolValue]),@"checks":checks});});};fixture.root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"permission-runtime-v4-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtPath:fixture.root withIntermediateDirectories:YES attributes:nil error:nil];TFAIPermissionV4Active=fixture;[fixture runPhase];__weak typeof(fixture) weak=fixture;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(weak&&!weak.finished){[weak check:NO name:@"permission runtime fixture timeout"];[weak finish];}});
}
#endif
