#import "TFAIAudioBackground.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
static NSString *const AudioPreference=@"TFAI.Background.AudioEnabled";
@interface TFAIAudioBackground : NSObject <AVAudioPlayerDelegate>
@property AVAudioPlayer *player;
@property BOOL wanted,interrupted,interruptionEnded,sessionActive;
@property NSString *failure;
@property NSUInteger retryGeneration,retryCount;
@property BOOL retryPending;
@property(copy) void (^changed)(void);
@end
@implementation TFAIAudioBackground
- (instancetype)init{if((self=[super init])){[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reset:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(mediaLost:) name:AVAudioSessionMediaServicesWereLostNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground:) name:UIApplicationDidBecomeActiveNotification object:nil];}return self;}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)notify{if(self.changed)self.changed();}
// One second of zero-valued PCM, generated locally; no file/network/recording permission.
- (NSData *)silence{NSMutableData *d=[NSMutableData new];[d appendBytes:"RIFF" length:4];uint32_t a=CFSwapInt32HostToLittle(16036);[d appendBytes:&a length:4];[d appendBytes:"WAVEfmt " length:8];a=CFSwapInt32HostToLittle(16);[d appendBytes:&a length:4];uint16_t b=CFSwapInt16HostToLittle(1);[d appendBytes:&b length:2];[d appendBytes:&b length:2];a=CFSwapInt32HostToLittle(8000);[d appendBytes:&a length:4];a=CFSwapInt32HostToLittle(16000);[d appendBytes:&a length:4];b=CFSwapInt16HostToLittle(2);[d appendBytes:&b length:2];b=CFSwapInt16HostToLittle(16);[d appendBytes:&b length:2];[d appendBytes:"data" length:4];a=CFSwapInt32HostToLittle(16000);[d appendBytes:&a length:4];[d increaseLengthBy:16000];return d;}
- (void)releaseSession{if(!self.sessionActive)return;self.sessionActive=NO;[AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];}
- (void)scheduleRetry{if(!self.wanted||self.interrupted||self.retryPending||self.retryCount>=3)return;self.retryPending=YES;NSUInteger generation=self.retryGeneration;NSTimeInterval delay=.5*(1<<self.retryCount++);__weak typeof(self) weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{TFAIAudioBackground *s=weak;if(!s||s.retryGeneration!=generation)return;s.retryPending=NO;if(!s.wanted||s.interrupted)return;[s start];[s notify];});}
- (BOOL)start{self.wanted=YES;if(self.player.isPlaying)return YES;if(self.interrupted)return NO;NSError *e=nil;AVAudioSession *session=AVAudioSession.sharedInstance;BOOL ready=[session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:&e];if(ready){ready=[session setActive:YES error:&e];self.sessionActive=ready;}
 if(!ready){self.failure=[NSString stringWithFormat:@"%@:%ld",e.domain?:@"AudioSession",(long)(e?e.code:-1)];[self scheduleRetry];return NO;}
 if(!self.player){self.player=[[AVAudioPlayer alloc]initWithData:[self silence] error:&e];self.player.delegate=self;self.player.numberOfLoops=-1;self.player.volume=.01;}BOOL ok=self.player&&[self.player prepareToPlay]&&[self.player play];self.failure=ok?nil:[NSString stringWithFormat:@"%@:%ld",e.domain?:@"AudioPlayback",(long)(e?e.code:-1)];if(!ok){self.player=nil;[self releaseSession];[self scheduleRetry];}else{self.retryGeneration++;self.retryCount=0;self.retryPending=NO;}return ok;}
- (void)stop{self.retryGeneration++;self.retryPending=NO;self.retryCount=0;self.wanted=NO;self.interrupted=NO;self.interruptionEnded=NO;[self.player stop];self.player=nil;[self releaseSession];}
- (void)interruption:(NSNotification *)n{NSDictionary *info=n.userInfo;dispatch_async(dispatch_get_main_queue(),^{if(!self.wanted)return;AVAudioSessionInterruptionType type=[info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];if(type==AVAudioSessionInterruptionTypeBegan){self.retryGeneration++;self.retryPending=NO;self.interrupted=YES;self.interruptionEnded=NO;self.sessionActive=NO;[self.player pause];}else{self.interruptionEnded=YES;BOOL resume=([info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue]&AVAudioSessionInterruptionOptionShouldResume)!=0;if(resume){self.interrupted=NO;self.retryCount=0;[self start];}else{self.interrupted=YES;self.failure=@"AudioInterruption:resume_not_granted";}}[self notify];});}
- (void)mediaLost:(NSNotification *)n{dispatch_async(dispatch_get_main_queue(),^{self.retryGeneration++;self.retryPending=NO;self.player=nil;self.sessionActive=NO;self.interrupted=YES;self.interruptionEnded=NO;if(self.wanted){self.failure=@"AudioSession:media_services_lost";[self notify];}});}
- (void)reset:(NSNotification *)n{dispatch_async(dispatch_get_main_queue(),^{self.retryGeneration++;self.retryPending=NO;self.retryCount=0;self.player=nil;self.sessionActive=NO;self.interrupted=NO;self.interruptionEnded=NO;if(self.wanted)[self start];[self notify];});}
- (void)foreground:(NSNotification *)n{dispatch_async(dispatch_get_main_queue(),^{if(!self.wanted)return;if(self.interrupted&&!self.interruptionEnded)return;self.interrupted=NO;self.retryCount=0;[self start];[self notify];});}
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error{dispatch_async(dispatch_get_main_queue(),^{if(player!=self.player)return;self.failure=[NSString stringWithFormat:@"%@:%ld",error.domain?:@"AudioDecode",(long)error.code];self.player=nil;[self releaseSession];[self scheduleRetry];[self notify];});}
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag{dispatch_async(dispatch_get_main_queue(),^{if(player!=self.player||!self.wanted)return;self.player=nil;self.failure=@"AudioPlayback:unexpected_stop";[self releaseSession];[self scheduleRetry];[self notify];});}
@end
static TFAIAudioBackground *Audio(void){static TFAIAudioBackground *a;static dispatch_once_t once;dispatch_once(&once,^{a=[TFAIAudioBackground new];});return a;}
BOOL TFAIAudioBackgroundEnabled(void){id v=[NSUserDefaults.standardUserDefaults objectForKey:AudioPreference];return v?[v boolValue]:YES;}
void TFAIAudioBackgroundSetEnabled(BOOL enabled){[NSUserDefaults.standardUserDefaults setBool:enabled forKey:AudioPreference];}
BOOL TFAIAudioBackgroundStart(void){return TFAIAudioBackgroundEnabled()&&[Audio() start];}
void TFAIAudioBackgroundStop(void){[Audio() stop];}
BOOL TFAIAudioBackgroundPlaying(void){return Audio().player.isPlaying;}
NSDictionary *TFAIAudioBackgroundDiagnostics(void){TFAIAudioBackground *a=Audio();return @{@"enabled":@(TFAIAudioBackgroundEnabled()),@"playing":@(a.player.isPlaying),@"requested":@(a.wanted),@"interrupted":@(a.interrupted),@"sessionActive":@(a.sessionActive),@"retryPending":@(a.retryPending),@"retryCount":@(a.retryCount),@"error":a.failure?:@""};}
void TFAIAudioBackgroundObserve(void (^changed)(void)){Audio().changed=changed;}
