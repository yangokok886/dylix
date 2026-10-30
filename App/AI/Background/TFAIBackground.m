#import "TFAIBackground.h"
#if !defined(TFAI_BACKGROUND_FIXTURE)
#import "../LiveActivity/TFAILiveActivity.h"
#import "TFAIAudioBackground.h"
#else
static void TFAILiveUpdate(NSString *s,NSUInteger c,NSUInteger n){}
static void TFAILiveEnd(BOOL success){}
static BOOL TestAudioEnabled=NO,TestAudioPlaying=NO,TestAudioStartOK=YES;
static BOOL TFAIAudioBackgroundEnabled(void){return TestAudioEnabled;}
static BOOL TFAIAudioBackgroundStart(void){return TestAudioPlaying=TestAudioEnabled&&TestAudioStartOK;}
static BOOL TFAIAudioBackgroundPlaying(void){return TestAudioPlaying;}
static void TFAIAudioBackgroundStop(void){TestAudioPlaying=NO;}
static NSDictionary *TFAIAudioBackgroundDiagnostics(void){return @{@"enabled":@(TestAudioEnabled),@"playing":@(TestAudioPlaying)};}
static void TFAIAudioBackgroundObserve(void (^changed)(void)){}

#endif
#import <UIKit/UIKit.h>
#import <BackgroundTasks/BackgroundTasks.h>
#import "TFAIContinuedCompatibility.h"

