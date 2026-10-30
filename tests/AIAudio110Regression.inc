#import "../App/AI/Background/TFAIBackground.h"
#import "../App/AI/Background/TFAIAudioBackground.h"
static NSTimer *TFAIAudio110Timer;
UIViewController *TFAIAudio110Regression(void){
 UIViewController *v=[UIViewController new];v.view.backgroundColor=UIColor.systemBackgroundColor;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
  BOOL previous=TFAIAudioBackgroundEnabled();TFAIBackgroundSetAudioEnabled(YES);
  NSString *token=TFAIBackgroundBegin(^(NSString *reason){JSONWrite(@{@"pass":@NO,@"reason":reason,@"diagnostics":TFAIBackgroundDiagnostics()},[Docs() stringByAppendingPathComponent:@"ai-audio110.json"],nil);});
  __block NSUInteger writes=0,backgroundWrites=0;NSTimeInterval started=NSProcessInfo.processInfo.systemUptime;
  NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"AudioBackground110-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
  TFAIAudio110Timer=[NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *timer){
   writes++;BOOL bg=UIApplication.sharedApplication.applicationState==UIApplicationStateBackground;if(bg)backgroundWrites++;
   NSDictionary *sample=@{@"writes":@(writes),@"backgroundWrites":@(backgroundWrites),@"elapsed":@(NSProcessInfo.processInfo.systemUptime-started),@"audio":TFAIAudioBackgroundDiagnostics()};
   JSONWrite(sample,[root stringByAppendingPathComponent:@"progress.json"],nil);
   TFAIBackgroundUpdate(token,@{@"type":@"tool_result"});
   if(writes>=16){[timer invalidate];TFAIAudio110Timer=nil;BOOL playing=TFAIAudioBackgroundPlaying();TFAIBackgroundEnd(token,YES);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{BOOL stopped=!TFAIAudioBackgroundPlaying();JSONWrite(@{@"pass":@(playing&&stopped&&backgroundWrites>=12),@"sample":sample,@"stoppedAfterCompletion":@(stopped),@"diagnostics":TFAIBackgroundDiagnostics()},[Docs() stringByAppendingPathComponent:@"ai-audio110.json"],nil);TFAIBackgroundSetAudioEnabled(previous);[NSFileManager.defaultManager removeItemAtPath:root error:nil];});}
  }];
 });return v;
}
