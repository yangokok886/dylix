#!/usr/bin/env python3
"""Run the actual file-mutation implementation against disposable local fixtures."""
from pathlib import Path
import subprocess,tempfile,json
R=Path(__file__).resolve().parents[1]
s=(R/'App/Studio.m').read_text()
def function(start,end):return s[s.index(start):s.index(end,s.index(start))]
helper=function('static BOOL ChangeProjectFile(', '@interface StudioFiles')
child=function('static NSString *Child(NSString *root, NSString *relative) {','\n',) # single-line actual helper
jsonwrite=function('static BOOL JSONWrite(NSDictionary *d, NSString *path, NSError **error) {','\n')
source='''#import <Foundation/Foundation.h>
#import "GitPreferences.h"
static void MarkSaved(NSString *root){}
'''+child+'\n'+jsonwrite+'\n'+helper+'''
int main(){@autoreleasepool{
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSFileManager *fm=NSFileManager.defaultManager;[fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 NSString *file=[root stringByAppendingPathComponent:@"Old.m"],*manifest=[root stringByAppendingPathComponent:@"MobileCompiler.json"];
 [@"int value = 1;" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
 JSONWrite(@{@"sources":@[@"Old.m"],@"forcedIncludes":@[@"Old.m"],@"prefixHeader":@"Old.m",@"name":@"Fixture"},manifest,nil);
 NSError *error=nil;NSMutableDictionary *r=[NSMutableDictionary new];
 r[@"rename"]=@(ChangeProjectFile(root,@"Old.m",@"New.m",&error));
 NSDictionary *(^config)(void)=^NSDictionary *{return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:manifest] options:0 error:nil];};
 r[@"referencesRenamed"]=@([config()[@"sources"] isEqual:@[@"New.m"]]&&[config()[@"forcedIncludes"] isEqual:@[@"New.m"]]&&[config()[@"prefixHeader"] isEqual:@"New.m"]);
 r[@"contentsPreserved"]=@([[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"New.m"] encoding:NSUTF8StringEncoding error:nil] isEqual:@"int value = 1;"]&&![fm fileExistsAtPath:file]);
 [@"existing" writeToFile:[root stringByAppendingPathComponent:@"Existing.m"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 r[@"duplicateRejected"]=@(!ChangeProjectFile(root,@"New.m",@"Existing.m",nil)&&[fm fileExistsAtPath:[root stringByAppendingPathComponent:@"New.m"]]);
 r[@"escapeRejected"]=@(!ChangeProjectFile(root,@"New.m",@"../escape.m",nil));
 NSData *valid=[NSData dataWithContentsOfFile:manifest];[@"{" writeToFile:manifest atomically:YES encoding:NSUTF8StringEncoding error:nil];
 r[@"invalidConfigPreservesFile"]=@(!ChangeProjectFile(root,@"New.m",nil,nil)&&[fm fileExistsAtPath:[root stringByAppendingPathComponent:@"New.m"]]);[valid writeToFile:manifest atomically:YES];
 r[@"delete"]=@(ChangeProjectFile(root,@"New.m",nil,&error));
 r[@"referencesRemoved"]=@([config()[@"sources"] count]==0&&[config()[@"forcedIncludes"] count]==0&&!config()[@"prefixHeader"]);
 r[@"onlyRequestedFileDeleted"]=@(![fm fileExistsAtPath:[root stringByAppendingPathComponent:@"New.m"]]&&[fm fileExistsAtPath:[root stringByAppendingPathComponent:@"Existing.m"]]);
 r[@"fixedNameRenameRejected"]=@(!ChangeProjectFile(root,@"MobileCompiler.json",@"Config.json",nil));
 BOOL ok=YES;for(NSNumber *value in r.allValues)ok&=value.boolValue;
 NSData *out=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil];puts([[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding].UTF8String);[fm removeItemAtPath:root error:nil];return ok?0:1;
}}
'''
with tempfile.TemporaryDirectory(prefix='tf-file-actions-') as d:
 p=Path(d);(p/'test.m').write_text(source)
 subprocess.run(['xcrun','--sdk','macosx','clang','-isysroot',subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip(),'-fobjc-arc','-fmodules','-fmodules-cache-path=/private/tmp/tmc-rules-module-cache','-fblocks','-I'+str(R/'App'),'-I'+str(R/'Vendor/libgit2/include'),'-framework','Foundation','-framework','Security','-framework','CoreFoundation',str(p/'test.m'),str(R/'App/GitService.m'),str(R/'build/git-macos/libgit2.a'),'-liconv','-o',str(p/'test')],check=True)
 result=subprocess.check_output([str(p/'test')],text=True);r=json.loads(result)
 out=R/'evidence/0.6.2-file-actions';out.mkdir(parents=True,exist_ok=True);(out/'mutations.json').write_text(result)
 print(f'{len(r)} file mutation checks passed')