@interface TFAIBackgroundCoordinator : NSObject
@property NSMutableDictionary<NSString *,void (^)(NSString *)> *runs;
@property NSMutableDictionary<NSString *,NSMutableDictionary *> *runStates;
@property NSUInteger audioStopGeneration;
@property BOOL audioStopPending;
@property UIBackgroundTaskIdentifier shortTask;
@property BGContinuedProcessingTask *continued API_AVAILABLE(ios(26.0));
@property BOOL registered,pending,failed;
@property NSUInteger steps,bytes,reasoningBytes,units,shortGeneration;
@property NSTimeInterval lastSignal,lastOutput,lastDiagnostic,phaseFraction;
@property NSString *phaseTool;
@property NSTimer *diagnosticTimer;
- (void)audioChanged;
- (void)audioPreferenceChanged;
- (void)releaseContinuedTask;
- (void)requestContinuedIfNeeded;
- (void)cancelPendingContinued;
- (void)continuedExpired:(BGContinuedProcessingTask *)task API_AVAILABLE(ios(26.0));
@property NSTimeInterval lastUpdate;
@property NSString *stage,*availability,*processID;
@property NSMutableArray *diagnosticEvents;
@end
@implementation TFAIBackgroundCoordinator
- (instancetype)init{if((self=[super init])){_runs=[NSMutableDictionary new];_runStates=[NSMutableDictionary new];_shortTask=UIBackgroundTaskInvalid;_stage=@"正在分析";_processID=NSUUID.UUID.UUIDString;_diagnosticEvents=[[NSUserDefaults.standardUserDefaults arrayForKey:@"TFAI.Background.Events"] mutableCopy]?:[NSMutableArray new];[self record:@"process_started" details:nil];__weak typeof(self) weak=self;TFAIAudioBackgroundObserve(^{[weak audioChanged];});[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioPreferenceChanged) name:@"TFAIAudioPreferenceChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(enteredBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];}return self;}
- (void)record:(NSString *)event details:(NSDictionary *)details{
 NSMutableDictionary *entry=[@{@"event":event,@"timestamp":@(NSDate.date.timeIntervalSince1970),@"process":self.processID?:@"",@"appState":@(UIApplication.sharedApplication.applicationState),@"activeRuns":@(self.runs.count),@"shortTaskActive":@(self.shortTask!=UIBackgroundTaskInvalid),@"continuedPending":@(self.pending)} mutableCopy];
 if(@available(iOS 26.0,*))entry[@"continuedActive"]=@(self.continued!=nil);
 NSTimeInterval remaining=UIApplication.sharedApplication.backgroundTimeRemaining;if(isfinite(remaining)&&remaining<86400)entry[@"backgroundSecondsRemaining"]=@(MAX(0,remaining));
 entry[@"audio"]=TFAIAudioBackgroundDiagnostics();entry[@"audioStopPending"]=@(self.audioStopPending);entry[@"receivedBytes"]=@(self.bytes);entry[@"reasoningBytes"]=@(self.reasoningBytes);entry[@"completedSteps"]=@(self.steps);entry[@"workUnits"]=@(self.units);entry[@"stage"]=self.stage?:@"";NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(self.lastSignal>0)entry[@"secondsSinceSignal"]=@(MAX(0,now-self.lastSignal));if(self.lastOutput>0)entry[@"secondsSinceOutput"]=@(MAX(0,now-self.lastOutput));if(@available(iOS 26.0,*)){if(self.continued){entry[@"progressTotal"]=@(self.continued.progress.totalUnitCount);entry[@"progressCompleted"]=@(self.continued.progress.completedUnitCount);}}
 [entry addEntriesFromDictionary:details?:@{}];[self.diagnosticEvents addObject:entry];while(self.diagnosticEvents.count>80)[self.diagnosticEvents removeObjectAtIndex:0];[NSUserDefaults.standardUserDefaults setObject:self.diagnosticEvents forKey:@"TFAI.Background.Events"];
}
- (void)audioChanged{if(!self.runs.count)return;BOOL playing=TFAIAudioBackgroundPlaying();[self record:playing?@"audio_resumed":@"audio_interrupted" details:nil];if(playing){self.availability=@"音频辅助后台运行中";[self releaseContinuedTask];[self cancelPendingContinued];[self endShort];}else{self.availability=@"音频辅助已中断 · 使用系统后台时间";[self beginShort];[self requestContinuedIfNeeded];}}
- (void)audioPreferenceChanged{if(!self.runs.count){if(!TFAIAudioBackgroundEnabled()){self.audioStopGeneration++;self.audioStopPending=NO;TFAIAudioBackgroundStop();}return;}if(TFAIAudioBackgroundEnabled()&&TFAIAudioBackgroundStart()){[self releaseContinuedTask];[self cancelPendingContinued];self.availability=@"音频辅助后台运行中";[self endShort];[self record:@"audio_started" details:nil];}else{TFAIAudioBackgroundStop();self.availability=@"使用系统短时后台执行";[self beginShort];[self record:@"audio_disabled_or_failed" details:nil];[self requestContinuedIfNeeded];}}
- (void)diagnosticTick{if(self.runs.count&&UIApplication.sharedApplication.applicationState==UIApplicationStateBackground)[self record:@"background_snapshot" details:nil];}
- (void)enteredBackground{if(!self.runs.count)return;if(TFAIAudioBackgroundEnabled()&&(TFAIAudioBackgroundPlaying()||TFAIAudioBackgroundStart())){[self audioChanged];[self record:@"entered_background" details:nil];return;}if(@available(iOS 26.0,*)){if(self.continued){[self record:@"entered_background" details:nil];return;}}[self beginShort];[self record:@"entered_background" details:nil];}
- (NSString *)identifier{return [NSBundle.mainBundle.bundleIdentifier stringByAppendingString:@".ai.processing"];}
- (void)registerTask{if(@available(iOS 26.0,*)){if(self.registered)return;__weak typeof(self) weak=self;self.registered=[BGTaskScheduler.sharedScheduler registerForTaskWithIdentifier:self.identifier usingQueue:dispatch_get_main_queue() launchHandler:^(__kindof BGTask *task){TFAIBackgroundCoordinator *s=weak;if(!s||![task isKindOfClass:BGContinuedProcessingTask.class]){[task setTaskCompletedWithSuccess:NO];return;}s.pending=NO;if(TFAIAudioBackgroundPlaying()){[task setTaskCompletedWithSuccess:NO];[s record:@"continued_superseded_by_audio" details:nil];return;}s.continued=(BGContinuedProcessingTask *)task;[s record:@"continued_started" details:nil];__weak BGContinuedProcessingTask *weakTask=(BGContinuedProcessingTask *)task;task.expirationHandler=^{dispatch_async(dispatch_get_main_queue(),^{BGContinuedProcessingTask *active=weakTask;if(active)[weak continuedExpired:active];});};if(!s.runs.count){[s completeSystemTask];return;}[s endShort];s.availability=@"系统持续后台任务已启用";[s updateSystemProgress:YES];}];}}
- (void)beginShort{if(self.shortTask!=UIBackgroundTaskInvalid||!self.runs.count)return;NSUInteger generation=++self.shortGeneration;__weak typeof(self) weak=self;self.shortTask=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"Dylix AI" expirationHandler:^{dispatch_async(dispatch_get_main_queue(),^{TFAIBackgroundCoordinator *s=weak;if(!s||s.shortGeneration!=generation)return;[s record:@"short_expired" details:nil];[s endShort];if(@available(iOS 26.0,*)){if(s.continued)return;}if(TFAIAudioBackgroundPlaying()){[s record:@"short_expired_audio_continues" details:nil];return;}if(UIApplication.sharedApplication.applicationState==UIApplicationStateBackground)[s expire:@"系统提供的后台执行时间已结束，已保存处理检查点，可在会话菜单继续分析。" source:@"short_expiration_handler"];});}];[self record:self.shortTask==UIBackgroundTaskInvalid?@"short_denied":@"short_started" details:nil];}
- (void)endShort{self.shortGeneration++;UIBackgroundTaskIdentifier task=self.shortTask;self.shortTask=UIBackgroundTaskInvalid;if(task!=UIBackgroundTaskInvalid)[UIApplication.sharedApplication endBackgroundTask:task];}
- (void)foreground{if(self.runs.count){if(TFAIAudioBackgroundEnabled()&&(TFAIAudioBackgroundPlaying()||TFAIAudioBackgroundStart())){[self audioChanged];[self record:@"returned_foreground" details:nil];return;}[self record:@"returned_foreground" details:nil];if(@available(iOS 26.0,*)){if(self.continued)return;}[self beginShort];[self requestContinuedIfNeeded];}}
- (NSString *)begin:(void (^)(NSString *))expired{NSString *token=NSUUID.UUID.UUIDString;BOOL first=!self.runs.count;self.audioStopGeneration++;self.audioStopPending=NO;void (^callback)(NSString *)=expired?:^(NSString *reason){};self.runs[token]=[callback copy];self.runStates[token]=[NSMutableDictionary new];if(!first){self.phaseTool=nil;self.phaseFraction=-1;[self updateSystemProgress:YES];return token;}self.failed=NO;self.steps=0;self.bytes=0;self.reasoningBytes=0;self.units=0;self.lastSignal=NSProcessInfo.processInfo.systemUptime;self.lastOutput=0;self.lastUpdate=0;self.lastDiagnostic=0;self.phaseTool=nil;self.phaseFraction=-1;[self.diagnosticTimer invalidate];self.diagnosticTimer=[NSTimer scheduledTimerWithTimeInterval:15 target:self selector:@selector(diagnosticTick) userInfo:nil repeats:YES];self.stage=@"正在连接模型";[self record:@"run_started" details:nil];self.availability=@"使用系统短时后台执行";if(TFAIAudioBackgroundEnabled()){BOOL ok=TFAIAudioBackgroundStart();[self record:ok?@"audio_started":@"audio_start_failed" details:nil];if(ok){self.availability=@"音频辅助后台运行中";TFAILiveUpdate(self.stage,self.runs.count,self.steps);return token;}}[self beginShort];TFAILiveUpdate(self.stage,self.runs.count,self.steps);[self requestContinuedIfNeeded];return token;}
- (void)requestContinuedIfNeeded{if(!self.runs.count||TFAIAudioBackgroundPlaying())return;if(@available(iOS 26.0,*)){if(self.continued){[self updateSystemProgress:YES];return;}if(!self.pending&&self.registered&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive){BGContinuedProcessingTaskRequest *request=[[BGContinuedProcessingTaskRequest alloc]initWithIdentifier:self.identifier title:@"Dylix AI" subtitle:@"正在分析"];request.strategy=BGContinuedProcessingTaskRequestSubmissionStrategyFail;self.pending=YES;NSError *error=nil;if(![BGTaskScheduler.sharedScheduler submitTaskRequest:request error:&error]){self.pending=NO;[self record:@"continued_submit_failed" details:@{@"errorDomain":error.domain?:@"",@"errorCode":@(error.code)}];self.availability=[NSString stringWithFormat:@"持续后台任务未获系统接纳（%ld），使用短时后台执行",(long)error.code];}else {self.availability=@"已申请系统持续后台任务";[self record:@"continued_submitted" details:nil];}}}}
- (void)cancelPendingContinued{if(@available(iOS 26.0,*)){if(self.pending){[BGTaskScheduler.sharedScheduler cancelTaskRequestWithIdentifier:self.identifier];self.pending=NO;[self record:@"continued_pending_cancelled" details:nil];}}}
- (void)continuedExpired:(BGContinuedProcessingTask *)task{if(self.continued!=task)return;[self record:@"continued_lease_expired" details:nil];
 // Expiration revokes this system lease, not a foreground run or another active execution mechanism.
 if(TFAIAudioBackgroundPlaying()||UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground){self.continued=nil;task.expirationHandler=nil;[task setTaskCompletedWithSuccess:NO];self.availability=TFAIAudioBackgroundPlaying()?@"音频辅助后台运行中":@"前台继续执行 · 持续后台任务已结束";if(!TFAIAudioBackgroundPlaying())[self beginShort];[self record:@"continued_expired_run_preserved" details:nil];return;}
 [self expire:@"系统结束了持续后台任务（取消或到期）。已保存处理检查点，可在会话菜单继续分析，先核对已执行操作。" source:@"continued_expiration_handler"];}
- (void)updateSystemProgress:(BOOL)force{NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(!force&&now-self.lastUpdate<1)return;self.lastUpdate=now;TFAILiveUpdate(self.stage,self.runs.count,self.steps);if(@available(iOS 26.0,*)){if(!self.continued)return;
 // Known local work reports phase completion; open-ended generation reports real units without a fabricated percentage.
 if(self.runs.count==1&&self.phaseFraction>=0){self.continued.progress.totalUnitCount=10000;self.continued.progress.completedUnitCount=MIN(9999,(int64_t)(self.phaseFraction*10000));}else{self.continued.progress.totalUnitCount=-1;self.continued.progress.completedUnitCount=(int64_t)self.units;}
 NSString *subtitle=self.stage;if(self.bytes+self.reasoningBytes)subtitle=[subtitle stringByAppendingFormat:@" · 已接收 %.1f KB",(self.bytes+self.reasoningBytes)/1024.0];[self.continued updateTitle:@"Dylix AI" subtitle:subtitle];}
 if(force||now-self.lastDiagnostic>=15){self.lastDiagnostic=now;[self record:@"progress_snapshot" details:nil];}}
- (void)update:(NSString *)token event:(NSDictionary *)event{if(!self.runs[token])return;NSString *type=event[@"type"];NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;BOOL force=NO;NSMutableDictionary *state=self.runStates[token];
 if([type isEqual:@"transport_error"]){[self record:@"transport_error" details:@{@"errorCode":event[@"code"]?:@0}];return;}
 if([type isEqual:@"text"]||[type isEqual:@"analysis_summary"]){NSUInteger bytes=[event[@"text"] isKindOfClass:NSString.class]?[event[@"text"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]:0;if(!bytes)return;if([type isEqual:@"text"]){self.bytes+=bytes;self.stage=@"正在接收回复";}else{self.reasoningBytes+=bytes;self.stage=@"正在接收思考内容";}self.units+=bytes;self.lastOutput=now;state[@"fraction"]=@(-1);}
 else if([type isEqual:@"tool_started"]){state[@"tool"]=[event[@"id"] isKindOfClass:NSString.class]?event[@"id"]:@"";state[@"fraction"]=@(-1);self.units++;self.stage=@"正在执行本机工具";force=YES;}
 else if([type isEqual:@"tool_progress"]){id value=event[@"progress"];if(![value isKindOfClass:NSNumber.class]||!isfinite([value doubleValue])||[value doubleValue]<0||[value doubleValue]>1)return;if(![state[@"tool"] isEqual:event[@"id"]])return;double fraction=[value doubleValue],previous=state[@"fraction"]?[state[@"fraction"] doubleValue]:-1;if(fraction<=previous)return;force=previous<0;self.units+=(NSUInteger)MAX(0,(fraction-MAX(0,previous))*10000);state[@"fraction"]=@(fraction);self.stage=@"正在处理本机工具";}
 else if([type isEqual:@"tool_result"]||[type isEqual:@"model_completed"]){self.steps++;self.units++;[state removeObjectForKey:@"tool"];state[@"fraction"]=@(-1);self.stage=@"正在整理分析";force=YES;}
 else if([type isEqual:@"assistant_start"]){[state removeObjectForKey:@"tool"];state[@"fraction"]=@(-1);self.stage=@"正在等待模型响应";force=YES;}
 else if([type isEqual:@"waiting_approval"]){self.stage=@"等待批准";state[@"fraction"]=@(-1);force=YES;}else return;
 state[@"stage"]=self.stage?:@"正在分析";self.phaseTool=self.runs.count==1?state[@"tool"]:nil;self.phaseFraction=self.runs.count==1&&state[@"fraction"]?[state[@"fraction"] doubleValue]:-1;self.lastSignal=now;[self updateSystemProgress:force];}
- (void)releaseContinuedTask{if(@available(iOS 26.0,*)){BGContinuedProcessingTask *task=self.continued;self.continued=nil;if(task){task.expirationHandler=nil;if(!self.failed){task.progress.totalUnitCount=MAX(1,self.steps);task.progress.completedUnitCount=task.progress.totalUnitCount;}[task setTaskCompletedWithSuccess:!self.failed];}}}
- (void)completeSystemTask{[self.diagnosticTimer invalidate];self.diagnosticTimer=nil;[self cancelPendingContinued];[self releaseContinuedTask];[self endShort];
 self.audioStopGeneration++;NSUInteger generation=self.audioStopGeneration;
 // A short successful handoff grace avoids tearing down and rebuilding the audio session between adjacent runs.
 if(!self.failed&&TFAIAudioBackgroundPlaying()){self.audioStopPending=YES;__weak typeof(self) weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.65*NSEC_PER_SEC)),dispatch_get_main_queue(),^{TFAIBackgroundCoordinator *s=weak;if(!s||s.audioStopGeneration!=generation||s.runs.count)return;s.audioStopPending=NO;TFAIAudioBackgroundStop();[s record:@"audio_stopped_idle" details:nil];});}
 else{self.audioStopPending=NO;TFAIAudioBackgroundStop();}}

