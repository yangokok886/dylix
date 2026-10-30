#import "GitAutomation.h"
#import "GitService.h"
#import "GitPreferences.h"
#import <UIKit/UIKit.h>
@interface TMCGitAutomation ()
@property NSMutableDictionary<NSString *,NSNumber *> *generations;
@property NSMutableDictionary<NSString *,NSString *> *pending;
@property BOOL active;
@end
@implementation TMCGitAutomation
+ (instancetype)shared{static TMCGitAutomation *value;static dispatch_once_t once;dispatch_once(&once,^{value=[self new];value.generations=[NSMutableDictionary new];value.pending=[NSMutableDictionary new];value.active=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;[NSNotificationCenter.defaultCenter addObserver:value selector:@selector(entered) name:UIApplicationDidBecomeActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:value selector:@selector(left) name:UIApplicationWillResignActiveNotification object:nil];});return value;}
- (void)left{self.active=NO;}
- (void)entered{self.active=YES;for(NSString *root in self.pending.allKeys)[self schedule:root trigger:self.pending[root] delay:2];}
- (void)cancelPending:(NSString *)root{self.generations[root]=@([self.generations[root] unsignedIntegerValue]+1);[self.pending removeObjectForKey:root];}
- (void)saved:(NSString *)root{NSDictionary *s=[TMCGitPreferences effective:root];if([s[@"enabled"] boolValue]&&[s[@"afterSave"] boolValue])[self schedule:root trigger:@"保存修改" delay:MAX(5,MIN(3600,[s[@"delay"] doubleValue]))];}
- (void)buildStarted:(NSString *)root{[TMCGitLease setBuilding:YES root:root];}
- (void)buildFinished:(NSString *)root success:(BOOL)success{[TMCGitLease setBuilding:NO root:root];NSDictionary *s=[TMCGitPreferences effective:root];if(success&&[s[@"enabled"] boolValue]&&[s[@"afterBuild"] boolValue])[self schedule:root trigger:@"构建成功" delay:1];else if(self.pending[root])[self schedule:root trigger:self.pending[root] delay:2];}
- (void)schedule:(NSString *)root trigger:(NSString *)trigger delay:(NSTimeInterval)delay{
 if(![NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@".git"]])return;
 NSUInteger generation=[self.generations[root] unsignedIntegerValue]+1;self.generations[root]=@(generation);self.pending[root]=trigger;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
 if([self.generations[root] unsignedIntegerValue]!=generation||!self.active)return;
 if([TMCGitLease isBuilding:root]){dispatch_async(TMCGitService.queue,^{[TMCGitPreferences record:@{@"status":@"paused",@"message":@"构建期间暂停自动存档，完成后继续"} root:root];});return;}
 dispatch_async(TMCGitService.queue,^{@autoreleasepool{
 __block BOOL eligible=NO;dispatch_sync(dispatch_get_main_queue(),^{eligible=self.active&&[self.generations[root] unsignedIntegerValue]==generation;});if(!eligible)return;
 NSDictionary *s=[TMCGitPreferences effective:root];if(![s[@"enabled"] boolValue]||([trigger isEqual:@"保存修改"]&&![s[@"afterSave"] boolValue])||([trigger isEqual:@"构建成功"]&&![s[@"afterBuild"] boolValue]))return;
 TMCGitService *g=[[TMCGitService alloc] initWithRoot:root];NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"yyyy-MM-dd HH:mm:ss";NSString *message=s[@"template"]?:@"存档 {project} · {date}";for(NSString *key in @[@"project",@"trigger",@"date"]){NSString *value=[key isEqual:@"project"]?root.lastPathComponent:[key isEqual:@"trigger"]?trigger:[f stringFromDate:NSDate.date];message=[message stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"{%@}",key] withString:value];}
 NSError *error=nil;NSDictionary *result=[g archive:message protection:NO name:s[@"name"] email:s[@"email"] error:&error];NSMutableDictionary *event=[(result?:@{@"status":@"paused",@"message":error.localizedDescription?:@"自动存档未完成"}) mutableCopy];event[@"trigger"]=trigger;
 if([result[@"status"] isEqual:@"committed"]){__block BOOL active=NO;dispatch_sync(dispatch_get_main_queue(),^{active=self.active;});[event addEntriesFromDictionary:[g pushArchive:result[@"id"] foreground:active]];}

 [TMCGitPreferences record:event root:root];dispatch_async(dispatch_get_main_queue(),^{if([self.generations[root] unsignedIntegerValue]==generation&&![event[@"status"] isEqual:@"paused"])[self.pending removeObjectForKey:root];[NSNotificationCenter.defaultCenter postNotificationName:@"TMCGitArchiveChanged" object:root];});
 }});
 });
}
@end

