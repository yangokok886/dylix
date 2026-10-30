#import "AIPolicy.h"
#import "../Permissions/TFAIPolicy.h"
#import <CommonCrypto/CommonDigest.h>
static NSError *PolicyError(NSString *text){return [NSError errorWithDomain:@"TweakForge.AI.RuntimePolicy" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
static BOOL Fail(NSError **error,NSString *text){if(error)*error=PolicyError(text);return NO;}
static NSString *Text(id value){return [value isKindOfClass:NSString.class]?value:@"";}
static BOOL ReadTool(NSString *name){return [@[@"list_files",@"read_file",@"search_text",@"list_symbols",@"propose_patch",@"read_project_config",@"propose_config_change",@"read_diagnostics",@"list_artifacts",@"git_status",@"git_diff",@"git_history"] containsObject:name];}
static BOOL FullPreset(NSString *preset){return [@[@"full",@"full_push",@"full_download",@"full_network"] containsObject:preset];}
static BOOL KnownTool(NSString *name){return ReadTool(name)||[@[@"apply_approved_patch",@"create_file",@"request_delete",@"build_project",@"cancel_build",@"git_save_version",@"git_download_updates",@"git_upload",@"download_file",@"extract_archive"] containsObject:name];}
static NSString *Fingerprint(NSDictionary *plan){if(![NSJSONSerialization isValidJSONObject:plan])return nil;NSData *data=[NSJSONSerialization dataWithJSONObject:plan options:NSJSONWritingSortedKeys error:nil];if(!data||data.length>4*1024*1024)return nil;unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *value=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[value appendFormat:@"%02x",digest[i]];return value;}
@interface TFAIRuntimePolicy ()
@property(copy) NSString *root;
@property(copy) NSString *projectID;
@property(copy) NSString *sessionID;
@property(copy) NSString *preset;
@property(copy) NSArray<NSString *> *paths;
@property NSTimeInterval expiresAt;
@property BOOL revoked;
@property NSMutableDictionary<NSString *,NSNumber *> *grants;
@end
@implementation TFAIRuntimePolicy
- (instancetype)initWithRoot:(NSString *)root projectID:(NSString *)projectID sessionID:(NSString *)sessionID{if((self=[super init])){_root=root.stringByStandardizingPath.stringByResolvingSymlinksInPath;_projectID=[projectID copy];_sessionID=[sessionID copy];_preset=@"assisted";_paths=@[];_expiresAt=NSDate.date.timeIntervalSince1970+1800;_grants=[NSMutableDictionary new];}return self;}
- (BOOL)safePath:(NSString *)relative requireExisting:(BOOL)existing error:(NSError **)error{return [self safePath:relative requireExisting:existing allowDirectory:NO error:error];}
- (BOOL)safePath:(NSString *)relative requireExisting:(BOOL)existing allowDirectory:(BOOL)allowDirectory error:(NSError **)error{
 if(!TFAIAllowedRelativePath(relative))return Fail(error,@"凭据、缓存、隐藏控制文件及项目外路径不在工具权限范围");
 if(![relative isKindOfClass:NSString.class]||!relative.length||relative.length>1024||[relative hasPrefix:@"/"]||[relative containsString:@"\\"]||[relative rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return Fail(error,@"请选择项目内的具体相对文件路径");
 NSArray *parts=[relative componentsSeparatedByString:@"/"];for(NSString *part in parts)if(!part.length||[part isEqual:@"."]||[part isEqual:@".."]||[part rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*?[]{}"]].location!=NSNotFound)return Fail(error,@"权限范围不接受通配符或路径跳转");
 NSString *full=self.root;for(NSString *part in parts){full=[full stringByAppendingPathComponent:part];NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:full error:nil];if([attrs[NSFileType] isEqual:NSFileTypeSymbolicLink])return Fail(error,@"权限范围不接受符号链接");}
 NSString *resolved=full.stringByResolvingSymlinksInPath;if(![resolved hasPrefix:[self.root stringByAppendingString:@"/"]])return Fail(error,@"路径超出当前项目");BOOL directory=NO;BOOL exists=[NSFileManager.defaultManager fileExistsAtPath:full isDirectory:&directory];if((directory&&!allowDirectory)||(existing&&!exists))return Fail(error,@"权限范围须选择已存在的具体文件，目录不作为递归授权");if(!exists){BOOL parent=NO;if(![NSFileManager.defaultManager fileExistsAtPath:full.stringByDeletingLastPathComponent isDirectory:&parent]||!parent)return Fail(error,@"新文件的父目录不存在");}return YES;
}
- (BOOL)configurePreset:(NSString *)preset paths:(NSArray<NSString *> *)paths session:(NSString *)sessionID error:(NSError **)error{@synchronized(self){
 if(![@[@"ask",@"assisted",@"scoped",@"full",@"full_push",@"full_download",@"full_network"] containsObject:preset]||![sessionID isKindOfClass:NSString.class]||!sessionID.length||![paths isKindOfClass:NSArray.class])return Fail(error,@"权限配置格式有误");
 if(FullPreset(preset)){BOOL directory=NO;if(!self.projectID.length||!self.root.length||[self.root isEqual:@"/"]||![NSFileManager.defaultManager fileExistsAtPath:self.root isDirectory:&directory]||!directory||![self.root.stringByResolvingSymlinksInPath isEqual:self.root])return Fail(error,@"请先关联本机项目；完全访问仅授予该项目");}
 if([preset isEqual:@"scoped"]){if(!paths.count||paths.count>64)return Fail(error,@"自动构建模式需明确选择 1–64 个文件作为本会话范围");for(id path in paths)if(![self safePath:path requireExisting:YES error:error])return NO;}
 self.preset=preset;self.paths=[preset isEqual:@"scoped"]?[[NSOrderedSet orderedSetWithArray:paths] array]:@[];self.sessionID=sessionID;self.expiresAt=NSDate.date.timeIntervalSince1970+1800;self.revoked=NO;[self.grants removeAllObjects];return YES;
}}
- (NSString *)invalidPlan:(NSDictionary *)plan{
 if(self.revoked)return @"本会话权限已撤销，请重新选择权限后继续";
 if(NSDate.date.timeIntervalSince1970>=self.expiresAt)return @"会话权限已过期，请重新确认";
 if(FullPreset(self.preset)){BOOL directory=NO;if(![NSFileManager.defaultManager fileExistsAtPath:self.root isDirectory:&directory]||!directory||![self.root.stringByResolvingSymlinksInPath isEqual:self.root])return @"项目目录发生变化，请重新关联并确认权限";}
 if(![plan isKindOfClass:NSDictionary.class]||!Fingerprint(plan))return @"工具预览格式无效或超过大小限制";
 if(![plan[@"project"] isEqual:self.projectID]||![plan[@"session"] isEqual:self.sessionID])return @"预览不属于当前项目或会话";
 if(!Text(plan[@"id"]).length||![plan[@"request"] isKindOfClass:NSDictionary.class]||!KnownTool(Text(plan[@"request"][@"name"]))||![plan[@"request"][@"arguments"] isKindOfClass:NSDictionary.class])return @"仅接受本地注册工具的完整预览";
 id expiration=plan[@"expires"];if(![expiration isKindOfClass:NSNumber.class]||[expiration doubleValue]<=NSDate.date.timeIntervalSince1970)return @"工具预览已过期，请重新生成";
 if(plan[@"edits"]&&![plan[@"edits"] isKindOfClass:NSArray.class])return @"修改预览格式有误";
 for(id raw in plan[@"edits"]){if(![raw isKindOfClass:NSDictionary.class]||![raw[@"before"] isKindOfClass:NSString.class]||![raw[@"after"] isKindOfClass:NSString.class])return @"修改预览缺少原文和修改后内容";NSError *error=nil;if(![self safePath:raw[@"path"] requireExisting:NO error:&error])return error.localizedDescription;}
 NSDictionary *args=plan[@"request"][@"arguments"];for(NSString *key in @[@"path",@"destination"]){if(args[key]&&Text(args[key]).length){NSError *error=nil;BOOL directoryTool=[@[@"list_files",@"search_text",@"extract_archive"] containsObject:plan[@"request"][@"name"]];if(![self safePath:args[key] requireExisting:NO allowDirectory:directoryTool error:&error])return error.localizedDescription;}}
 return nil;
}
- (BOOL)destructiveReplacement:(NSDictionary *)edit{NSString *before=edit[@"before"],*after=edit[@"after"];if(!before.length)return NO;if(!after.length)return YES;NSUInteger prefix=0,common=MIN(before.length,after.length);while(prefix<common&&[before characterAtIndex:prefix]==[after characterAtIndex:prefix])prefix++;NSUInteger suffix=0;while(suffix<common-prefix&&[before characterAtIndex:before.length-1-suffix]==[after characterAtIndex:after.length-1-suffix])suffix++;return prefix+suffix<MIN((NSUInteger)24,MAX((NSUInteger)1,before.length/2));}
- (BOOL)separate:(NSDictionary *)plan{NSString *tool=plan[@"request"][@"name"];if([@[@"request_delete",@"git_save_version",@"git_download_updates",@"git_upload",@"download_file",@"extract_archive",@"cancel_build"] containsObject:tool])return YES;
 for(NSDictionary *edit in plan[@"edits"]){NSString *kind=Text(edit[@"kind"]),*path=Text(edit[@"path"]);if(![@[@"source",@"create"] containsObject:kind]||[@[@"MobileCompiler.json",@"control",@"Makefile",@"makefile",@"GNUmakefile"] containsObject:path.lastPathComponent]||[@[@"plist",@"json",@"yaml",@"yml",@"entitlements"] containsObject:path.pathExtension.lowercaseString]||[self destructiveReplacement:edit])return YES;}return NO;
}
- (NSDictionary *)decisionForPlan:(NSDictionary *)plan{@synchronized(self){NSString *invalid=[self invalidPlan:plan];if(invalid)return @{@"decision":@"denied",@"reason":invalid,@"preset":self.preset,@"readOnly":@NO,@"separateConfirmation":@NO};NSString *tool=plan[@"request"][@"name"];BOOL read=ReadTool(tool);if(read)return @{@"decision":@"allowed",@"reason":@"仅读取或生成提案，不修改项目",@"preset":self.preset,@"readOnly":@YES,@"separateConfirmation":@NO};BOOL separate=[self separate:plan];if(FullPreset(self.preset)){
  BOOL push=[tool isEqual:@"git_upload"],download=[@[@"download_file",@"extract_archive",@"git_download_updates"] containsObject:tool];
  BOOL allowedPush=[@[@"full_push",@"full_network"] containsObject:self.preset],allowedDownload=[@[@"full_download",@"full_network"] containsObject:self.preset];
  if((push&&!allowedPush)||(download&&!allowedDownload))return @{@"decision":@"needsApproval",@"reason":push?@"当前会话未允许自动上传，请核对远端后批准本次推送":@"当前会话未允许自动下载或解压，请核对具体来源与目标",@"preset":self.preset,@"readOnly":@NO,@"separateConfirmation":@YES};
  return @{@"decision":@"allowed",@"reason":@"用户已授予当前项目本会话权限；仍校验工具预览、路径、源文件与备份",@"preset":self.preset,@"readOnly":@NO,@"separateConfirmation":@NO};
 }if([self.preset isEqual:@"scoped"]){for(NSDictionary *edit in plan[@"edits"])if(![self.paths containsObject:edit[@"path"]])return @{@"decision":@"denied",@"reason":@"修改目标不在用户选择的会话范围内，请重新选择范围",@"preset":self.preset,@"readOnly":@NO,@"separateConfirmation":@(separate)};for(NSString *path in self.paths)if(![self safePath:path requireExisting:YES error:nil])return @{@"decision":@"denied",@"reason":@"已选择的权限范围发生变化，请重新确认",@"preset":self.preset,@"readOnly":@NO,@"separateConfirmation":@NO};if([tool isEqual:@"build_project"])return @{@"decision":@"allowed",@"reason":@"用户已允许本会话在当前项目中自动构建；源码修改仍须预览",@"preset":self.preset,@"readOnly":@NO,@"separateConfirmation":@NO};}
 return @{@"decision":@"needsApproval",@"reason":separate?@"此操作须独立明确确认，不接受会话宽泛授权":@"请先核对具体操作及红绿差异，再批准本次请求",@"preset":self.preset,@"readOnly":@NO,@"separateConfirmation":@(separate)};
}}
- (BOOL)grantReviewedPlan:(NSDictionary *)plan session:(NSString *)sessionID error:(NSError **)error{@synchronized(self){if(![sessionID isEqual:self.sessionID])return Fail(error,@"批准会话已变化");NSDictionary *decision=[self decisionForPlan:plan];if([decision[@"decision"] isEqual:@"denied"])return Fail(error,decision[@"reason"]);if([decision[@"separateConfirmation"] boolValue])return Fail(error,@"此操作需要独立操作确认，不可使用源码预览授权");NSString *tool=plan[@"request"][@"name"];if(![@[@"apply_approved_patch",@"create_file",@"build_project"] containsObject:tool])return Fail(error,@"此工具不使用源码预览授权");if(![tool isEqual:@"build_project"]&&![plan[@"edits"] count])return Fail(error,@"源码预览为空");NSString *hash=Fingerprint(plan);self.grants[hash]=@(MIN(self.expiresAt,MIN([plan[@"expires"] doubleValue],NSDate.date.timeIntervalSince1970+300)));return YES;}}
- (BOOL)consumeReviewedPlan:(NSDictionary *)plan error:(NSError **)error{@synchronized(self){NSString *hash=Fingerprint(plan);NSNumber *expiry=hash?self.grants[hash]:nil;if(hash)[self.grants removeObjectForKey:hash];if(!expiry||expiry.doubleValue<=NSDate.date.timeIntervalSince1970)return Fail(error,@"批准不存在、已使用或已过期，请重新预览");NSDictionary *decision=[self decisionForPlan:plan];if([decision[@"decision"] isEqual:@"denied"]||[decision[@"separateConfirmation"] boolValue])return Fail(error,decision[@"reason"]);return YES;}}
- (void)revoke{@synchronized(self){self.revoked=YES;self.expiresAt=0;[self.grants removeAllObjects];}}
@end
