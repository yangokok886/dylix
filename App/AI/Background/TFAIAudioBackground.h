#import <Foundation/Foundation.h>
BOOL TFAIAudioBackgroundEnabled(void);
void TFAIAudioBackgroundSetEnabled(BOOL enabled);
BOOL TFAIAudioBackgroundStart(void);
void TFAIAudioBackgroundStop(void);
BOOL TFAIAudioBackgroundPlaying(void);
NSDictionary *TFAIAudioBackgroundDiagnostics(void);
// Main-thread callback for interruptions, playback failures and resumes.
void TFAIAudioBackgroundObserve(void (^changed)(void));