#if TARGET_OS_SIMULATOR
#import "GitUI.h"
UIViewController *TMCGitAutomationRegression(void){
 NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
 NSString *root=[documents stringByAppendingPathComponent:[@"GitAutomation-" stringByAppendingString:NSUUID.UUID.UUIDString]];
 [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 NSMutableDictionary *checks=[NSMutableDictionary new];NSDictionary *oldGlobal=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"GitGlobalSettings"];
 TMCGitService *g=[[TMCGitService alloc] initWithRoot:root];checks[@"init"]=@([g initialize:nil]);
 void (^write)(NSString *)=^(NSString *text){[text writeToFile:[root stringByAppendingPathComponent:@"source.m"] atomically:YES encoding:NSUTF8StringEncoding error:nil];};
 [TMCGitPreferences saveGlobal:@{@"name":@"Automation Fixture",@"email":@"fixture@example.org",@"enabled":@YES,@"afterSave":@YES,@"afterBuild":@YES,@"protect":@YES,@"delay":@5,@"template":@"{trigger} {project}"}];
 NSString *origin=[NSString stringWithFormat:@"https://%@.example.invalid",NSUUID.UUID.UUIDString.lowercaseString],*aid=NSUUID.UUID.UUIDString,*bid=NSUUID.UUID.UUIDString;
 NSString *url=[origin stringByAppendingString:@"/owner/project.git"];
 NSError *error=nil;
 checks[@"accountAStored"]=@([TMCGitPreferences saveAccount:@{@"id":aid,@"origin":origin,@"username":@"accountA",@"default":@YES} token:@"fixture-token-A" error:&error]);
 checks[@"accountBStored"]=@([TMCGitPreferences saveAccount:@{@"id":bid,@"origin":origin,@"username":@"accountB",@"default":@NO} token:@"fixture-token-B" error:&error]);
 checks[@"inheritsOnlyDefaultAccount"]=@([[TMCGitPreferences credential:url root:root][@"token"] isEqual:@"fixture-token-A"]);
 [TMCGitPreferences saveProject:@{@"authMode":@"account",@"account":bid,@"authURL":[TMCGitPreferences repositoryKey:url]} root:root error:nil];
 checks[@"repositoryAccountOverride"]=@([[TMCGitPreferences credential:url root:root][@"token"] isEqual:@"fixture-token-B"]);
 checks[@"accountCannotLeakToAnotherRepo"]=@(![TMCGitPreferences credential:[origin stringByAppendingString:@"/other/project.git"] root:root].count);
 checks[@"accountCannotLeakToAnotherService"]=@(![TMCGitPreferences credential:@"https://other.example.invalid/repo.git" root:root].count);
 [TMCGitPreferences deleteAccount:bid];checks[@"deletedOverrideDoesNotFallBack"]=@(![TMCGitPreferences credential:url root:root].count);
 NSString *metadata=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:TMCGitPreferences.accounts options:0 error:nil] encoding:NSUTF8StringEncoding];checks[@"PATNotInAccountMetadata"]=@(![metadata containsString:@"fixture-token"]);
 [TMCGitService saveCredentialForURL:url username:@"repoAccount" token:@"repo-fixture-token" error:nil];[TMCGitPreferences saveProject:@{@"authMode":@"repository",@"authURL":[TMCGitPreferences repositoryKey:url]} root:root error:nil];checks[@"legacyRepoPATOverride"]=@([[TMCGitPreferences credential:url root:root][@"username"] isEqual:@"repoAccount"]);[TMCGitPreferences saveProject:@{@"authMode":@"inherit"} root:root error:nil];checks[@"explicitInheritanceIgnoresLegacyRepoPAT"]=@([[TMCGitPreferences credential:url root:root][@"username"] isEqual:@"accountA"]);
 [TMCGitPreferences saveProject:@{@"authMode":@"none"} root:root error:nil];checks[@"disableAuth"]=@(![TMCGitPreferences credential:url root:root].count);[TMCGitService deleteCredentialForURL:url];[TMCGitPreferences deleteAccount:aid];[TMCGitPreferences saveProject:@{} root:root error:nil];
 void (^later)(double,dispatch_block_t)=^(double seconds,dispatch_block_t block){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),block);};
 TMCGitAutomation *autoGit=TMCGitAutomation.shared;
 later(1,^{[autoGit entered];write(@"int value=1;\n");[autoGit saved:root];});
 later(3,^{write(@"int value=2;\n");[autoGit saved:root];});
 later(6.7,^{checks[@"debounceCancelsEarlierSave"]=@([g history:nil].count==0);});
 later(10,^{checks[@"continuousSavesCoalesce"]=@([g history:nil].count==1);checks[@"archiveContainsLatestSavedText"]=@([[g diff:@"source.m" revision:nil staged:NO error:nil] length]==0);[autoGit saved:root];});
 later(16.5,^{checks[@"noEmptyScheduledCommit"]=@([g history:nil].count==1);[autoGit buildStarted:root];write(@"int value=3;\n");[autoGit saved:root];});
 later(23,^{checks[@"buildPausesScheduledCommit"]=@([[TMCGitPreferences records:root][0][@"status"] isEqual:@"paused"]);[autoGit buildFinished:root success:YES];});
 later(26,^{checks[@"successfulBuildArchivesOnce"]=@([g history:nil].count==2);checks[@"buildTriggerInMessage"]=@([[g history:nil][0][@"message"] containsString:@"构建成功"]);write(@"int value=4;\n");[g stage:@[@"source.m"] remove:NO error:nil];NSData *index=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".git/index"]];[index writeToFile:[root stringByAppendingPathComponent:@".studio-test-index"] atomically:YES];write(@"int value=5;\n");[autoGit saved:root];});
 later(33,^{checks[@"scheduledCommitPreservesStaging"]=@([[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".git/index"]] isEqual:[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".studio-test-index"]]]);checks[@"stagedPauseVisible"]=@([[TMCGitPreferences records:root][0][@"message"] containsString:@"暂存区"]);[g stage:@[@"source.m"] remove:YES error:nil];[autoGit left];[autoGit saved:root];});
 later(39,^{checks[@"inactiveDoesNotCommit"]=@([g history:nil].count==2);[autoGit entered];});
 later(43,^{checks[@"foregroundResumesPendingSave"]=@([g history:nil].count==3);checks[@"resultHasTimestamp"]=@([TMCGitPreferences records:root][0][@"date"]!=nil);[autoGit cancelPending:root];if(oldGlobal)[NSUserDefaults.standardUserDefaults setObject:oldGlobal forKey:@"GitGlobalSettings"];else[NSUserDefaults.standardUserDefaults removeObjectForKey:@"GitGlobalSettings"];BOOL all=YES;for(NSNumber *value in checks.allValues)all&=value.boolValue;NSDictionary *report=@{@"checks":checks,@"passed":@(all),@"root":root,@"count":@(checks.count)};[[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[documents stringByAppendingPathComponent:@"git-automation-test.json"] atomically:YES];});
 return TMCGitSettingsController(root);
}
#endif
