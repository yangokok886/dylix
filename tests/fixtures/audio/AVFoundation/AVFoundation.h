#define AVAudioSession TFMockAudioSession
#define AVAudioPlayer TFMockAudioPlayer
#define AVAudioPlayerDelegate TFMockAudioPlayerDelegate
#import <Foundation/Foundation.h>
extern NSString *AVAudioSessionInterruptionNotification,*AVAudioSessionMediaServicesWereResetNotification,*AVAudioSessionMediaServicesWereLostNotification,*AVAudioSessionInterruptionTypeKey,*AVAudioSessionInterruptionOptionKey,*AVAudioSessionCategoryPlayback,*AVAudioSessionModeDefault;
typedef NS_ENUM(NSUInteger,AVAudioSessionInterruptionType){AVAudioSessionInterruptionTypeEnded,AVAudioSessionInterruptionTypeBegan};
static const NSUInteger AVAudioSessionInterruptionOptionShouldResume=1,AVAudioSessionCategoryOptionMixWithOthers=1,AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation=1;
@protocol AVAudioPlayerDelegate <NSObject>
@end
@interface AVAudioPlayer : NSObject
@property(weak) id<AVAudioPlayerDelegate> delegate;
@property NSInteger numberOfLoops;
@property float volume;
@property(getter=isPlaying) BOOL playing;
- (instancetype)initWithData:(NSData *)data error:(NSError **)error;
- (BOOL)prepareToPlay;
- (BOOL)play;
- (void)pause;
- (void)stop;
@end
@interface AVAudioSession : NSObject
@property(class,readonly) AVAudioSession *sharedInstance;
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(NSUInteger)options error:(NSError **)error;
- (BOOL)setActive:(BOOL)active error:(NSError **)error;
- (BOOL)setActive:(BOOL)active withOptions:(NSUInteger)options error:(NSError **)error;
@end
