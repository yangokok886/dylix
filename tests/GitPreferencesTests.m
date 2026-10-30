#import <Foundation/Foundation.h>
#import "GitPreferences.h"
#import "GitService.h"
static NSUInteger count;
#define VERIFY(...) do{count++;if(!(__VA_ARGS__)){NSLog(@"FAIL %s:%d %s",__FILE__,__LINE__,#__VA_ARGS__);exit(2);}}while(0)
int main(){@autoreleasepool{
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tf-git-prefs-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 NSDictionary *prior=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"GitGlobalSettings"];
 [TMCGitPreferences saveGlobal:@{@"name":@"Global",@"email":@"global@example.org",@"enabled":@YES,@"delay":@37,@"push":@YES}];
 VERIFY([[TMCGitPreferences effective:root][@"name"] isEqual:@"Global"]);VERIFY([[TMCGitPreferences effective:root][@"source"] isEqual:@"全局继承"]);VERIFY(![[TMCGitPreferences effective:root][@"push"] boolValue]);
 NSError *error=nil;VERIFY([TMCGitPreferences saveProject:@{@"override":@YES,@"name":@"Project",@"email":@"project@example.org",@"enabled":@NO,@"push":@YES,@"pushURL":@"https://github.com/a/b.git",@"pushBranch":@"main"} root:root error:&error]);VERIFY([[TMCGitPreferences effective:root][@"name"] isEqual:@"Project"]);VERIFY(![[TMCGitPreferences effective:root][@"enabled"] boolValue]);VERIFY([[TMCGitPreferences effective:root][@"source"] isEqual:@"项目覆盖"]);VERIFY([[TMCGitPreferences effective:root][@"delay"] intValue]==37);VERIFY([[TMCGitPreferences effective:root][@"push"] boolValue]);
 VERIFY([TMCGitPreferences saveProject:@{@"override":@NO,@"name":@"Stale"} root:root error:&error]);VERIFY([[TMCGitPreferences effective:root][@"name"] isEqual:@"Global"]);
 VERIFY([[TMCGitPreferences origin:@"https://GitHub.com/owner/repo.git"] isEqual:@"https://github.com"]);VERIFY([[TMCGitPreferences origin:@"https://git.example.org:8443/r"] isEqual:@"https://git.example.org:8443"]);VERIFY([[TMCGitPreferences repositoryKey:@"https://GitHub.com/a/b.git/"] isEqual:@"https://github.com/a/b"]);
 // A background Git operation owns the gate. UI must not block or overwrite it.
 dispatch_semaphore_t locked=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0),finished=dispatch_semaphore_create(0);
 dispatch_async(TMCGitService.queue,^{@autoreleasepool{TMCGitLease *hold __attribute__((objc_precise_lifetime))=[TMCGitLease acquire];dispatch_semaphore_signal(locked);dispatch_semaphore_wait(release,DISPATCH_TIME_FOREVER);}dispatch_semaphore_signal(finished);});
 dispatch_semaphore_wait(locked,DISPATCH_TIME_FOREVER);VERIFY([TMCGitLease tryWrite]==nil);VERIFY(![TMCGitPreferences saveProject:@{} root:root error:&error]);VERIFY([error.localizedDescription containsString:@"Git 正在处理"]);dispatch_semaphore_signal(release);dispatch_semaphore_wait(finished,DISPATCH_TIME_FOREVER);
 {TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];VERIFY(lease!=nil);TMCGitLease *nested __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];VERIFY(nested!=nil);}
 TMCGitService *g=[[TMCGitService alloc] initWithRoot:root];VERIFY([g initialize:nil]);[TMCGitLease setBuilding:YES root:root];error=nil;VERIFY([g status:&error]==nil);VERIFY([error.localizedDescription containsString:@"构建"]);[TMCGitLease setBuilding:NO root:root];VERIFY([g status:nil]!=nil);
 for(int i=0;i<105;i++)[TMCGitPreferences record:@{@"message":[NSString stringWithFormat:@"event %d",i]} root:root];VERIFY([TMCGitPreferences records:root].count==100);VERIFY([[TMCGitPreferences records:root][0][@"message"] isEqual:@"event 104"]);
 if(prior)[NSUserDefaults.standardUserDefaults setObject:prior forKey:@"GitGlobalSettings"];else[NSUserDefaults.standardUserDefaults removeObjectForKey:@"GitGlobalSettings"];
 printf("{\"checks\":%lu,\"result\":\"passed\"}\n",(unsigned long)count);
}}
