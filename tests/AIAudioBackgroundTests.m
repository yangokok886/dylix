#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
NSString *UIApplicationDidBecomeActiveNotification=@"TestForeground",*UIApplicationDidEnterBackgroundNotification=@"TestBackground";
NSString *AVAudioSessionInterruptionNotification=@"Interruption",*AVAudioSessionMediaServicesWereResetNotification=@"Reset",*AVAudioSessionMediaServicesWereLostNotification=@"Lost",*AVAudioSessionInterruptionTypeKey=@"type",*AVAudioSessionInterruptionOptionKey=@"options",*AVAudioSessionCategoryPlayback=@"playback",*AVAudioSessionModeDefault=@"default";
static BOOL allowPlay=YES,allowSession=YES;
static NSUInteger checks,starts,stops;
static void Check(BOOL b,NSString *s){checks++;if(!b){NSLog(@"FAIL %@",s);exit(1);}NSLog(@"PASS %@",s);}
@implementation AVAudioSession
+ (AVAudioSession *)sharedInstance{static AVAudioSession *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
- (BOOL)setCategory:(NSString *)c mode:(NSString *)m options:(NSUInteger)o error:(NSError **)e{Check(o==AVAudioSessionCategoryOptionMixWithOthers,@"audio mixes instead of silencing another app");return YES;}
- (BOOL)setActive:(BOOL)a error:(NSError **)e{if(a){starts++;if(!allowSession&&e)*e=[NSError errorWithDomain:@"fixture.session" code:12 userInfo:nil];return allowSession;}stops++;return YES;}
- (BOOL)setActive:(BOOL)a withOptions:(NSUInteger)o error:(NSError **)e{Check(o==AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation,@"audio releases with notification");return [self setActive:a error:e];}
@end
@implementation AVAudioPlayer
- (instancetype)initWithData:(NSData *)data error:(NSError **)e{if((self=[super init]))Check(data.length==16044,@"silent PCM payload valid size");return self;}
- (BOOL)prepareToPlay{return YES;}
- (BOOL)play{self.playing=allowPlay;return allowPlay;}
- (void)pause{self.playing=NO;}
- (void)stop{self.playing=NO;}
@end
#import "../App/AI/Background/TFAIAudioBackground.m"
static void Drain(NSTimeInterval t){[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:t]];}
static void Interruption(NSUInteger type,NSUInteger options){[NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionInterruptionNotification object:nil userInfo:@{AVAudioSessionInterruptionTypeKey:@(type),AVAudioSessionInterruptionOptionKey:@(options)}];Drain(.03);}
int main(){@autoreleasepool{
 id previousPreference=[NSUserDefaults.standardUserDefaults objectForKey:@"TFAI.Background.AudioEnabled"];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"TFAI.Background.AudioEnabled"];Check(TFAIAudioBackgroundEnabled(),@"audio default enabled");
 __block NSUInteger changes=0;TFAIAudioBackgroundObserve(^{changes++;});
 Check(TFAIAudioBackgroundStart()&&TFAIAudioBackgroundPlaying(),@"audio starts actual playback");NSUInteger begun=starts;Check(TFAIAudioBackgroundStart()&&starts==begun,@"repeat request preserves active session");
 Interruption(AVAudioSessionInterruptionTypeBegan,0);Check(!TFAIAudioBackgroundPlaying()&&Audio().interrupted&&Audio().wanted,@"interruption pauses playback but keeps demand");
 Check(!TFAIAudioBackgroundStart(),@"no forced restart during active interruption");
 Interruption(AVAudioSessionInterruptionTypeEnded,0);Check(!TFAIAudioBackgroundPlaying()&&Audio().interrupted,@"missing resume permission remains suspended");
 [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];Drain(.03);Check(TFAIAudioBackgroundPlaying()&&!Audio().interrupted,@"foreground explicitly recovers ended interruption");
 Interruption(AVAudioSessionInterruptionTypeBegan,0);Interruption(AVAudioSessionInterruptionTypeEnded,AVAudioSessionInterruptionOptionShouldResume);Check(TFAIAudioBackgroundPlaying(),@"system resume permission recovers demand");
 [NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionMediaServicesWereLostNotification object:nil];Drain(.03);Check(!TFAIAudioBackgroundPlaying()&&Audio().wanted,@"media loss preserves demand while engine unavailable");
 [NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionMediaServicesWereResetNotification object:nil];Drain(.03);Check(TFAIAudioBackgroundPlaying(),@"media reset rebuilds player and session");
 allowPlay=NO;[Audio() audioPlayerDecodeErrorDidOccur:Audio().player error:[NSError errorWithDomain:@"fixture.decode" code:4 userInfo:nil]];Drain(.03);Check(!TFAIAudioBackgroundPlaying()&&Audio().retryPending,@"decode failure schedules bounded recovery");allowPlay=YES;Drain(.6);Check(TFAIAudioBackgroundPlaying()&&!Audio().retryPending,@"retry recovers actual playback");
 TFAIAudioBackgroundStop();allowSession=NO;Check(!TFAIAudioBackgroundStart()&&Audio().retryPending,@"session activation failure reports pending retry");TFAIAudioBackgroundStop();allowSession=YES;NSUInteger before=starts;Drain(.6);Check(!Audio().wanted&&!TFAIAudioBackgroundPlaying()&&starts==before,@"stop invalidates delayed restart");
 allowPlay=NO;[Audio() start];Drain(3.7);Check(Audio().retryCount==3&&!Audio().retryPending&&!TFAIAudioBackgroundPlaying(),@"repeated failure stops after three retries");
 TFAIAudioBackgroundStop();allowPlay=YES;TFAIAudioBackgroundSetEnabled(NO);Check(!TFAIAudioBackgroundStart()&&!TFAIAudioBackgroundPlaying(),@"disabled preference does not start player");Check(changes>=7,@"state observer receives actual transitions");Check([TFAIAudioBackgroundDiagnostics()[@"requested"] boolValue]==NO,@"diagnostics distinguish requested and playing");
 if(previousPreference)[NSUserDefaults.standardUserDefaults setObject:previousPreference forKey:@"TFAI.Background.AudioEnabled"];else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TFAI.Background.AudioEnabled"];NSLog(@"PASS %lu audio lifecycle checks",(unsigned long)checks);
 }return 0;}
