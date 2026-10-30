#import "ProjectSafety.h"

@implementation TMCLineIndex
- (void)update:(NSString *)text{NSMutableArray *starts=[NSMutableArray arrayWithObject:@0];NSUInteger offset=0;while(offset<text.length){NSRange next=[text rangeOfString:@"\n" options:NSLiteralSearch range:NSMakeRange(offset,text.length-offset)];if(next.location==NSNotFound)break;offset=next.location+1;[starts addObject:@(offset)];}_starts=starts;}
- (NSUInteger)lineAt:(NSUInteger)offset{NSUInteger low=0,high=self.starts.count;while(low<high){NSUInteger middle=(low+high)/2;if([self.starts[middle] unsignedIntegerValue]<=offset)low=middle+1;else high=middle;}return MAX((NSUInteger)1,low);}
@end

static BOOL Fail(NSError **error, NSInteger code, NSString *message){if(error)*error=[NSError errorWithDomain:@"TweakForge.Files" code:code userInfo:@{NSLocalizedDescriptionKey:message}];return NO;}
NSDictionary *TMCReadDraft(NSString *root){
 NSString *path=[root stringByAppendingPathComponent:@".studio-draft.json"];
 NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
 if(!a)return @{};
 NSData *data=[a[NSFileSize] unsignedLongLongValue]<=16*1024*1024?[NSData dataWithContentsOfFile:path]:nil;
 id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
 BOOL valid=[value isKindOfClass:NSDictionary.class]&&[value[@"file"] isKindOfClass:NSString.class]&&[value[@"text"] isKindOfClass:NSString.class];
 NSString *relative=valid?value[@"file"]:nil,*base=root.stringByResolvingSymlinksInPath;
 NSString *target=relative?[root stringByAppendingPathComponent:relative].stringByResolvingSymlinksInPath:nil;
 valid=valid&&!relative.isAbsolutePath&&[target hasPrefix:[base stringByAppendingString:@"/"]];
 if(valid&&value[@"base"]&&![value[@"base"] isKindOfClass:NSString.class])valid=NO;
 if(!valid){NSString *quarantine=[root stringByAppendingPathComponent:[@".studio-draft-invalid-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager moveItemAtPath:path toPath:quarantine error:nil];return @{};}
 return value;
}
BOOL TMCWriteDocument(NSString *path, NSData *expected, NSString *text, NSError **error){
 if(!path.length||!text)return Fail(error,1,@"文件路径或内容无效");
 __block BOOL ok=NO;__block NSError *failure=nil;NSError *coordination=nil;
 NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
 [coordinator coordinateWritingItemAtURL:[NSURL fileURLWithPath:path] options:0 error:&coordination byAccessor:^(NSURL *url){
  NSData *current=[NSData dataWithContentsOfURL:url options:0 error:&failure];
  if(!current)return;
  if(![current isEqual:expected]){Fail(&failure,409,@"磁盘文件已被其他操作修改，已保留双方内容。请选择处理方式。");return;}
  ok=[[text dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url options:NSDataWritingAtomic error:&failure];
 }];
 if(!ok&&error)*error=failure?:coordination?:[NSError errorWithDomain:@"TweakForge.Files" code:2 userInfo:@{NSLocalizedDescriptionKey:@"保存未完成"}];return ok;
}
static BOOL Excluded(NSString *relative,BOOL share){
 for(NSString *part in relative.pathComponents){
  if([@[@".git",@".svn",@".theos",@".build",@"build",@"DerivedData",@"packages",@"__MACOSX"] containsObject:part]||[part hasPrefix:@".studio-"])return YES;
  if(share&&([part hasPrefix:@".env"]||[@[@"credentials.json",@"auth.json"] containsObject:part.lowercaseString]))return YES;
 }
 NSString *ext=relative.pathExtension.lowercaseString;
 if([@[@"o",@"deb",@"tmp",@"swp"] containsObject:ext])return YES;
 if(share&&[@[@"p12",@"pfx",@"pem",@"key",@"mobileprovision"] containsObject:ext])return YES;
 return NO;
}
BOOL TMCCopyProject(NSString *root,NSString *destination,BOOL share,NSProgress *progress,void (^update)(NSProgress *),NSError **error){
 NSFileManager *fm=NSFileManager.defaultManager;NSMutableArray *files=[NSMutableArray new];
 NSDirectoryEnumerator *enumerator=[fm enumeratorAtPath:root];NSString *relative;unsigned long long bytes=0;
 while((relative=enumerator.nextObject)){
  if(progress.cancelled)return Fail(error,NSUserCancelledError,@"已取消准备项目");
  if(Excluded(relative,share)){[enumerator skipDescendants];continue;}
  NSDictionary *a=[fm attributesOfItemAtPath:[root stringByAppendingPathComponent:relative] error:error];if(!a)return NO;
  if([a[NSFileType] isEqual:NSFileTypeSymbolicLink])return Fail(error,3,[@"项目含链接，请先转换为普通文件：" stringByAppendingString:relative]);
  if([a[NSFileType] isEqual:NSFileTypeDirectory])continue;
  if(![a[NSFileType] isEqual:NSFileTypeRegular])return Fail(error,3,@"项目含特殊文件");
  bytes+=[a[NSFileSize] unsignedLongLongValue];[files addObject:relative];
 }
 progress.totalUnitCount=MAX(1,(int64_t)bytes);progress.completedUnitCount=0;if(update)update(progress);
 if(![fm createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:error])return NO;
 for(relative in files){
  if(progress.cancelled)return Fail(error,NSUserCancelledError,@"已取消准备项目");
  NSString *source=[root stringByAppendingPathComponent:relative],*target=[destination stringByAppendingPathComponent:relative];
  if(![fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]||![fm copyItemAtPath:source toPath:target error:error])return NO;
  progress.completedUnitCount+=[[fm attributesOfItemAtPath:target error:nil][NSFileSize] longLongValue];if(update)update(progress);
 }
 progress.completedUnitCount=progress.totalUnitCount;return YES;
}
void TMCPruneBuildCaches(NSString *documents,NSString *project,NSString *keeping){
 NSFileManager *fm=NSFileManager.defaultManager;NSMutableArray *builds=[NSMutableArray new];
 for(NSString *name in [fm contentsOfDirectoryAtPath:documents error:nil]){
  if(![name hasPrefix:@"Build-"])continue;NSString *path=[documents stringByAppendingPathComponent:name];
  id metadata=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@".studio-cache-owner.json"]]?:NSData.data options:0 error:nil];
  if([metadata isKindOfClass:NSDictionary.class]&&[metadata[@"project"] isEqual:project])[builds addObject:path];
 }
 [builds sortUsingComparator:^NSComparisonResult(NSString *a,NSString *b){return [[fm attributesOfItemAtPath:b error:nil][NSFileModificationDate] compare:[fm attributesOfItemAtPath:a error:nil][NSFileModificationDate]];}];
 NSString *lastSuccess=nil;for(NSString *path in builds){id report=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"report.json"]]?:NSData.data options:0 error:nil];if([report isKindOfClass:NSDictionary.class]&&[report[@"success"] boolValue]){lastSuccess=path;break;}}
 for(NSUInteger i=0;i<builds.count;i++)if(i>=5&&![builds[i] isEqual:keeping]&&![builds[i] isEqual:lastSuccess]){NSString *old=builds[i];NSDictionary *metadata=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[old stringByAppendingPathComponent:@".studio-cache-owner.json"]]?:NSData.data options:0 error:nil];NSString *snapshot=metadata[@"snapshot"];if([snapshot isKindOfClass:NSString.class]&&[snapshot.stringByDeletingLastPathComponent isEqual:documents]&&[snapshot.lastPathComponent hasPrefix:@"Snapshot-"])[fm removeItemAtPath:snapshot error:nil];[fm removeItemAtPath:old error:nil];}
}
