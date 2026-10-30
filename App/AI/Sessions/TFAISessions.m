#import "../AIV2Contracts.h"
#import "../Core/TFAIRecovery.h"
#import <TargetConditionals.h>

static NSError *AIStoreError(NSString *message) { return [NSError errorWithDomain:@"TFAISessions" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
static BOOL AIIdentifier(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !value.length || value.length>128) return NO;
    return [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"] invertedSet]].location==NSNotFound;
}
static NSString *AIStoreRoot(NSString *project) {
    if (!AIIdentifier(project)) return nil;
    NSString *base=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
    return [[base stringByAppendingPathComponent:@"TweakForgeAI/Sessions"] stringByAppendingPathComponent:project];
}
static BOOL AIExcluded(NSString *relative) {
    NSSet *dirs=[NSSet setWithArray:@[@".git",@".theos",@"build",@"Build",@"DerivedData",@"Frameworks",@"node_modules",@"Caches",@"tmp",@".ssh"]];
    for(NSString *part in relative.pathComponents) {
        if ([dirs containsObject:part] || [part hasPrefix:@".studio-"] || [part hasPrefix:@".env"] || [part hasPrefix:@".ai-"]) return YES;
        NSString *lower=part.lowercaseString;
        if ([lower containsString:@"credential"] || [lower containsString:@"secret"] || [lower containsString:@"token"] || [lower isEqual:@"id_rsa"] || [lower isEqual:@"id_ed25519"])return YES;
    }
    return [@[@"p12",@"pfx",@"key",@"pem",@"cer",@"mobileprovision",@"ipa",@"deb",@"dylib",@"a",@"o",@"zip",@"7z",@"rar",@"png",@"jpg",@"jpeg",@"gif",@"heic",@"pdf",@"xcassets"] containsObject:relative.pathExtension.lowercaseString];
}
static BOOL AISensitiveText(NSString *text) {
    // Content sent to a provider must not accidentally contain common credential formats.
    NSString *pattern=@"(?i)(github_pat_[a-z0-9_]{12,}|gh[pousr]_[a-z0-9]{20,}|sk-(?:proj-|ant-)?[a-z0-9_-]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|authorization[\\\"'\\s:]+bearer[\\s]+[a-z0-9._-]{12,})";
    return [[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil] firstMatchInString:text options:0 range:NSMakeRange(0,text.length)]!=nil;
}
static NSString *SessionPath(NSString *scope,NSString *identifier) {NSString *root=AIStoreRoot(scope);return root&&AIIdentifier(identifier)?[root stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"json"]]:nil;}
static NSString *SummaryPath(NSString *scope,NSString *identifier) {return [[AIStoreRoot(scope) stringByAppendingPathComponent:@"index"] stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"json"]];}
static NSString *Tombstone(NSString *scope,NSString *identifier){return [[AIStoreRoot(scope) stringByAppendingPathComponent:@"deleted"] stringByAppendingPathComponent:identifier];}
static BOOL WriteJSON(id value,NSString *path,NSError **error) {
 if(!path||![NSJSONSerialization isValidJSONObject:value]){if(error)*error=AIStoreError(@"会话数据格式有误");return NO;}
 NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:error];if(!data)return NO;
 if(![NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return NO;
 BOOL ok=[data writeToFile:path options:NSDataWritingAtomic error:error];if(ok){[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
#if TARGET_OS_IPHONE
 [NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:path error:nil];
#endif
 }return ok;
}
static id ReadJSON(NSString *path){NSDictionary *attrs=path?[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil]:nil;if(!attrs||[attrs fileSize]>33*1024*1024)return nil;NSData *data=[NSData dataWithContentsOfFile:path];return data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil]:nil;}
static NSMutableSet *LiveRuns(void){static NSMutableSet *runs;static dispatch_once_t once;dispatch_once(&once,^{runs=[NSMutableSet new];});return runs;}
static NSString *LiveKey(NSString *project,NSString *session){return [@[project?:@"general",session?:@""] componentsJoinedByString:@"\n"];}
BOOL TFAIHasLiveRuns(void){@synchronized(LiveRuns()){return LiveRuns().count>0;}}
BOOL TFAISessionHasLiveRun(NSString *project,NSString *session){@synchronized(LiveRuns()){return [LiveRuns() containsObject:LiveKey(project,session)];}}
void TFAISetSessionLiveRun(NSString *project,NSString *session,BOOL active){@synchronized(LiveRuns()){if(active)[LiveRuns() addObject:LiveKey(project,session)];else[LiveRuns() removeObject:LiveKey(project,session)];}}
static NSMutableDictionary *Normalize(id obj,NSString *scope){
 if(![obj isKindOfClass:NSDictionary.class]||!AIIdentifier(obj[@"id"])||![obj[@"messages"] isKindOfClass:NSArray.class]||[obj[@"schemaVersion"] integerValue]>2)return nil;
 NSMutableDictionary *record=[obj mutableCopy];record[@"schemaVersion"]=@2;record[@"storageProjectID"]=scope;
 if(![record[@"title"] isKindOfClass:NSString.class])record[@"title"]=@"会话";
 if(![record[@"updatedAt"] isKindOfClass:NSNumber.class])record[@"updatedAt"]=@0;
 for(NSString *key in @[@"grants",@"approval",@"apiKey",@"secret",@"Authorization"])[record removeObjectForKey:key];
 if(!TFAISessionHasLiveRun(scope,record[@"id"])&&[@[@"streaming",@"waitingApproval",@"running"] containsObject:record[@"state"]]){NSDictionary *checkpoint=[record[@"runtimeCheckpoint"] isKindOfClass:NSDictionary.class]?record[@"runtimeCheckpoint"]:nil;if([checkpoint[@"messages"] isKindOfClass:NSArray.class])record[@"messages"]=TFAIRecoveryTranscript(checkpoint[@"messages"]);NSMutableArray *records=[NSMutableArray new];for(NSDictionary *item in record[@"processRecords"]){NSMutableDictionary *row=[item mutableCopy];if([@[@"requested",@"running",@"waitingApproval",@"approved"] containsObject:row[@"status"]]){row[@"status"]=@"interrupted";row[@"summary"]=@"中断时未收到完成记录 · 结果待核对";if(!row[@"duration"]&&row[@"startedAt"])row[@"duration"]=@(MAX(0,[checkpoint[@"savedAt"] doubleValue]-[row[@"startedAt"] doubleValue]));}[records addObject:row];}if(record[@"processRecords"])record[@"processRecords"]=records;record[@"recoveryAvailable"]=@YES;record[@"state"]=@"interrupted";record[@"notice"]=@"上次处理已中断，已恢复保存的记录。菜单中可继续分析；未完成工具的结果需先核对，不自动重复执行。";}
 return record;
}
static NSDictionary *MakeSummary(NSDictionary *record,NSString *scope){
 NSMutableDictionary *summary=[NSMutableDictionary new];for(NSString *key in @[@"id",@"title",@"updatedAt",@"createdAt",@"pinned",@"projectName",@"projectRoot",@"associatedProjectID",@"state",@"mode"]){id v=record[key];if(v)summary[key]=v;}
 summary[@"storageProjectID"]=scope;summary[@"schemaVersion"]=@2;summary[@"messageCount"]=@([record[@"messages"] count]);
 NSString *preview=@"尚未发送消息";for(NSDictionary *m in [record[@"messages"] reverseObjectEnumerator])if([m isKindOfClass:NSDictionary.class]&&[@[@"assistant",@"user"] containsObject:m[@"role"]]&&[m[@"content"] isKindOfClass:NSString.class]&&[m[@"content"] length]){preview=m[@"content"];NSRange context=[preview rangeOfString:@"<project_context>"];if(context.location!=NSNotFound)preview=[preview substringToIndex:context.location];break;}
 preview=[[preview componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@" "];if(preview.length>180)preview=[preview substringToIndex:180];summary[@"summary"]=preview;return summary;
}
static NSArray *Sorted(NSArray *items){return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){BOOL ap=[a[@"pinned"] boolValue],bp=[b[@"pinned"] boolValue];if(ap!=bp)return ap?NSOrderedAscending:NSOrderedDescending;return [b[@"updatedAt"] compare:a[@"updatedAt"]];}];}
@implementation TFAISessions
+ (NSArray<NSDictionary *> *)sessions:(NSString *)projectID {
 @synchronized(self){NSMutableArray *records=[NSMutableArray new];for(NSDictionary *summary in [self summaries:projectID]){NSDictionary *record=[self loadSession:summary[@"id"] project:projectID];if(record)[records addObject:record];}return records;}
}
+ (NSMutableDictionary *)create:(NSString *)projectID title:(NSString *)title {
 NSMutableDictionary *record=[@{@"schemaVersion":@2,@"id":NSUUID.UUID.UUIDString,@"storageProjectID":projectID?:@"general",@"title":title.length?title:@"新会话",@"messages":@[],@"state":@"idle",@"createdAt":@(NSDate.date.timeIntervalSince1970),@"updatedAt":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
 [self save:record project:projectID error:nil];return record;
}
+ (BOOL)save:(NSDictionary *)session project:(NSString *)projectID error:(NSError **)error {
 @synchronized(self){NSString *path=SessionPath(projectID,session[@"id"]);if(!path||![session[@"messages"] isKindOfClass:NSArray.class]){if(error)*error=AIStoreError(@"会话标识或消息格式有误");return NO;}
 if([NSFileManager.defaultManager fileExistsAtPath:Tombstone(projectID,session[@"id"])]){if(error)*error=AIStoreError(@"会话已删除，请创建新会话；旧回调不会恢复删除记录");return NO;}
 NSMutableDictionary *safe=[session mutableCopy];NSDictionary *existing=ReadJSON(path);if([existing isKindOfClass:NSDictionary.class]&&[existing[@"metadataRevision"] unsignedLongLongValue]>[safe[@"metadataRevision"] unsignedLongLongValue]){for(NSString *key in @[@"title",@"pinned",@"projectName",@"projectRoot",@"associatedProjectID",@"metadataRevision"]){if(existing[key])safe[key]=existing[key];else[safe removeObjectForKey:key];}}
 safe[@"schemaVersion"]=@2;safe[@"storageProjectID"]=projectID;safe[@"updatedAt"]=@(NSDate.date.timeIntervalSince1970);
 for(NSString *key in @[@"grants",@"approval",@"apiKey",@"secret",@"Authorization"])[safe removeObjectForKey:key];
 NSData *data=[NSJSONSerialization dataWithJSONObject:safe options:0 error:error];if(!data)return NO;if(data.length>32*1024*1024){if(error)*error=AIStoreError(@"会话已超过 32 MB，请新建会话");return NO;}
 if(!WriteJSON(safe,path,error))return NO;
 // Metadata is a rebuildable cache; payload remains authoritative if index write is interrupted.
 WriteJSON(MakeSummary(safe,projectID),SummaryPath(projectID,session[@"id"]),nil);return YES;}
}
+ (void)remove:(NSString *)sessionID project:(NSString *)projectID {
 @synchronized(self){NSString *path=SessionPath(projectID,sessionID);if(!path)return;NSString *marker=Tombstone(projectID,sessionID);[NSFileManager.defaultManager createDirectoryAtPath:marker.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];[@"deleted" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];[NSFileManager.defaultManager removeItemAtPath:path error:nil];[NSFileManager.defaultManager removeItemAtPath:SummaryPath(projectID,sessionID) error:nil];}
}
+ (NSArray<NSDictionary *> *)contextForPaths:(NSArray<NSString *> *)paths root:(NSString *)root error:(NSError **)error {
    NSString *base=root.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    NSMutableOrderedSet *selected=[NSMutableOrderedSet new];NSFileManager *fm=NSFileManager.defaultManager;
    NSString *prefix=[base stringByAppendingString:@"/"];
    for(id raw in paths) {
        if(![raw isKindOfClass:NSString.class]){if(error)*error=AIStoreError(@"附件路径格式有误");return @[];}
        NSString *p=[raw isAbsolutePath]?raw:[base stringByAppendingPathComponent:raw];p=p.stringByStandardizingPath;
        NSString *resolved=p.stringByResolvingSymlinksInPath;
        if(![resolved hasPrefix:prefix]&&![resolved isEqual:base]){if(error)*error=AIStoreError(@"所选附件超出项目范围");return @[];}
        NSString *rel=[resolved isEqual:base]?@"":[resolved substringFromIndex:prefix.length];
        if(AIExcluded(rel)){if(error)*error=AIStoreError([NSString stringWithFormat:@"已排除敏感文件或构建产物：%@",rel]);return @[];}
        BOOL dir=NO;if(![fm fileExistsAtPath:resolved isDirectory:&dir]){if(error)*error=AIStoreError(@"所选附件已不存在");return @[];}
        if(!dir){[selected addObject:resolved];continue;}
        NSDirectoryEnumerator *en=[fm enumeratorAtURL:[NSURL fileURLWithPath:resolved isDirectory:YES] includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *url,NSError *e){return NO;}];
        for(NSURL *url in en){NSString *candidate=url.path;NSString *r=[candidate substringFromIndex:prefix.length];NSNumber *sym=nil,*isdir=nil;[url getResourceValue:&sym forKey:NSURLIsSymbolicLinkKey error:nil];[url getResourceValue:&isdir forKey:NSURLIsDirectoryKey error:nil];if(sym.boolValue||AIExcluded(r)){[en skipDescendants];continue;}if(!isdir.boolValue)[selected addObject:candidate];if(selected.count>80){if(error)*error=AIStoreError(@"附件超过 80 个文件，请缩小范围");return @[];}}
    }
    if(selected.count>80){if(error)*error=AIStoreError(@"附件超过 80 个文件，请缩小范围");return @[];}
    NSMutableArray *result=[NSMutableArray new];NSUInteger total=0;
    for(NSString *file in selected){NSDictionary *attrs=[fm attributesOfItemAtPath:file error:error];if(!attrs)return @[];if([attrs fileSize]>256*1024){if(error)*error=AIStoreError([NSString stringWithFormat:@"%@ 超过单文件 256 KB，请选取较小的上下文",file.lastPathComponent]);return @[];}
        NSData *data=[NSData dataWithContentsOfFile:file options:0 error:error];if(!data)return @[];
        total+=data.length;if(total>768*1024){if(error)*error=AIStoreError(@"附件总量超过 768 KB，请减少附件；内容未截断");return @[];}
        NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if(!text||[text rangeOfString:[NSString stringWithFormat:@"%C",(unichar)0]].location!=NSNotFound){if(error)*error=AIStoreError([NSString stringWithFormat:@"%@ 不是 UTF-8 文本，请通过图片入口添加图片",file.lastPathComponent]);return @[];}
        if(AISensitiveText(text)){if(error)*error=AIStoreError([NSString stringWithFormat:@"%@ 含疑似密钥，已停止附加",file.lastPathComponent]);return @[];}
        [result addObject:@{@"path":[file substringFromIndex:prefix.length],@"content":text,@"bytes":@(data.length),@"kind":@"text"}];
    }return result;
}
@end

@implementation TFAISessions (V2)
+ (NSMutableDictionary *)loadSession:(NSString *)identifier project:(NSString *)scope {
 @synchronized(self){NSString *path=SessionPath(scope,identifier);if(!path||[NSFileManager.defaultManager fileExistsAtPath:Tombstone(scope,identifier)])return nil;return Normalize(ReadJSON(path),scope);}
}
+ (NSArray<NSDictionary *> *)summaries:(NSString *)scope {
 @synchronized(self){NSMutableArray *all=[NSMutableArray new];NSString *base=[AIStoreRoot(@"general") stringByDeletingLastPathComponent];NSArray *scopes=scope?@[scope]:[NSFileManager.defaultManager contentsOfDirectoryAtPath:base error:nil];
 for(NSString *project in scopes){NSString *root=AIStoreRoot(project);if(!root)continue;for(NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil]){if(![file.pathExtension isEqual:@"json"])continue;NSString *identifier=file.stringByDeletingPathExtension;if(!AIIdentifier(identifier)||[NSFileManager.defaultManager fileExistsAtPath:Tombstone(project,identifier)])continue;NSString *payload=[root stringByAppendingPathComponent:file],*index=SummaryPath(project,identifier);NSDictionary *payloadAttrs=[NSFileManager.defaultManager attributesOfItemAtPath:payload error:nil],*indexAttrs=[NSFileManager.defaultManager attributesOfItemAtPath:index error:nil];id summary=nil;if(indexAttrs&&[indexAttrs[NSFileModificationDate] compare:payloadAttrs[NSFileModificationDate]]!=NSOrderedAscending)summary=ReadJSON(index);
 if(![summary isKindOfClass:NSDictionary.class]||![summary[@"schemaVersion"] isEqual:@2]||![summary[@"id"] isEqual:identifier]||![summary[@"updatedAt"] isKindOfClass:NSNumber.class]||![summary[@"title"] isKindOfClass:NSString.class]){NSDictionary *record=Normalize(ReadJSON(payload),project);if(!record)continue;summary=MakeSummary(record,project);WriteJSON(summary,index,nil);}
 NSMutableDictionary *display=[summary mutableCopy];if(!TFAISessionHasLiveRun(project,identifier)&&[@[@"streaming",@"waitingApproval",@"running"] containsObject:display[@"state"]])display[@"state"]=@"interrupted";[all addObject:display];}}
 return Sorted(all);}
}
+ (BOOL)saveMetadata:(NSDictionary *)metadata identifier:(NSString *)identifier project:(NSString *)scope error:(NSError **)error {
 @synchronized(self){NSMutableDictionary *record=[self loadSession:identifier project:scope];if(!record){if(error)*error=AIStoreError(@"会话已删除或不存在");return NO;}
 NSSet *allowed=[NSSet setWithArray:@[@"title",@"pinned",@"projectName",@"projectRoot",@"associatedProjectID",@"draft",@"draftText",@"attachments",@"pendingAttachments",@"scrollOffset",@"folds",@"collapsed",@"mode",@"selectedConnection",@"selectedModel",@"followBottom"]];
 for(NSString *key in metadata){if(![allowed containsObject:key]){if(error)*error=AIStoreError(@"此字段不属于会话显示设置");return NO;}id value=metadata[key];if([@[@"title",@"projectName",@"projectRoot",@"associatedProjectID",@"draft",@"draftText",@"mode",@"selectedModel"] containsObject:key]&&value!=NSNull.null&&![value isKindOfClass:NSString.class]){if(error)*error=AIStoreError(@"会话文字字段格式有误");return NO;}if([@[@"pinned",@"scrollOffset",@"followBottom"] containsObject:key]&&value!=NSNull.null&&![value isKindOfClass:NSNumber.class]){if(error)*error=AIStoreError(@"会话状态字段格式有误");return NO;}if(value==NSNull.null)[record removeObjectForKey:key];else record[key]=value;}
 record[@"metadataRevision"]=@([record[@"metadataRevision"] unsignedLongLongValue]+1);return [self save:record project:scope error:error];}
}
@end
