#import "../App/AI/AIContracts.h"
static int checks=0,failures=0;
static void Check(BOOL pass,NSString *name){checks++;if(!pass){failures++;fprintf(stderr,"FAIL %s\n",name.UTF8String);}else printf("PASS %s\n",name.UTF8String);}
int main(){@autoreleasepool{
 NSString *project=[@"fixture-" stringByAppendingString:NSUUID.UUID.UUIDString];NSMutableDictionary *session=[TFAISessions create:project title:@"fixture"];
 Check([TFAISessions sessions:project].count==1,@"create persisted");
 session[@"messages"]=@[@{@"role":@"user",@"content":@"test"}];session[@"state"]=@"waitingApproval";session[@"grants"]=@[@"write"];session[@"secret"]=@"dummy";
 NSError *e=nil;Check([TFAISessions save:session project:project error:&e],@"atomic save");
 NSDictionary *restored=[TFAISessions sessions:project].firstObject;Check([restored[@"state"] isEqual:@"interrupted"],@"approval not resumed");Check(!restored[@"grants"]&&!restored[@"secret"],@"grants and top-level secrets excluded");
 Check([restored[@"messages"] count]==1,@"messages restored");session[@"title"]=@"renamed";[TFAISessions save:session project:project error:nil];Check([[[TFAISessions sessions:project].firstObject objectForKey:@"title"] isEqual:@"renamed"],@"rename persisted");
 Check([TFAISessions sessions:@"../bad"].count==0,@"invalid project rejected");
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:project];NSFileManager *fm=NSFileManager.defaultManager;[fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 [@"int x;" writeToFile:[root stringByAppendingPathComponent:@"Main.m"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 NSArray *files=[TFAISessions contextForPaths:@[@"Main.m"] root:root error:&e];Check(files.count==1&&[files.firstObject[@"bytes"] integerValue]==6,@"UTF8 source manifest exact");
 e=nil;Check([TFAISessions contextForPaths:@[@"../outside"] root:root error:&e].count==0&&e,@"path traversal rejected");
 [fm createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"escape"] withDestinationPath:@"/etc" error:nil];e=nil;Check([TFAISessions contextForPaths:@[@"escape/passwd"] root:root error:&e].count==0&&e,@"symlink escape rejected");
 [@"KEY=placeholder" writeToFile:[root stringByAppendingPathComponent:@".env"] atomically:YES encoding:NSUTF8StringEncoding error:nil];e=nil;Check([TFAISessions contextForPaths:@[@".env"] root:root error:&e].count==0&&e,@"sensitive filename rejected");
 NSString *fake=[@"github_pat_" stringByAppendingString:[@"" stringByPaddingToLength:50 withString:@"x" startingAtIndex:0]];[fake writeToFile:[root stringByAppendingPathComponent:@"Config.m"] atomically:YES encoding:NSUTF8StringEncoding error:nil];e=nil;Check([TFAISessions contextForPaths:@[@"Config.m"] root:root error:&e].count==0&&e,@"credential body rejected");
 [[NSMutableData dataWithLength:300*1024] writeToFile:[root stringByAppendingPathComponent:@"Large.m"] atomically:YES];e=nil;Check([TFAISessions contextForPaths:@[@"Large.m"] root:root error:&e].count==0&&e,@"oversize rejected not truncated");
 [fm removeItemAtPath:[root stringByAppendingPathComponent:@"Large.m"] error:nil];[fm removeItemAtPath:[root stringByAppendingPathComponent:@"Config.m"] error:nil];e=nil;Check([TFAISessions contextForPaths:@[@"Main.m",@"Main.m"] root:root error:&e].count==1,@"duplicate attachments coalesced");
 [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"build"] withIntermediateDirectories:YES attributes:nil error:nil];[@"output" writeToFile:[root stringByAppendingPathComponent:@"build/a.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];e=nil;files=[TFAISessions contextForPaths:@[@"."] root:root error:&e];Check(files.count==1&&!e,@"directory excludes build hidden and symlink");
 [TFAISessions remove:session[@"id"] project:project];Check([TFAISessions sessions:project].count==0,@"delete conversation");Check([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"Main.m"]],@"delete does not revert source");
 [fm removeItemAtPath:root error:nil];printf("%d checks, %d failures\n",checks,failures);return failures?1:0;
}}