- (void)end:(NSString *)token success:(BOOL)success{if(!self.runs[token])return;[self.runs removeObjectForKey:token];[self.runStates removeObjectForKey:token];[self record:@"run_ended" details:@{@"success":@(success)}];if(!success)self.failed=YES;if(!self.runs.count){self.availability=self.failed?@"后台任务已结束 · 存在中断记录":@"当前没有运行中的后台任务";TFAILiveEnd(!self.failed);[self completeSystemTask];}else{NSDictionary *state=self.runStates.allValues.firstObject;if(self.runs.count==1&&state[@"stage"])self.stage=state[@"stage"];self.phaseTool=state[@"tool"];self.phaseFraction=self.runs.count==1&&state[@"fraction"]?[state[@"fraction"] doubleValue]:-1;[self updateSystemProgress:YES];}}
- (void)expire:(NSString *)reason source:(NSString *)source{self.availability=@"系统后台任务已结束 · 检查点已保存";[self record:@"system_expiration" details:@{@"source":source?:@"unknown"}];NSArray *callbacks=[self.runs.allValues copy];[self.runs removeAllObjects];[self.runStates removeAllObjects];self.failed=YES;TFAILiveEnd(NO);for(void (^callback)(NSString *) in callbacks)callback(reason);[self completeSystemTask];}
@end
static TFAIBackgroundCoordinator *Coordinator(void){static TFAIBackgroundCoordinator *c;static dispatch_once_t once;dispatch_once(&once,^{c=[TFAIBackgroundCoordinator new];});return c;}
void TFAIBackgroundRegister(void){[Coordinator() registerTask];}
NSString *TFAIBackgroundBegin(void (^expired)(NSString *)){return [Coordinator() begin:expired];}
void TFAIBackgroundUpdate(NSString *token,NSDictionary *event){if(token)[Coordinator() update:token event:event];}
void TFAIBackgroundEnd(NSString *token,BOOL success){if(token)[Coordinator() end:token success:success];}
NSString *TFAIBackgroundStatus(void){return Coordinator().availability?:@"使用系统短时后台执行";}

NSDictionary *TFAIBackgroundDiagnostics(void){TFAIBackgroundCoordinator *c=Coordinator();return @{@"version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"",@"build":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"",@"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"currentProcess":c.processID?:@"",@"status":TFAIBackgroundStatus(),@"events":[c.diagnosticEvents copy]?:@[],@"note":@"appState: 0前台，1暂时不活跃，2后台。process变化表示App进程重启，不等于已确认系统杀进程；请结合系统ips日志判断。诊断不包含聊天、文件、密钥或设备标识。"};}

void TFAIBackgroundSetAudioEnabled(BOOL enabled){
#if !defined(TFAI_BACKGROUND_FIXTURE)
TFAIAudioBackgroundSetEnabled(enabled);
#else
TestAudioEnabled=enabled;
#endif
[NSNotificationCenter.defaultCenter postNotificationName:@"TFAIAudioPreferenceChanged" object:nil];}
