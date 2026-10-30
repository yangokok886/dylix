#import "../Tools/TFAIWebTools.h"
#import "../ClassDump/TFAIClassDump.h"
#import "../ClassDump/TFAIClassDumpExecution.h"
#import "../AIContracts.h"
#import "../Background/TFAIBackground.h"
#import "../AIV2Contracts.h"
#import "AIPolicy.h"
#import "TFAIMessageMetadata.h"
#import "TFAIRecovery.h"
#import "TFAIDeveloperPrompt.h"
#import "../Binary/TFAIBinary.h"
#import "../Attachments/TFAIAttachmentStore.h"
#import "../../GitPreferences.h"
#import "../Permissions/TFAIPolicy.h"

static NSError *AIError(NSString *message) { return [NSError errorWithDomain:@"TweakForge.AI" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
@interface TFProjectAIRuntime : NSObject <TFAIRuntimeV2>
@property(nonatomic,copy) TFAIEvent event;
@property(nonatomic,copy) void (^approval)(NSDictionary *,void (^)(BOOL,NSArray<NSNumber *> *));
@property(nonatomic,copy) void (^bridge)(NSString *,NSDictionary *,TFAIResult);
@property NSString *root,*projectID,*sessionID;
@property TFAITransport *transport;
@property TFAIWebTools *webTools;
@property NSProgress *classDumpProgress;
@property TFAIToolbox *toolbox;
@property TFAIRuntimePolicy *policy;
@property NSMutableArray *messages,*calls;
@property NSMutableString *response;
@property NSDictionary *connection;
@property(nonatomic) NSDictionary *nextConnection;
@property(nonatomic) NSString *interactionMode,*requestMode;
@property NSMutableDictionary *toolStarts;
@property NSMutableDictionary *providerMetadata;
@property NSMutableDictionary *attachmentReferences;
@property NSUInteger generation,rounds,toolCount,receivedBytes;
@property NSTimeInterval started;
@property NSString *responseMessageID;
@property NSNumber *responseTimestamp;
@property BOOL running;
@property NSString *backgroundToken,*checkpointRunID,*checkpointState;
@property NSUInteger checkpointSequence;
@property NSTimeInterval checkpointTime;
@property NSMutableDictionary *activeToolRecords;
@property BOOL recoveryReadOnly;
@property NSUInteger developerPromptIndex;
@property NSDictionary *promptEnvironment;
@property(nonatomic) BOOL buildAllowed;
@property NSMutableSet *completedCalls;
@property NSDictionary *approvedUploadTarget;
@property NSString *pendingWorkspacePreset,*workspaceToolID;
@end
@implementation TFProjectAIRuntime
- (instancetype)init { if((self=[super init])){_completedCalls=[NSMutableSet new];[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];}return self; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self];[_transport cancel];[_toolbox cancel];[_webTools cancel];[_classDumpProgress cancel]; }
- (void)checkpoint:(BOOL)durable {if(!self.checkpointRunID.length||!self.event)return;NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(!durable&&now-self.checkpointTime<2)return;self.checkpointTime=now;NSMutableArray *transcript=[[self publicMessages] mutableCopy];if(self.response.length)[transcript addObject:@{@"role":@"assistant",@"content":[self.response copy],@"messageID":self.responseMessageID?:NSUUID.UUID.UUIDString,@"timestamp":self.responseTimestamp?:@(NSDate.date.timeIntervalSince1970)}];NSDictionary *checkpoint=@{@"schema":@1,@"runID":self.checkpointRunID,@"sequence":@(++self.checkpointSequence),@"savedAt":@(NSDate.date.timeIntervalSince1970),@"active":@(self.running),@"state":self.running?@"running":(self.checkpointState?:@"interrupted"),@"messages":transcript,@"pendingTools":self.activeToolRecords.allValues?:@[],@"rounds":@(self.rounds),@"receivedBytes":@(self.receivedBytes),@"recoveryMode":@"readOnlyReview"};self.event(@{@"type":@"checkpoint",@"checkpoint":checkpoint,@"durable":@(durable)});}
- (void)emit:(NSDictionary *)event {NSString *type=event[@"type"];if([type isEqual:@"tool_started"]&&event[@"id"]){if(!self.activeToolRecords)self.activeToolRecords=[NSMutableDictionary new];self.activeToolRecords[event[@"id"]]=@{@"id":event[@"id"],@"name":event[@"name"]?:@"tool",@"state":@"outcomeUnknown"};}else if([type isEqual:@"tool_result"]&&event[@"id"])[self.activeToolRecords removeObjectForKey:event[@"id"]];TFAIBackgroundUpdate(self.backgroundToken,event);if(self.event)self.event(event);if(self.running){BOOL boundary=[@[@"assistant_start",@"tool_started",@"tool_result",@"waiting_approval"] containsObject:type];if(boundary||[@[@"text",@"analysis_summary",@"tool_progress"] containsObject:type])[self checkpoint:boundary];}}
- (NSArray *)publicMessages {NSMutableArray *a=[NSMutableArray new];for(NSDictionary *m in self.messages)if(![m[@"role"] isEqual:@"system"])[a addObject:m];return a;}
- (void)revokePermission:(NSString *)reason {
 BOOL hadGrant=self.buildAllowed||self.policy!=nil;self.pendingWorkspacePreset=nil;self.approvedUploadTarget=nil;self.buildAllowed=NO;[self.policy revoke];self.policy=nil;
 if(hadGrant)[self emit:@{@"type":@"permission_revoked",@"preset":@"assisted",@"reason":reason?:@"会话权限已撤销"}];
}
- (void)checkPermissionExpiry {
 if(self.policy&&NSDate.date.timeIntervalSince1970>=self.policy.expiresAt){[self revokePermission:@"会话权限已到期，已恢复逐次批准"];if(self.running)[self finish:@"interrupted" message:@"会话权限已到期，本轮已暂停。请核对记录后重新发送。"];}
}
- (void)finish:(NSString *)state message:(NSString *)message {
 if(!self.running)return;
 self.running=NO;if(![state isEqual:@"completed"]&&[self.projectID isEqual:@"general"]&&self.bridge)self.bridge(@"cancel_workspace",@{},^(NSDictionary *r,NSError *e){});self.checkpointState=state;if(![state isEqual:@"completed"])[self revokePermission:@"任务已中断，已恢复逐次批准"];self.generation++;[self.transport cancel];[self.toolbox cancel];[self.webTools cancel];[self.classDumpProgress cancel];
 // Never save an assistant tool-call message without its matching results.
 if(self.response.length)[self.messages addObject:@{@"role":@"assistant",@"content":[self.response copy],@"messageID":self.responseMessageID?:NSUUID.UUID.UUIDString,@"timestamp":self.responseTimestamp?:@(NSDate.date.timeIntervalSince1970)}];self.response=nil;
 NSMutableSet *answered=[NSMutableSet new];for(NSDictionary *m in self.messages)if(m[@"tool_call_id"])[answered addObject:m[@"tool_call_id"]];
 NSMutableArray *dangling=[NSMutableArray new];for(NSDictionary *m in self.messages)for(NSDictionary *c in m[@"tool_calls"])if(![answered containsObject:c[@"id"]])[dangling addObject:c];
 for(NSDictionary *c in dangling)[self.messages addObject:@{@"role":@"tool",@"tool_call_id":c[@"id"],@"content":@"Execution interrupted. Check local state before proposing again; do not replay side effects."}];
 [self checkpoint:YES];
 if(message.length)[self emit:@{@"type":@"status",@"message":message}];
 [self emit:@{@"type":@"done",@"state":state,@"message":message?:@"",@"messages":[self publicMessages]}];TFAIBackgroundEnd(self.backgroundToken,[state isEqual:@"completed"]);self.backgroundToken=nil;
}
- (void)fail:(NSString *)message { [self emit:@{@"type":@"error",@"message":message?:@"请求失败"}];[self finish:@"interrupted" message:message?:@"请求失败"]; }
- (void)activateSession:(NSString *)sessionID {if(self.running)[self stop];[self revokePermission:@"会话已切换，已恢复逐次批准"];self.sessionID=sessionID;self.policy=[[TFAIRuntimePolicy alloc] initWithRoot:self.root projectID:(self.workspaceToolID?:self.projectID) sessionID:sessionID];self.toolbox=[[TFAIToolbox alloc] initWithRoot:self.root projectID:(self.workspaceToolID?:self.projectID) sessionID:sessionID];self.toolbox.bridge=self.bridge;}
- (BOOL)configurePermissionPreset:(NSString *)preset paths:(NSArray<NSString *> *)paths error:(NSError **)error {if(!self.sessionID.length){if(error)*error=AIError(@"请先打开会话");return NO;}if(self.running){if(error)*error=AIError(@"请先停止当前任务再修改权限");return NO;}if(!self.root.length){if(!self.policy)self.policy=[[TFAIRuntimePolicy alloc]initWithRoot:@"" projectID:(self.workspaceToolID?:self.projectID) sessionID:self.sessionID];BOOL ok=[self.policy configurePreset:@"assisted" paths:@[] session:self.sessionID error:error];if(ok)self.pendingWorkspacePreset=preset;return ok;}self.pendingWorkspacePreset=nil;if(!self.policy)self.policy=[[TFAIRuntimePolicy alloc] initWithRoot:self.root projectID:(self.workspaceToolID?:self.projectID) sessionID:self.sessionID];self.buildAllowed=NO;BOOL ok=[self.policy configurePreset:preset paths:paths session:self.sessionID error:error];if(ok){self.approvedUploadTarget=nil;TFAIRuntimePolicy *configured=self.policy;__weak typeof(self) weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1800*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(weak.policy==configured)[weak checkPermissionExpiry];});}return ok;}
- (void)setBuildAllowed:(BOOL)allowed {_buildAllowed=allowed;}
- (void)stop {if([self.projectID isEqual:@"general"]&&self.bridge)self.bridge(@"cancel_workspace",@{},^(NSDictionary *r,NSError *e){});[self revokePermission:@"任务已停止，已恢复逐次批准"]; [self finish:@"stopped" message:@"已停止模型请求与排队工具；已完成的修改会保留，可独立撤回。正在执行的本机编译在当前编译步骤结束后停止后续 AI 操作。"];} 
- (void)background {if(self.running)[self checkpoint:YES];if(self.running)[self emit:@{@"type":@"status",@"message":[TFAIBackgroundStatus() stringByAppendingString:@" · 系统允许期间继续处理"]}];} 
- (void)setNextConnection:(NSDictionary *)connection {_nextConnection=[connection copy];}
- (void)setInteractionMode:(NSString *)mode {_interactionMode=[mode isEqual:@"develop"]?@"develop":@"ask";}
- (NSSet *)selectedBinaryInputs {NSMutableDictionary *valid=[NSMutableDictionary new];for(NSString *key in self.attachmentReferences){NSDictionary *ref=self.attachmentReferences[key];if(![ref isKindOfClass:NSDictionary.class])continue;if(ref[@"derivedDirectoryGrant"]&&!TFAIReadDirectoryReference(@{@"directoryGrant":ref[@"derivedDirectoryGrant"]},@{@"action":@"validate"},nil))continue;valid[key]=ref;}return TFAIBinarySelectedIDs(valid);}
- (NSSet *)selectedClassDumpJobs {
 NSMutableSet *jobs=[NSMutableSet new];for(id ref in self.attachmentReferences.allValues)if([ref isKindOfClass:NSDictionary.class]){if(ref[@"derivedDirectoryGrant"]&&!TFAIReadDirectoryReference(@{@"directoryGrant":ref[@"derivedDirectoryGrant"]},@{@"action":@"validate"},nil))continue;id job=ref[@"classDumpJobID"]?:ref[@"classDumpInputID"]?:ref[@"binaryInputID"];if([job isKindOfClass:NSString.class]&&[[NSUUID alloc]initWithUUIDString:job])[jobs addObject:job];}return jobs;
}
- (NSSet *)selectedClassDumpInputs {NSMutableSet *ids=[NSMutableSet new];for(id ref in self.attachmentReferences.allValues)if([ref isKindOfClass:NSDictionary.class]){id value=ref[@"classDumpInputID"];if([value isKindOfClass:NSString.class]&&[[NSUUID alloc]initWithUUIDString:value])[ids addObject:value];}return ids;}
- (NSArray *)requestSchemas {
 if((self.connection[@"toolsEnabled"]&&![self.connection[@"toolsEnabled"] boolValue])||[self.connection[@"capabilities"][@"tools"] isEqual:@"unsupported"])return @[];
 NSMutableArray *schemas=[NSMutableArray arrayWithObject:TFAIDevelopmentGuideSchema()];
 if(!self.recoveryReadOnly&&[self.projectID isEqual:@"general"]){
 NSDictionary *str=@{@"type":@"string"};
 [schemas addObject:@{@"name":@"list_projects",@"description":@"List local Dylix projects with stable IDs. No writes.",@"parameters":@{@"type":@"object",@"properties":@{},@"additionalProperties":@NO}}];
 if(![self.requestMode isEqual:@"ask"])for(NSString *name in @[@"create_project",@"clone_project",@"select_project"]){NSDictionary *props=[name isEqual:@"select_project"]?@{@"project_id":str}:[name isEqual:@"clone_project"]?@{@"name":str,@"url":str}:@{@"name":str,@"template":@{@"type":@"string",@"enum":@[@"logos",@"objectivec",@"dylib"]}};[schemas addObject:@{@"name":name,@"description":@"Request confirmation to create/clone/select a local project and bind it to THIS conversation. Then project read/edit/config/build/git tools become available immediately. Clone accepts credential-free HTTPS repository URLs; create uses the app template and defaults. Never overwrite existing projects.",@"parameters":@{@"type":@"object",@"properties":props,@"required":[name isEqual:@"select_project"]?@[@"project_id"]:[name isEqual:@"clone_project"]?@[@"name",@"url"]:@[@"name",@"template"],@"additionalProperties":@NO}}];}
 }
if([self selectedBinaryInputs].count)[schemas addObjectsFromArray:TFAIBinarySchemas()];if(TFAIWebTools.enabled)[schemas addObjectsFromArray:TFAIWebTools.schemas];if(self.root.length){if(![self.requestMode isEqual:@"ask"])[schemas addObjectsFromArray:TFAIToolbox.schemas];else {NSSet *read=[NSSet setWithArray:@[@"list_files",@"read_file",@"search_text",@"list_symbols",@"read_project_config",@"read_diagnostics",@"list_artifacts",@"git_status",@"git_diff",@"git_history"]];for(NSDictionary *schema in TFAIToolbox.schemas)if([read containsObject:schema[@"name"]])[schemas addObject:schema];}}
 if(!self.recoveryReadOnly&&[self selectedClassDumpInputs].count)[schemas addObject:@{@"name":@"classdump_export",@"description":@"When the user asks to export headers from their selected IPA attachment, run local offline class-dump and create a shareable headers ZIP. Only exact input_id from the user manifest is accepted. Does not upload, execute, decrypt or modify the IPA or project. Returns jobID for classdump_headers. Repeated invocation reuses the output.",@"parameters":@{@"type":@"object",@"properties":@{@"input_id":@{@"type":@"string"}},@"required":@[@"input_id"],@"additionalProperties":@NO}}];
 if([self selectedClassDumpJobs].count)[schemas addObject:@{@"name":@"classdump_headers",@"description":@"Read only the user's selected local IPA class-dump job. Use job_id from the attachment manifest. list returns header paths; read returns bounded lines; search searches declarations. Continue list/search with next_offset as offset; read uses next_line as start_line. No IPA upload, binary execution or project edits.",@"parameters":@{@"type":@"object",@"properties":@{@"offset":@{@"type":@"integer",@"minimum":@0,@"maximum":@200000},@"job_id":@{@"type":@"string"},@"action":@{@"type":@"string",@"enum":@[@"list",@"read",@"search"]},@"path":@{@"type":@"string"},@"query":@{@"type":@"string"},@"start_line":@{@"type":@"integer",@"minimum":@1},@"line_count":@{@"type":@"integer",@"minimum":@1,@"maximum":@120}},@"required":@[@"job_id",@"action"],@"additionalProperties":@NO}}];
 if(self.attachmentReferences.count)[schemas addObject:@{@"name":@"read_attachment",@"description":@"Read an explicitly selected attachment by its exact ID. For a directory authorization use action=list (default), search (literal query, current level, bounded), read (relative path, max 120 lines/16KB; binary/XML Apple plist is decoded locally to XML text, never use inspect for plist), or inspect (relative path of Mach-O executable/dylib/framework binary, max 64MB; returns binary_id enabling binary_inspect locally without binary upload). List/search paginate with next_offset. Visit returned subdirectories explicitly. Files stay local until read; no writes or absolute paths. File snapshots use start_line/line_count as before.",@"parameters":@{@"type":@"object",@"properties":@{@"id":@{@"type":@"string"},@"action":@{@"type":@"string",@"enum":@[@"list",@"search",@"read",@"inspect"]},@"path":@{@"type":@"string"},@"query":@{@"type":@"string"},@"offset":@{@"type":@"integer",@"minimum":@0,@"maximum":@10000},@"start_line":@{@"type":@"integer",@"minimum":@1},@"line_count":@{@"type":@"integer",@"minimum":@1,@"maximum":@120}},@"required":@[@"id"],@"additionalProperties":@NO}}];return schemas;
}
- (void)send:(NSArray<NSDictionary *> *)messages session:(NSString *)sessionID {
 if(self.running){[self emit:@{@"type":@"error",@"message":@"请等待当前任务或先停止。"}];return;}
 [self checkPermissionExpiry];self.running=YES;self.generation++;self.rounds=0;self.toolCount=0;self.receivedBytes=0;self.started=NSProcessInfo.processInfo.systemUptime;self.checkpointRunID=NSUUID.UUID.UUIDString;self.checkpointSequence=0;self.checkpointTime=0;self.checkpointState=nil;self.activeToolRecords=[NSMutableDictionary new];self.recoveryReadOnly=[messages.lastObject[@"localRecovery"] boolValue];
 self.attachmentReferences=[NSMutableDictionary new];for(NSDictionary *m in messages)if([m[@"role"] isEqual:@"user"]&&[m[@"localAttachmentReferences"] isKindOfClass:NSDictionary.class])[self.attachmentReferences addEntriesFromDictionary:m[@"localAttachmentReferences"]];self.messages=[NSMutableArray new];if(![self.sessionID isEqual:sessionID])[self revokePermission:@"会话已切换，已恢复逐次批准"];self.sessionID=sessionID;self.response=nil;if(!self.policy)self.policy=[[TFAIRuntimePolicy alloc] initWithRoot:self.root projectID:(self.workspaceToolID?:self.projectID) sessionID:sessionID];
 self.connection=[self.nextConnection copy]?:[TFAIConnections effectiveForProject:self.projectID];self.requestMode=self.recoveryReadOnly?@"ask":(self.interactionMode?:@"develop");self.toolStarts=[NSMutableDictionary new];
 if(!self.connection||![self.connection[@"model"] length]){[self fail:@"请先在 AI 设置中选择连接并填写模型 ID。"];return;}
 NSData *input=[NSJSONSerialization dataWithJSONObject:messages options:0 error:nil];
 if(!input||input.length>8*1024*1024){[self fail:@"本次上下文超过 8 MB；请移除附件或开启新会话。原会话内容保持完整。"];return;}
 self.promptEnvironment=@{@"app":@"Dylix",@"version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"unknown",@"build":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"unknown",@"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"hasProject":@(self.root.length>0),@"mode":self.requestMode?:@"ask",@"model":self.connection[@"model"]?:@"",@"protocol":self.connection[@"protocol"]?:@"",@"recoveryReadOnly":@(self.recoveryReadOnly),@"attachmentReferenceCount":@(self.attachmentReferences.count)};
 self.developerPromptIndex=self.messages.count;
 [self.messages addObject:@{@"role":@"system",@"content":@""}];

 if(self.recoveryReadOnly)messages=TFAIRecoveryTranscript(messages);
 for(NSDictionary *m in TFAIMessageMetadata(messages,nil))if([@[@"user",@"assistant",@"tool"] containsObject:m[@"role"]])[self.messages addObject:m];
 self.toolbox=[[TFAIToolbox alloc] initWithRoot:self.root projectID:(self.workspaceToolID?:self.projectID) sessionID:sessionID];self.toolbox.bridge=self.bridge;
 self.transport=[TFAITransport new];__weak typeof(self) weak=self;self.backgroundToken=TFAIBackgroundBegin(^(NSString *reason){if(weak.running)[weak finish:@"interrupted" message:reason];});[self nextRound];

}
- (void)nextRound {
 if(!self.running)return;
 [self checkPermissionExpiry];if(!self.running)return;
 NSArray *schemas=[self requestSchemas];NSMutableDictionary *environment=[self.promptEnvironment mutableCopy]?:[NSMutableDictionary new];environment[@"permission"]=@{@"preset":self.pendingWorkspacePreset?:self.policy.preset?:@"assisted",@"expiresAt":@(self.policy.expiresAt)};environment[@"backgroundStatus"]=TFAIBackgroundStatus();
 if(self.developerPromptIndex<self.messages.count)self.messages[self.developerPromptIndex]=@{@"role":@"system",@"content":TFAIDeveloperPrompt(environment,schemas)};
 self.rounds++;
 NSData *payload=[NSJSONSerialization dataWithJSONObject:self.messages options:0 error:nil];if(payload.length>8*1024*1024){[self fail:@"累计上下文超过 8 MB，已暂停；请开始新会话并选择必要文件。"];return;}
 self.response=[NSMutableString new];self.providerMetadata=[NSMutableDictionary new];self.calls=[NSMutableArray new];NSUInteger token=self.generation;
 self.responseMessageID=NSUUID.UUID.UUIDString;self.responseTimestamp=@(NSDate.date.timeIntervalSince1970);[self emit:@{@"type":@"assistant_start",@"round":@(self.rounds),@"messageID":self.responseMessageID,@"timestamp":self.responseTimestamp}];
 __weak typeof(self) weak=self;
 [self.transport send:self.messages connection:self.connection tools:schemas event:^(NSDictionary *event){
  TFProjectAIRuntime *s=weak;if(!s.running||token!=s.generation)return;
  NSString *type=event[@"type"];
  if([type isEqual:@"text"]){NSString *text=event[@"text"]?:@"";s.receivedBytes+=[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];if(s.receivedBytes>1024*1024){[s fail:@"本轮输出超过 1 MB，已停止；部分输出已保留。"];return;}[s.response appendString:text];[s emit:event];}
  else if([type isEqual:@"tool_call"]){BOOL registered=NO;for(NSDictionary *schema in [s requestSchemas])if([schema[@"name"] isEqual:event[@"name"]])registered=YES;if(!registered){[s fail:s.root.length?@"当前为问答模式，此项目操作未执行。请切换开发模式后重新提出请求。":@"此工具尚未注册。开发任务可先创建、克隆或选择项目，再使用返回的项目工具。"];return;}if((s.connection[@"toolsEnabled"]&&![s.connection[@"toolsEnabled"] boolValue])||[s.connection[@"capabilities"][@"tools"] isEqual:@"unsupported"]){[s fail:@"当前连接已关闭工具调用，模型返回的操作未执行。"];return;}if(![event[@"id"] isKindOfClass:NSString.class]||![event[@"name"] isKindOfClass:NSString.class]||![event[@"arguments"] isKindOfClass:NSDictionary.class]){[s fail:@"模型工具请求格式不完整，未执行。"];return;}for(NSDictionary *c in s.calls)if([c[@"id"] isEqual:event[@"id"]]){if(![c[@"arguments"] isEqual:event[@"arguments"]]||![c[@"name"] isEqual:event[@"name"]])[s fail:@"重复工具 ID 的参数发生变化，已停止。 "];return;}[s.calls addObject:@{@"id":event[@"id"],@"name":event[@"name"],@"arguments":event[@"arguments"]}];[s emit:event];}
  else if([type isEqual:@"provider_items"]){s.providerMetadata[@"provider_items"]=event[@"items"]?:@[];for(NSString *key in @[@"providerProtocol",@"providerModel",@"providerConnectionID"])if(event[key])s.providerMetadata[key]=event[key];}
  else if([type isEqual:@"done"]){TFAIBackgroundUpdate(s.backgroundToken,@{@"type":@"model_completed"});if(!s.calls.count&&![[s.response stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length]){[s fail:@"服务端结束了本次响应，但没有返回正文或工具调用。已保留此前结果，请检查连接后继续。"];return;}NSMutableDictionary *m=[@{@"role":@"assistant",@"content":[s.response copy],@"messageID":s.responseMessageID,@"timestamp":s.responseTimestamp} mutableCopy];[m addEntriesFromDictionary:s.providerMetadata];if(s.calls.count)m[@"tool_calls"]=[s.calls copy];[s.messages addObject:m];s.response=nil;if(s.calls.count)[s runCall:0];else[s finish:@"completed" message:nil];}
  else if([type isEqual:@"error"]){TFAIBackgroundUpdate(s.backgroundToken,@{@"type":@"transport_error",@"code":event[@"code"]?:@0});[s fail:event[@"message"]?:@"模型请求失败"];}
  else [s emit:event];
 }];
}
- (NSDictionary *)uploadTargetForPlan:(NSDictionary *)plan {
 if(![plan[@"request"][@"name"] isEqual:@"git_upload"])return nil;
 NSMutableDictionary *target=[NSMutableDictionary new];for(NSString *key in @[@"remote",@"branch",@"upstream"]){id value=plan[key];if(![value isKindOfClass:NSString.class])return nil;target[key]=value;}
 if(![target[@"remote"] length]||![target[@"branch"] length])return nil;return target;
}
- (BOOL)requiresUploadTargetApproval:(NSDictionary *)plan permission:(NSDictionary *)permission {
 if(![plan[@"request"][@"name"] isEqual:@"git_upload"]||![permission[@"decision"] isEqual:@"allowed"]||![permission[@"preset"] hasPrefix:@"full"])return NO;
 NSDictionary *target=[self uploadTargetForPlan:plan];return !target||![self.approvedUploadTarget isEqual:target];
}
- (void)runCall:(NSUInteger)index {
 if(!self.running)return;if(index>=self.calls.count){[self nextRound];return;}
 self.toolCount++;
 NSDictionary *call=self.calls[index];NSString *identifier=call[@"id"];
 BOOL registered=NO;for(NSDictionary *schema in [self requestSchemas])if([schema[@"name"] isEqual:call[@"name"]])registered=YES;if(!registered){[self recordCall:call result:nil error:AIError(@"当前模式或会话范围未提供此工具，该操作未执行") index:index];return;}
 if([self.completedCalls containsObject:identifier]){[self recordCall:call result:nil error:AIError(@"该调用 ID 已执行；为避免重复操作，本次不重放。") index:index];return;}
 NSUInteger token=self.generation;__weak typeof(self) weak=self;
 if([@[@"list_projects",@"create_project",@"clone_project",@"select_project"] containsObject:call[@"name"]]){
 BOOL read=[call[@"name"] isEqual:@"list_projects"];NSDictionary *args=call[@"arguments"],*schema=nil;for(NSDictionary *candidate in [self requestSchemas])if([candidate[@"name"] isEqual:call[@"name"]])schema=candidate;
 BOOL valid=YES;for(NSString *key in args)if(!schema[@"parameters"][@"properties"][key]||![args[key] isKindOfClass:NSString.class]||[args[key] length]>2048)valid=NO;for(NSString *key in schema[@"parameters"][@"required"])if(![args[key] length])valid=NO;
 if(!valid){[self recordCall:call result:nil error:AIError(@"项目操作参数有误") index:index];return;}
 void (^execute)(void)=^{if(!weak.running||weak.generation!=token)return;weak.toolStarts[identifier]=@(NSProcessInfo.processInfo.systemUptime);[weak emit:@{@"type":@"tool_started",@"id":identifier,@"name":call[@"name"],@"arguments":args}];if(!weak.bridge){[weak recordCall:call result:nil error:AIError(@"项目服务未连接") index:index];return;}weak.bridge(call[@"name"],args,^(NSDictionary *result,NSError *error){if(!weak.running||weak.generation!=token)return;
 if(!error&&!read){NSString *root=result[@"root"];BOOL dir=NO;if(![root isKindOfClass:NSString.class]||![NSFileManager.defaultManager fileExistsAtPath:root isDirectory:&dir]||!dir){[weak recordCall:call result:nil error:AIError(@"项目服务未返回有效目录") index:index];return;}
 NSString *preset=weak.pendingWorkspacePreset?:weak.policy.preset?:@"assisted";BOOL build=weak.buildAllowed;[weak.policy revoke];weak.approvedUploadTarget=nil;weak.root=root;weak.workspaceToolID=result[@"projectID"];weak.policy=[[TFAIRuntimePolicy alloc]initWithRoot:root projectID:(weak.workspaceToolID?:weak.projectID) sessionID:weak.sessionID];[weak.policy configurePreset:preset paths:@[] session:weak.sessionID error:nil];weak.buildAllowed=build;weak.pendingWorkspacePreset=nil;weak.toolbox=[[TFAIToolbox alloc]initWithRoot:root projectID:(weak.workspaceToolID?:weak.projectID) sessionID:weak.sessionID];weak.toolbox.bridge=weak.bridge;NSMutableDictionary *env=[weak.promptEnvironment mutableCopy];env[@"hasProject"]=@YES;weak.promptEnvironment=env;[weak emit:@{@"type":@"workspace_bound",@"root":root,@"projectID":result[@"projectID"]?:@"",@"name":result[@"name"]?:root.lastPathComponent}];}
 NSMutableDictionary *publicResult=[result mutableCopy];[publicResult removeObjectForKey:@"root"];[weak.completedCalls addObject:identifier];[weak recordCall:call result:publicResult error:error index:index];});};
 if(read){execute();return;}if(!self.approval){[self recordCall:call result:nil error:AIError(@"项目操作需要确认目标") index:index];return;}NSDictionary *plan=@{@"id":NSUUID.UUID.UUIDString,@"request":call,@"summary":@"确认项目操作并用于当前会话；已有同名项目保留，参考附件保持只读。",@"edits":@[]};__block BOOL answered=NO;[self emit:@{@"type":@"waiting_approval"}];self.approval(plan,^(BOOL approved,NSArray *edits){if(answered)return;answered=YES;if(!weak.running||weak.generation!=token)return;if(approved)execute();else[weak recordCall:call result:nil error:AIError(@"用户取消项目操作") index:index];});return;
 }
 if([call[@"name"] isEqual:@"read_development_guide"]){self.toolStarts[identifier]=@(NSProcessInfo.processInfo.systemUptime);[self emit:@{@"type":@"tool_started",@"id":identifier,@"name":call[@"name"],@"arguments":call[@"arguments"]}];NSError *error=nil;NSDictionary *result=TFAIDevelopmentGuide(call[@"arguments"],&error);[self.completedCalls addObject:identifier];[self recordCall:call result:result error:error index:index];return;}
 if([@[@"web_read",@"web_search",@"github_query"] containsObject:call[@"name"]]){self.toolStarts[identifier]=@(NSProcessInfo.processInfo.systemUptime);[self emit:@{@"type":@"tool_started",@"id":identifier,@"name":call[@"name"],@"arguments":call[@"arguments"]}];TFAIWebTools *web=[TFAIWebTools new];self.webTools=web;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *result=[web execute:call[@"name"] arguments:call[@"arguments"] error:&error];dispatch_async(dispatch_get_main_queue(),^{if(!weak.running||weak.generation!=token)return;weak.webTools=nil;[weak.completedCalls addObject:identifier];[weak recordCall:call result:result error:error index:index];});});return;}
 if([call[@"name"] isEqual:@"binary_inspect"]){NSString *binary=call[@"arguments"][@"binary_id"];if(![[self selectedBinaryInputs] containsObject:binary?:@""]){[self recordCall:call result:nil error:AIError(@"此二进制尚未附加到当前会话") index:index];return;}self.toolStarts[identifier]=@(NSProcessInfo.processInfo.systemUptime);[self emit:@{@"type":@"tool_started",@"id":identifier,@"name":@"binary_inspect",@"arguments":call[@"arguments"]}];dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *result=TFAIBinaryExecute(binary,call[@"arguments"],&error);dispatch_async(dispatch_get_main_queue(),^{if(!weak.running||weak.generation!=token)return;[weak.completedCalls addObject:identifier];[weak recordCall:call result:result error:error index:index];});});return;}
 if([call[@"name"] isEqual:@"classdump_export"]){NSDictionary *args=call[@"arguments"];NSString *input=args[@"input_id"];if(args.count!=1||![input isKindOfClass:NSString.class]||![[self selectedClassDumpInputs] containsObject:input]){[self recordCall:call result:nil error:AIError(@"请使用用户在当前会话附加的 IPA input_id") index:index];return;}self.toolStarts[identifier]=@(NSProcessInfo.processInfo.systemUptime);[self emit:@{@"type":@"tool_started",@"id":identifier,@"name":call[@"name"],@"arguments":args}];NSProgress *progress=[NSProgress progressWithTotalUnitCount:100];self.classDumpProgress=progress;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *result=TFAIClassDumpExecute(input,progress,^(double fraction,NSString *message){dispatch_async(dispatch_get_main_queue(),^{if(weak.running&&weak.generation==token)[weak emit:@{@"type":@"tool_progress",@"id":identifier,@"name":@"classdump_export",@"progress":@(fraction),@"message":message?:@""}];});},&error);dispatch_async(dispatch_get_main_queue(),^{if(!weak.running||weak.generation!=token)return;weak.classDumpProgress=nil;[weak.completedCalls addObject:identifier];[weak recordCall:call result:result error:error index:index];});});return;}
 if([call[@"name"] isEqual:@"classdump_headers"]){NSString *job=call[@"arguments"][@"job_id"];if(![job isKindOfClass:NSString.class]||![[self selectedClassDumpJobs] containsObject:job]){[self recordCall:call result:nil error:AIError(@"此头文件目录尚未由用户附加到当前会话") index:index];return;}self.toolStarts[identifier]=@(NSProcessInfo.processInfo.systemUptime);[self emit:@{@"type":@"tool_started",@"id":identifier,@"name":call[@"name"],@"arguments":call[@"arguments"]}];dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *result=TFAIClassDumpRead(job,call[@"arguments"],&error);dispatch_async(dispatch_get_main_queue(),^{if(!weak.running||weak.generation!=token)return;[weak.completedCalls addObject:identifier];[weak recordCall:call result:result error:error index:index];});});return;}
 if([call[@"name"] isEqual:@"read_attachment"]){self.toolStarts[identifier]=@(NSProcessInfo.processInfo.systemUptime);[self emit:@{@"type":@"tool_started",@"id":identifier,@"name":call[@"name"],@"arguments":call[@"arguments"]}];NSDictionary *references=[self.attachmentReferences copy];dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *failure=nil;NSDictionary *result=TFAIReadAttachmentReferences(references,call[@"arguments"],&failure);dispatch_async(dispatch_get_main_queue(),^{if(!weak.running||weak.generation!=token)return;if(!failure&&result[@"binaryInputID"]){NSDictionary *origin=references[call[@"arguments"][@"id"]];if(origin[@"directoryGrant"]){NSString *key=[@"directory-binary-" stringByAppendingString:result[@"binaryInputID"]];NSDictionary *derived=@{@"binaryInputID":result[@"binaryInputID"],@"derivedDirectoryGrant":origin[@"directoryGrant"],@"path":result[@"path"]?:@"Mach-O"};weak.attachmentReferences[key]=derived;for(NSInteger i=weak.messages.count-1;i>=0;i--){NSDictionary *m=weak.messages[i];if([m[@"role"] isEqual:@"user"]){NSMutableDictionary *updated=[m mutableCopy],*refs=[m[@"localAttachmentReferences"] mutableCopy]?:[NSMutableDictionary new];refs[key]=derived;updated[@"localAttachmentReferences"]=refs;weak.messages[i]=updated;break;}}}}[weak.completedCalls addObject:identifier];[weak recordCall:call result:result error:failure index:index];});});return;}
 [self.toolbox prepare:call completion:^(NSDictionary *plan,NSError *error){TFProjectAIRuntime *s=weak;if(!s.running||token!=s.generation)return;if(error||!plan){[s recordCall:call result:nil error:error?:AIError(@"工具计划为空") index:index];return;}
  [s checkPermissionExpiry];if(!s.running||token!=s.generation)return;if(!s.policy)s.policy=[[TFAIRuntimePolicy alloc] initWithRoot:s.root projectID:(s.workspaceToolID?:s.projectID) sessionID:s.sessionID];NSDictionary *permission=[s.policy decisionForPlan:plan];if([permission[@"decision"] isEqual:@"denied"]){[s recordCall:call result:nil error:AIError(permission[@"reason"]) index:index];return;}
  BOOL uploadConfirmation=[s requiresUploadTargetApproval:plan permission:permission];__block BOOL explicitlyApproved=NO;
  void (^execute)(NSDictionary *)=^(NSDictionary *approvedPlan){if(!weak.running||weak.generation!=token)return;
   [weak checkPermissionExpiry];if(!weak.running||weak.generation!=token)return;if(!weak.policy){[weak recordCall:call result:nil error:AIError(@"会话权限已到期，请重新批准该操作") index:index];return;}NSDictionary *current=[weak.policy decisionForPlan:approvedPlan];NSError *guard=nil;if([current[@"decision"] isEqual:@"denied"]){[weak recordCall:call result:nil error:AIError(current[@"reason"]) index:index];return;}
   if([weak requiresUploadTargetApproval:approvedPlan permission:current]&&!explicitlyApproved){[weak recordCall:call result:nil error:AIError(@"首次上传或上传目标变化，请先确认实际远端与分支") index:index];return;}
   if(explicitlyApproved&&[call[@"name"] isEqual:@"git_upload"]&&[current[@"preset"] hasPrefix:@"full"]&&[current[@"decision"] isEqual:@"allowed"])weak.approvedUploadTarget=[weak uploadTargetForPlan:approvedPlan];
   if([current[@"decision"] isEqual:@"needsApproval"]&&![current[@"separateConfirmation"] boolValue]&&!(weak.buildAllowed&&[call[@"name"] isEqual:@"build_project"])){
    if(![weak.policy grantReviewedPlan:approvedPlan session:weak.sessionID error:&guard]||![weak.policy consumeReviewedPlan:approvedPlan error:&guard]){[weak recordCall:call result:nil error:guard index:index];return;}
   }
   NSString *authorization=explicitlyApproved?@"explicit-preview":[current[@"readOnly"] boolValue]?@"read-only":[current[@"decision"] isEqual:@"allowed"]&&[current[@"preset"] hasPrefix:@"full"]?@"project-full":([call[@"name"] isEqual:@"build_project"]&&([current[@"decision"] isEqual:@"allowed"]||weak.buildAllowed))?@"session-build":@"explicit-preview";
   [weak.toolbox setApprovalContext:authorization];
   weak.toolStarts[identifier]=@(NSProcessInfo.processInfo.systemUptime);[weak emit:@{@"type":@"tool_started",@"id":identifier,@"name":call[@"name"],@"arguments":call[@"arguments"],@"time":@(NSDate.date.timeIntervalSince1970),@"approvalMode":current[@"preset"]?:@"assisted",@"authorization":authorization}];
   [weak.toolbox execute:approvedPlan approved:YES completion:^(NSDictionary *result,NSError *failure){if(!weak.running||weak.generation!=token)return;[weak.completedCalls addObject:identifier];[weak recordCall:call result:result error:failure index:index];}];};
  if(!uploadConfirmation&&([permission[@"decision"] isEqual:@"allowed"]||(s.buildAllowed&&[call[@"name"] isEqual:@"build_project"]))){execute(plan);return;}
  if(!s.approval){[s recordCall:call result:nil error:AIError(@"此操作需要用户批准，当前没有可用批准界面。") index:index];return;}
  __block BOOL answered=NO;[s emit:@{@"type":@"waiting_approval"}];s.approval(plan,^(BOOL approved,NSArray<NSNumber *> *indexes){if(answered)return;answered=YES;if(!weak.running||token!=weak.generation)return;if(!approved){[weak recordCall:call result:nil error:AIError(@"用户拒绝了操作，请勿重复请求。") index:index];return;}explicitlyApproved=YES;if(indexes){[weak.toolbox selectEdits:indexes plan:plan completion:^(NSDictionary *selected,NSError *failure){if(!weak.running||token!=weak.generation)return;if(failure)[weak recordCall:call result:nil error:failure index:index];else execute(selected);}];}else execute(plan);});
 }];
}
- (void)recordCall:(NSDictionary *)call result:(NSDictionary *)result error:(NSError *)error index:(NSUInteger)index {
 if(!self.running)return;NSDictionary *value=error?@{@"error":error.localizedDescription}:result?:@{};
 NSData *bytes=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
 if(bytes.length>512*1024){value=@{@"error":@"结果超过 512 KB；请缩小查询范围。未自动发送被截断内容。"};bytes=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];}
 NSString *text=bytes?[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding]:@"{}";
 if(TFAIContainsSecret(text)){value=@{@"error":@"结果包含疑似密钥，已阻止将此工具输出发送给模型。请在本机检查并去除敏感信息。"};text=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] encoding:NSUTF8StringEncoding];}
 [self.messages addObject:@{@"role":@"tool",@"tool_call_id":call[@"id"],@"content":text}];
 [self emit:@{@"type":@"tool_result",@"id":call[@"id"],@"name":call[@"name"],@"result":value,@"duration":self.toolStarts[call[@"id"]]?@(MAX(0,NSProcessInfo.processInfo.systemUptime-[self.toolStarts[call[@"id"]] doubleValue])):@0}];
 [self runCall:index+1];
}
- (void)undo:(TFAIResult)completion {if(!self.root.length){completion(nil,AIError(@"普通会话没有项目修改可撤回"));return;}if(self.running){completion(nil,AIError(@"请先停止当前任务再撤回。"));return;}if(!self.toolbox)self.toolbox=[[TFAIToolbox alloc] initWithRoot:self.root projectID:(self.workspaceToolID?:self.projectID) sessionID:self.sessionID?:@"undo"];[self.toolbox undo:completion];}
@end
id<TFAIRuntimeV2> TFAICreateRuntime(NSString *root,NSString *projectID,void (^bridge)(NSString *,NSDictionary *,TFAIResult)) {TFProjectAIRuntime *r=[TFProjectAIRuntime new];r.root=root;r.projectID=projectID;if([projectID isEqual:@"general"]&&root.length)r.workspaceToolID=TFAIProjectID(root);r.bridge=bridge;return r;}
NSString *TFAIProjectID(NSString *root) {
 // Hidden local identity travels with a renamed project but is excluded from source sharing.
 NSString *path=[root stringByAppendingPathComponent:@".studio-ai-identity.json"];
 id data=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path]?:NSData.data options:0 error:nil];
 if([data isKindOfClass:NSDictionary.class]&&[data[@"id"] isKindOfClass:NSString.class]&&[[NSUUID alloc] initWithUUIDString:data[@"id"]])return data[@"id"];
 TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease)return nil;
 NSString *uuid=NSUUID.UUID.UUIDString;NSError *error=nil;NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"schema":@1,@"id":uuid} options:0 error:&error];
 if(![json writeToFile:path options:NSDataWritingAtomic error:&error])return nil;return uuid;
}

void TFAIRebindRuntime(id<TFAIRuntime> runtime,void (^bridge)(NSString *,NSDictionary *,TFAIResult)){if([runtime isKindOfClass:TFProjectAIRuntime.class]){TFProjectAIRuntime *r=(TFProjectAIRuntime *)runtime;r.bridge=bridge;r.toolbox.bridge=bridge;}}
