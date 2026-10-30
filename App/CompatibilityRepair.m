#import "CompatibilityRepair.h"
#import <TargetConditionals.h>
static NSString *RepairPath(NSString *root,NSString *relative){
 if(![relative isKindOfClass:NSString.class]||!relative.length||[relative hasPrefix:@"/"])return nil;
 for(NSString *part in relative.pathComponents)if([part isEqual:@".."]||[part isEqual:@"."])return nil;
 NSString *base=root.stringByStandardizingPath.stringByResolvingSymlinksInPath,*path=[[base stringByAppendingPathComponent:relative] stringByStandardizingPath];
 if(![path.stringByResolvingSymlinksInPath hasPrefix:[base stringByAppendingString:@"/"]])return nil;
 return path;
}
static BOOL RepairError(NSError **error,NSString *message){if(error)*error=[NSError errorWithDomain:@"CompatibilityRepair" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];return NO;}
NSArray *TMCCompatibilityRules(void) {
 static NSArray *rules;static dispatch_once_t once;dispatch_once(&once,^{
 NSString *path=[NSBundle.mainBundle pathForResource:@"rules" ofType:@"json" inDirectory:@"CompatibilityRules"];
#if !TARGET_OS_IPHONE
 if(!path)path=NSProcessInfo.processInfo.environment[@"TMC_RULES_PATH"];
#endif
 NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;id json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
 rules=[json isKindOfClass:NSDictionary.class]&&[json[@"schemaVersion"] isEqual:@1]&&[json[@"rules"] isKindOfClass:NSArray.class]?json[@"rules"]:@[];
 });return rules;
}
static NSDictionary *Rule(NSString *identifier){for(NSDictionary *r in TMCCompatibilityRules())if([r[@"id"] isEqual:identifier])return r;return nil;}
static BOOL RuleMatches(NSDictionary *rule,NSString *message){
 NSDictionary *conditions=rule[@"diagnosticConditions"];NSStringCompareOptions options=[conditions[@"caseSensitive"] boolValue]?0:NSCaseInsensitiveSearch;
 for(NSString *part in conditions[@"allContains"])if([message rangeOfString:part options:options].location==NSNotFound)return NO;
 for(NSString *part in conditions[@"noneContains"])if([message rangeOfString:part options:options].location!=NSNotFound)return NO;
 BOOL matched=NO;for(NSString *part in conditions[@"anyContains"])if([message rangeOfString:part options:options].location!=NSNotFound){matched=YES;break;}
 for(NSString *pattern in conditions[@"anyRegex"]){NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:pattern options:options?NSRegularExpressionCaseInsensitive:0 error:nil];if([rx firstMatchInString:message options:0 range:NSMakeRange(0,message.length)]){matched=YES;break;}}
 return matched;
}
static BOOL Enabled(NSString *identifier){NSDictionary *r=Rule(identifier);return [r[@"handling"][@"automaticEnabled"] boolValue]&&[r[@"validation"][@"status"] isEqual:@"verified"];}
static NSDictionary *AnnotatedEdit(NSDictionary *edit,NSString *identifier,NSString *kind,NSString *file,NSUInteger ordinal){
 NSMutableDictionary *r=[edit mutableCopy];NSDictionary *rule=Rule(identifier);r[@"ruleID"]=identifier;r[@"ruleName"]=rule[@"name"]?:identifier;r[@"sources"]=rule[@"sources"]?:@[];r[@"kind"]=kind;r[@"id"]=[NSString stringWithFormat:@"%@:%@:%lu",identifier,file,(unsigned long)ordinal];return r;
}
// Clang's positions are 1-based UTF-8 byte columns, with a half-open end.
static NSUInteger BytePosition(NSData *data,NSUInteger line,NSUInteger column){if(!line||!column)return NSNotFound;const unsigned char *bytes=data.bytes;NSUInteger start=0,current=1;while(current<line&&start<data.length){if(bytes[start++]=='\n')current++;}if(current!=line)return NSNotFound;NSUInteger end=start;while(end<data.length&&bytes[end]!='\n')end++;return column-1<=end-start?start+column-1:NSNotFound;}
static NSString *DecodeClangString(NSString *quoted){
 // JSON is a subset of Clang's quoting; reject octal/unknown escapes rather than misdecode paths.
 NSData *data=[[NSString stringWithFormat:@"[%@]",quoted] dataUsingEncoding:NSUTF8StringEncoding];NSArray *a=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];return [a isKindOfClass:NSArray.class]&&[a.firstObject isKindOfClass:NSString.class]?a.firstObject:nil;
}
NSArray *TMCParseFixIts(NSString *log,NSString *root,NSString *snapshot){
 NSMutableArray *result=[NSMutableArray new];NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"^fix-it:(\"(?:[^\"\\\\]|\\\\.)*\"):\\{([0-9]+):([0-9]+)-([0-9]+):([0-9]+)\\}:(\"(?:[^\"\\\\]|\\\\.)*\")$" options:0 error:nil];
 NSMutableArray *group=[NSMutableArray new];NSString *message=@"";__block BOOL macro=NO;__block NSUInteger hintCount=0;
 void (^flush)(void)=^{if(group.count==1&&hintCount==1&&!macro)[result addObject:group.firstObject];[group removeAllObjects];hintCount=0;};
 for(NSString *line in [log componentsSeparatedByString:@"\n"]){
  if([line containsString:@"expanded from macro"]){macro=YES;continue;}
  if([line rangeOfString:@": (?:fatal error|error|warning|note):" options:NSRegularExpressionSearch].location!=NSNotFound){flush();message=line;macro=NO;}
  if([line containsString:@"expanded from macro"])macro=YES;
  if([line hasPrefix:@"fix-it:"])hintCount++;NSTextCheckingResult *m=[rx firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];if(!m)continue;
  NSString *path=DecodeClangString([line substringWithRange:[m rangeAtIndex:1]]),*replacement=DecodeClangString([line substringWithRange:[m rangeAtIndex:6]]);NSString *relative=nil;
  for(NSString *base in @[snapshot?:@"",root?:@""])if(base.length&&[path hasPrefix:[base stringByAppendingString:@"/"]]){relative=[path substringFromIndex:base.length+1];break;}
  if(!relative||!RepairPath(root,relative)||!replacement)continue;
  [group addObject:@{@"file":relative,@"path":path,@"line":@([[line substringWithRange:[m rangeAtIndex:2]] integerValue]),@"column":@([[line substringWithRange:[m rangeAtIndex:3]] integerValue]),@"endLine":@([[line substringWithRange:[m rangeAtIndex:4]] integerValue]),@"endColumn":@([[line substringWithRange:[m rangeAtIndex:5]] integerValue]),@"replacement":replacement,@"message":message,@"severity":@"fix-it",@"compilerFixIt":@YES}];
 }flush();return result;
}
static NSArray *HeaderCandidates(NSString *root,NSString *header){
 if(!header.length||header.isAbsolutePath||[header.pathComponents containsObject:@".."])return @[];
 NSMutableArray *candidates=[NSMutableArray new];NSDirectoryEnumerator *enumerator=[NSFileManager.defaultManager enumeratorAtPath:root];NSString *relative;NSUInteger count=0;
 while((relative=enumerator.nextObject)&&++count<10000){NSString *path=RepairPath(root,relative);NSDictionary *at=path?[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil]:nil;BOOL hidden=[relative.lastPathComponent hasPrefix:@"."];if(hidden||!at||[at[NSFileType] isEqual:NSFileTypeSymbolicLink]){[enumerator skipDescendants];continue;}if([at[NSFileType] isEqual:NSFileTypeDirectory])continue;
 if([relative isEqual:header]||[relative hasSuffix:[@"/" stringByAppendingString:header]])[candidates addObject:relative];
 }return count>=10000?@[]:candidates;
}
// Lexical guard only; semantic changes still require a compiler diagnostic.
static NSString *CodeOnly(NSString *text){
 NSMutableString *out=[text mutableCopy];BOOL block=NO,line=NO,escape=NO;unichar quote=0;
 for(NSUInteger i=0;i<text.length;i++){unichar c=[text characterAtIndex:i],next=i+1<text.length?[text characterAtIndex:i+1]:0;BOOL hide=NO;
  if(line){hide=YES;if(c=='\n')line=NO;}
  else if(block){hide=YES;if(c=='*'&&next=='/'){[out replaceCharactersInRange:NSMakeRange(i,2) withString:@"  "];i++;block=NO;continue;}}
  else if(quote){hide=YES;if(escape)escape=NO;else if(c=='\\')escape=YES;else if(c==quote)quote=0;}
  else if(c=='/'&&(next=='/'||next=='*')){line=next=='/';block=next=='*';hide=YES;[out replaceCharactersInRange:NSMakeRange(i,2) withString:@"  "];i++;continue;}
  else if(c=='"'||c=='\''){quote=c;hide=YES;}
  if(hide&&c!='\n'&&c!='\r')[out replaceCharactersInRange:NSMakeRange(i,1) withString:@" "];
 }return out;
}
static BOOL CodePosition(NSString *text,NSUInteger offset){
 BOOL block=NO,line=NO,escape=NO;unichar quote=0;
 for(NSUInteger i=0;i<offset;i++){unichar c=[text characterAtIndex:i],next=i+1<text.length?[text characterAtIndex:i+1]:0;
 if(line){if(c=='\n')line=NO;continue;}
 if(block){if(c=='*'&&next=='/'&&i+1<offset){block=NO;i++;}continue;}
 if(quote){if(escape)escape=NO;else if(c=='\\')escape=YES;else if(c==quote)quote=0;continue;}
 if(c=='/'&&next=='/'&&i+1<offset){line=YES;i++;}else if(c=='/'&&next=='*'&&i+1<offset){block=YES;i++;}else if(c=='"'||c=='\'')quote=c;
 }return !block&&!line&&!quote;
}
static NSString *MissingHeader(NSString *message){NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"'([^']+)' file not found" options:0 error:nil];NSTextCheckingResult *m=[rx firstMatchInString:message options:0 range:NSMakeRange(0,message.length)];return m?[message substringWithRange:[m rangeAtIndex:1]]:nil;}
NSArray *TMCCompatibilityFindings(NSString *root,NSArray *diagnostics){
 NSMutableArray *out=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];for(NSDictionary *d in diagnostics)for(NSDictionary *rule in TMCCompatibilityRules()){
 if([rule[@"handling"][@"category"] isEqual:@"repairable"]||!RuleMatches(rule,d[@"message"]?:@""))continue;NSArray *extensions=rule[@"diagnosticConditions"][@"fileExtensions"];if(extensions.count&&![extensions containsObject:[d[@"file"] pathExtension]])continue;NSString *id=rule[@"id"];if([id isEqual:@"TF012"]&&[@[@"mm",@"xm",@"cpp"] containsObject:[d[@"file"] pathExtension]])continue;if([seen containsObject:id])continue;NSMutableDictionary *finding=[rule mutableCopy];finding[@"file"]=d[@"file"]?:@"构建阶段";finding[@"line"]=d[@"line"]?:@0;
 NSString *header=MissingHeader(d[@"message"]?:@"");if([id isEqual:@"TF007"]&&HeaderCandidates(root,header).count<2)continue;if([id isEqual:@"TF006"]&&HeaderCandidates(root,header).count>0)finding[@"explanation"]=@"头文件存在于工程内，请核对搜索目录；若快照已变化，请重新构建后生成适配。";
 [seen addObject:id];[out addObject:finding];}return out;
}
NSArray *TMCCompatibilityPlan(NSString *root,NSArray *diagnostics){
 NSMutableArray *expanded=[diagnostics mutableCopy];for(NSDictionary *d in diagnostics)if([d[@"fixits"] isKindOfClass:NSArray.class])[expanded addObjectsFromArray:d[@"fixits"]];diagnostics=expanded;
 NSMutableDictionary *byFile=[NSMutableDictionary new];for(NSDictionary *d in diagnostics){NSString *file=d[@"file"],*path=RepairPath(root,file);if(!path||![@[@"m",@"mm",@"x",@"xm",@"h",@"c",@"cpp"] containsObject:file.pathExtension])continue;NSString *source=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];NSString *snapshot=[d[@"path"] isKindOfClass:NSString.class]?[NSString stringWithContentsOfFile:d[@"path"] encoding:NSUTF8StringEncoding error:nil]:nil;
 // Only offer source edits when the file still matches the build diagnostic snapshot.
 if(!source||!snapshot||![source isEqual:snapshot])continue;
 NSMutableArray *items=byFile[file];if(!items){items=[NSMutableArray new];byFile[file]=items;}[items addObject:d];}
 NSMutableArray *plan=[NSMutableArray new];for(NSString *file in [byFile.allKeys sortedArrayUsingSelector:@selector(compare:)]){NSString *before=[NSString stringWithContentsOfFile:RepairPath(root,file) encoding:NSUTF8StringEncoding error:nil];NSMutableArray *lines=[[before componentsSeparatedByString:@"\n"] mutableCopy],*edits=[NSMutableArray new];NSMutableSet *done=[NSMutableSet new];BOOL mach=NO;NSArray *codeLines=[CodeOnly(before) componentsSeparatedByString:@"\n"];
 for(NSDictionary *d in byFile[file]){NSUInteger number=[d[@"line"] unsignedIntegerValue];if(!number||number>lines.count)continue;NSString *message=d[@"message"]?:@"",*line=lines[number-1],*after=line,*reason=nil;NSString *code=codeLines[number-1];BOOL codePresent=[[code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] length]>0;
 if(codePresent&&[@[@"mm",@"xm",@"cpp"] containsObject:file.pathExtension]&&Enabled(@"TF001")&&RuleMatches(Rule(@"TF001"),message)){NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"^(\\s*__(?:weak|strong)\\s+)typeof(\\s*\\()" options:0 error:nil];after=[rx stringByReplacingMatchesInString:line options:0 range:NSMakeRange(0,line.length) withTemplate:@"$1__typeof__$2"];if(![after isEqual:line])reason=@"在当前 C++ 模式使用显式 GNU __typeof__ 拼写";}
 if(codePresent&&Enabled(@"TF002")&&!reason&&[message hasPrefix:@"assigning to '"]&&[message containsString:@"from incompatible type 'NSInteger'"]){NSRegularExpression *typeRX=[NSRegularExpression regularExpressionWithPattern:@"^assigning to '([A-Za-z_][A-Za-z0-9_]*)'" options:0 error:nil];NSTextCheckingResult *match=[typeRX firstMatchInString:message options:0 range:NSMakeRange(0,message.length)];if(match){NSString *type=[message substringWithRange:[match rangeAtIndex:1]];NSRegularExpression *assignment=[NSRegularExpression regularExpressionWithPattern:@"^(\\s*[A-Za-z_][A-Za-z0-9_]*\\.[A-Za-z_][A-Za-z0-9_]*\\s*=\\s*)(\\[[A-Za-z_][A-Za-z0-9_]* integerValue\\])(\\s*;\\s*)$" options:0 error:nil];after=[assignment stringByReplacingMatchesInString:line options:0 range:NSMakeRange(0,line.length) withTemplate:[NSString stringWithFormat:@"$1(%@)$2$3",type]];if(![after isEqual:line])reason=[@"按诊断要求显式转换到 " stringByAppendingString:type];}}
 if(reason&&![done containsObject:@(number)]){lines[number-1]=after;[edits addObject:@{@"line":@(number),@"before":line,@"after":after,@"reason":reason}];[done addObject:@(number)];}
 if(Enabled(@"TF003")&&([message containsString:@"task_basic_info"]||[message containsString:@"TASK_BASIC_INFO"]||[message containsString:@"task_info_t"])&&![before containsString:@"<mach/task_info.h>"]&&[CodeOnly(before) rangeOfString:@"(?:struct\\s+task_basic_info|TASK_BASIC_INFO|task_info_t)" options:NSRegularExpressionSearch].location!=NSNotFound)mach=YES;
 }
 if(mach){[edits addObject:@{@"line":@1,@"before":@"",@"after":@"#include <mach/task_info.h>",@"reason":@"补充诊断中缺少的 Mach task 信息类型声明"}];[lines insertObject:@"#include <mach/task_info.h>" atIndex:0];}
 for(NSUInteger i=0;i<edits.count;i++){NSDictionary *e=edits[i];NSString *id=[e[@"reason"] containsString:@"GNU"]?@"TF001":[e[@"reason"] containsString:@"显式转换"]?@"TF002":@"TF003";edits[i]=AnnotatedEdit(e,id,@"source",file,i);}
 if(edits.count)[plan addObject:@{@"file":file,@"before":before,@"after":[lines componentsJoinedByString:@"\n"],@"edits":edits}];}
 // Accept only individually tested compiler Fix-It families. Never invent a range.
 for(NSDictionary *d in diagnostics){if(![d[@"compilerFixIt"] boolValue])continue;
 NSString *replacement=d[@"replacement"],*identifier=nil;for(NSString *candidate in @[@"TF004",@"TF027",@"TF028",@"TF029",@"TF030"])if(Enabled(candidate)&&RuleMatches(Rule(candidate),d[@"message"]?:@"")){identifier=candidate;break;}if(!identifier)continue;
 NSString *file=d[@"file"],*path=RepairPath(root,file);if(!path||![@[@"m",@"mm",@"c",@"cpp",@"h"] containsObject:file.pathExtension])continue;
 if([identifier isEqual:@"TF027"]&&![@[@"m",@"mm"] containsObject:file.pathExtension])continue;
 NSString *before=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil],*snapshot=[NSString stringWithContentsOfFile:d[@"path"] encoding:NSUTF8StringEncoding error:nil];if(!before||![before isEqual:snapshot])continue;
 NSData *data=[before dataUsingEncoding:NSUTF8StringEncoding];NSUInteger ln=[d[@"line"] unsignedIntegerValue];if(ln!=[d[@"endLine"] unsignedIntegerValue])continue;
 NSUInteger start=BytePosition(data,ln,[d[@"column"] unsignedIntegerValue]),end=BytePosition(data,ln,[d[@"endColumn"] unsignedIntegerValue]);if(start==NSNotFound||end==NSNotFound||end<start)continue;
 NSString *prefix=[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0,start)] encoding:NSUTF8StringEncoding],*removed=[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(start,end-start)] encoding:NSUTF8StringEncoding];if(!prefix||!removed||!CodePosition(before,prefix.length))continue;
 NSArray *sourceLines=[before componentsSeparatedByString:@"\n"];NSString *sourceLine=ln&&ln<=sourceLines.count?sourceLines[ln-1]:@"";if([sourceLine rangeOfString:@"^\\s*#" options:NSRegularExpressionSearch].location!=NSNotFound||[sourceLine containsString:@"//"]||[sourceLine containsString:@"/*"])continue;
 NSUInteger lineOffset=0;for(NSUInteger i=0;i+1<ln;i++)lineOffset+=[sourceLines[i] length]+1;NSUInteger local=prefix.length-lineOffset;if(local>sourceLine.length||removed.length>sourceLine.length-local)continue;
 BOOL insertion=start==end,accepted=NO;
 if([identifier isEqual:@"TF004"])accepted=insertion&&[replacement isEqual:@";"];
 if([identifier isEqual:@"TF027"])accepted=insertion&&[replacement isEqual:@"@"]&&local<sourceLine.length&&[sourceLine characterAtIndex:local]=='"'&&(local==0||[sourceLine characterAtIndex:local-1]!='@');
 if([identifier isEqual:@"TF028"])accepted=!insertion&&replacement.length==0&&([removed isEqual:@")"]||[removed isEqual:@"]"]);
 if([identifier isEqual:@"TF029"])accepted=insertion&&[@[@"struct ",@"union ",@"enum "] containsObject:replacement]&&local<sourceLine.length&&[[NSCharacterSet letterCharacterSet] characterIsMember:[sourceLine characterAtIndex:local]];
 if([identifier isEqual:@"TF030"])accepted=insertion&&[@[@",",@", "] containsObject:replacement];
 if(!accepted)continue;NSMutableString *displayAfter=[sourceLine mutableCopy];[displayAfter replaceCharactersInRange:NSMakeRange(local,removed.length) withString:replacement];
 NSDictionary *e=AnnotatedEdit(@{@"line":d[@"line"],@"column":d[@"column"],@"displayBefore":sourceLine,@"displayAfter":displayAfter,@"before":removed,@"after":replacement,@"offset":@(prefix.length),@"length":@(removed.length),@"reason":[NSString stringWithFormat:@"Clang 14 Fix-It 精确字节范围：%@",Rule(identifier)[@"name"]]},identifier,@"source",file,prefix.length);
 NSMutableDictionary *entry=nil;for(NSDictionary *candidate in plan)if([candidate[@"file"] isEqual:file]){entry=[candidate mutableCopy];[plan removeObject:candidate];break;}
 NSMutableArray *edits=entry?[entry[@"edits"] mutableCopy]:[NSMutableArray new];[edits addObject:e];[plan addObject:@{@"file":file,@"before":before,@"after":before,@"edits":edits}];
 }
 // Only a real, uniquely resolved project header may add a configuration search path.
 NSMutableSet *directories=[NSMutableSet new];NSMutableDictionary *requirements=[NSMutableDictionary new];NSString *configPath=RepairPath(root,@"MobileCompiler.json"),*configText=configPath?[NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil]:nil;
 NSDictionary *config=configText?[NSJSONSerialization JSONObjectWithData:[configText dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]:nil;
 if(Enabled(@"TF005")&&[config isKindOfClass:NSDictionary.class])for(NSDictionary *d in diagnostics){NSString *header=MissingHeader(d[@"message"]?:@""),*file=d[@"file"],*sourcePath=RepairPath(root,file);if(!header||!sourcePath)continue;
 NSString *source=[NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:nil],*snapshot=[NSString stringWithContentsOfFile:d[@"path"] encoding:NSUTF8StringEncoding error:nil];if(!source||![source isEqual:snapshot]||![d[@"path"] hasSuffix:file])continue;
 NSString *base=[d[@"path"] substringToIndex:[d[@"path"] length]-file.length];NSString *oldConfig=[NSString stringWithContentsOfFile:[base stringByAppendingPathComponent:@"MobileCompiler.json"] encoding:NSUTF8StringEncoding error:nil];if(![oldConfig isEqual:configText])continue;
 NSArray *matches=HeaderCandidates(root,header);if(matches.count!=1)continue;NSString *match=matches.firstObject;NSString *directory=[match substringToIndex:match.length-header.length];while([directory hasSuffix:@"/"])directory=[directory substringToIndex:directory.length-1];if(!directory.length)directory=@".";
 if((!config[@"includeDirectories"]||[config[@"includeDirectories"] isKindOfClass:NSArray.class])&&![directory isEqual:@"."]&&![config[@"includeDirectories"] containsObject:directory]){[directories addObject:directory];requirements[file]=source;requirements[match]=[NSString stringWithContentsOfFile:RepairPath(root,match) encoding:NSUTF8StringEncoding error:nil]?:@"";}
 }
 if(directories.count){NSMutableDictionary *updated=[config mutableCopy];NSMutableArray *include=[config[@"includeDirectories"] isKindOfClass:NSArray.class]?[config[@"includeDirectories"] mutableCopy]:[NSMutableArray new];[include addObjectsFromArray:[directories.allObjects sortedArrayUsingSelector:@selector(compare:)]];updated[@"includeDirectories"]=include;
 NSString *after=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:updated options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding];NSDictionary *edit=AnnotatedEdit(@{@"line":@1,@"before":configText,@"after":after,@"offset":@0,@"length":@(configText.length),@"reason":[NSString stringWithFormat:@"工程内唯一真实头文件：添加搜索目录 %@",[[directories.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]]},@"TF005",@"configuration",@"MobileCompiler.json",0);[plan addObject:@{@"file":@"MobileCompiler.json",@"before":configText,@"after":after,@"edits":@[edit],@"preconditions":requirements}];}
 NSMutableSet *all=[NSMutableSet new];for(NSDictionary *entry in plan)for(NSDictionary *e in entry[@"edits"])[all addObject:e[@"id"]];return TMCSelectedCompatibilityPlan(plan,all);

}
NSArray *TMCSelectedCompatibilityPlan(NSArray *plan,NSSet *selected){
 NSMutableArray *out=[NSMutableArray new];for(NSDictionary *entry in plan){NSString *before=entry[@"before"];NSMutableArray *edits=[NSMutableArray new];
 for(NSDictionary *edit in entry[@"edits"]){if(![selected containsObject:edit[@"id"]])continue;NSMutableDictionary *e=[edit mutableCopy];NSUInteger offset=0,length=0;
 if(edit[@"offset"]){offset=[edit[@"offset"] unsignedIntegerValue];length=[edit[@"length"] unsignedIntegerValue];}
 else {NSArray *lines=[before componentsSeparatedByString:@"\n"];NSUInteger line=[edit[@"line"] unsignedIntegerValue];if(!line||line>lines.count)return @[];for(NSUInteger i=0;i+1<line;i++)offset+=[lines[i] length]+1;length=[edit[@"before"] length];if(length&&![lines[line-1] isEqual:edit[@"before"]])return @[];
 // A new include at the beginning is an insertion of a complete source line.
 if(!length&&[edit[@"after"] hasPrefix:@"#include"])e[@"replacement"]=[edit[@"after"] stringByAppendingString:@"\n"];
 }
 if(offset>before.length||length>before.length-offset||![[before substringWithRange:NSMakeRange(offset,length)] isEqual:edit[@"before"]])return @[];
 e[@"offset"]=@(offset);e[@"length"]=@(length);[edits addObject:e];}
 if(!edits.count)continue;[edits sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSComparisonResult result=[b[@"offset"] compare:a[@"offset"]];return result==NSOrderedSame?[b[@"length"] compare:a[@"length"]]:result;}];
 NSMutableString *after=[before mutableCopy];NSUInteger boundary=NSNotFound;BOOL lastInsertion=NO;for(NSDictionary *edit in edits){NSUInteger offset=[edit[@"offset"] unsignedIntegerValue],length=[edit[@"length"] unsignedIntegerValue];if(boundary!=NSNotFound&&(offset+length>boundary||(offset==boundary&&!length&&lastInsertion)))return @[];boundary=offset;lastInsertion=length==0;[after replaceCharactersInRange:NSMakeRange(offset,length) withString:edit[@"replacement"]?:edit[@"after"]];}
 [out addObject:@{@"file":entry[@"file"],@"before":before,@"after":after,@"edits":edits,@"preconditions":entry[@"preconditions"]?:@{}}];}return out;
}
static BOOL WriteTransaction(NSString *root,NSArray *plan,NSError **error){
 for(NSDictionary *entry in plan){for(NSString *file in entry[@"preconditions"]){NSString *check=RepairPath(root,file);NSString *text=check?[NSString stringWithContentsOfFile:check encoding:NSUTF8StringEncoding error:nil]:nil;if(!text||![text isEqual:entry[@"preconditions"][file]])return RepairError(error,@"相关源码或依赖已改变，请重新构建后生成修复。");}NSString *path=RepairPath(root,entry[@"file"]);NSString *current=path?[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]:nil;if(!current||![current isEqual:entry[@"before"]])return RepairError(error,@"文件已改变或路径无效，请重新构建后生成修复预览。");}
 NSMutableArray *written=[NSMutableArray new];for(NSDictionary *entry in plan){if(![entry[@"after"] writeToFile:RepairPath(root,entry[@"file"]) atomically:YES encoding:NSUTF8StringEncoding error:error]){for(NSDictionary *old in written)[old[@"before"] writeToFile:RepairPath(root,old[@"file"]) atomically:YES encoding:NSUTF8StringEncoding error:nil];return NO;}[written addObject:entry];}return YES;
}
BOOL TMCApplyCompatibilityPlan(NSString *root,NSArray *plan,NSError **error){
 if(!plan.count)return RepairError(error,@"没有可应用的修复。");
 NSString *backup=RepairPath(root,@".studio-repair-backup.json");if(!backup)return RepairError(error,@"备份路径无效。");NSData *oldBackup=[NSData dataWithContentsOfFile:backup];NSData *json=[NSJSONSerialization dataWithJSONObject:plan options:0 error:error];if(!json||![json writeToFile:backup options:NSDataWritingAtomic error:error])return NO;
 if(!WriteTransaction(root,plan,error)){if(oldBackup)[oldBackup writeToFile:backup atomically:YES];else[NSFileManager.defaultManager removeItemAtPath:backup error:nil];return NO;}
 NSString *historyRoot=RepairPath(root,@".studio-repair-history");BOOL saved=[NSFileManager.defaultManager createDirectoryAtPath:historyRoot withIntermediateDirectories:YES attributes:nil error:error];NSString *identifier=NSUUID.UUID.UUIDString;
 NSData *contextData=[NSData dataWithContentsOfFile:RepairPath(root,@".studio-repair-context.json")];NSDictionary *context=contextData?[NSJSONSerialization JSONObjectWithData:contextData options:0 error:nil]:@{};
 NSDictionary *history=@{@"id":identifier,@"created":@([NSDate.date timeIntervalSince1970]),@"changes":plan,@"beforeDiagnostics":context?:@{},@"state":@"awaiting-rebuild"};NSData *historyData=[NSJSONSerialization dataWithJSONObject:history options:NSJSONWritingPrettyPrinted error:error];NSString *historyPath=[historyRoot stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"json"]];
 saved=saved&&historyData&&[historyData writeToFile:historyPath options:NSDataWritingAtomic error:error]&&[identifier writeToFile:RepairPath(root,@".studio-repair-pending") atomically:YES encoding:NSUTF8StringEncoding error:error];
 if(saved)saved=[identifier writeToFile:RepairPath(root,@".studio-repair-last") atomically:YES encoding:NSUTF8StringEncoding error:error];
 if(!saved){for(NSDictionary *entry in plan)[entry[@"before"] writeToFile:RepairPath(root,entry[@"file"]) atomically:YES encoding:NSUTF8StringEncoding error:nil];if(oldBackup)[oldBackup writeToFile:backup atomically:YES];else[NSFileManager.defaultManager removeItemAtPath:backup error:nil];return NO;}return YES;
}
BOOL TMCUndoCompatibilityRepair(NSString *root,NSError **error){
 NSString *path=RepairPath(root,@".studio-repair-backup.json");NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;id plan=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:error]:nil;if(![plan isKindOfClass:NSArray.class]||![plan count])return RepairError(error,@"暂无上次修复备份。");NSMutableArray *reverse=[NSMutableArray new];for(NSDictionary *entry in plan){if(![entry isKindOfClass:NSDictionary.class]||![entry[@"before"] isKindOfClass:NSString.class]||![entry[@"after"] isKindOfClass:NSString.class])return RepairError(error,@"备份格式有误。");[reverse addObject:@{@"file":entry[@"file"]?:@"",@"before":entry[@"after"],@"after":entry[@"before"]}];}if(!WriteTransaction(root,reverse,error))return NO;[NSFileManager.defaultManager removeItemAtPath:path error:nil];
 NSString *last=[NSString stringWithContentsOfFile:RepairPath(root,@".studio-repair-last") encoding:NSUTF8StringEncoding error:nil];if(last.length){NSString *history=RepairPath(root,[@".studio-repair-history/" stringByAppendingString:[last stringByAppendingPathExtension:@"json"]]);NSData *raw=history?[NSData dataWithContentsOfFile:history]:nil;NSMutableDictionary *record=raw?[NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingMutableContainers error:nil]:nil;if([record isKindOfClass:NSMutableDictionary.class]){record[@"state"]=@"undone";record[@"undoneAt"]=@([NSDate.date timeIntervalSince1970]);[[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:nil] writeToFile:history options:NSDataWritingAtomic error:nil];}}
 return YES;
}

BOOL TMCRecordRepairContext(NSString *root,NSArray *diagnostics,NSString *log,NSError **error){
 NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"diagnostics":diagnostics?:@[],@"log":log?:@"",@"recorded":@([NSDate.date timeIntervalSince1970])} options:0 error:error];NSString *path=RepairPath(root,@".studio-repair-context.json");return path&&data&&[data writeToFile:path options:NSDataWritingAtomic error:error];
}
void TMCRecordRebuildDiagnostics(NSString *root,NSString *build,NSArray *diagnostics){
 NSString *pending=RepairPath(root,@".studio-repair-pending");if(![NSFileManager.defaultManager fileExistsAtPath:pending])return;
 NSString *folder=RepairPath(root,@".studio-repair-history");NSArray *names=[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil];BOOL remaining=NO;
 NSDate *modified=[NSFileManager.defaultManager attributesOfItemAtPath:[build stringByAppendingPathComponent:@"report.json"] error:nil][NSFileModificationDate];
 for(NSString *name in names){NSString *path=RepairPath(root,[@".studio-repair-history" stringByAppendingPathComponent:name]);NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;id json=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil]:nil;if(![json isKindOfClass:NSMutableDictionary.class]||![json[@"state"] isEqual:@"awaiting-rebuild"])continue;
 if(!modified||modified.timeIntervalSince1970<[json[@"created"] doubleValue]){remaining=YES;continue;}
 NSString *log=[NSString stringWithContentsOfFile:[build stringByAppendingPathComponent:@"build.log"] encoding:NSUTF8StringEncoding error:nil];NSData *reportData=[NSData dataWithContentsOfFile:[build stringByAppendingPathComponent:@"report.json"]];id report=reportData?[NSJSONSerialization JSONObjectWithData:reportData options:0 error:nil]:nil;
 json[@"afterDiagnostics"]=@{@"diagnostics":diagnostics?:@[],@"log":log?:@"",@"report":report?:@{},@"build":build.lastPathComponent?:@"",@"recorded":@([NSDate.date timeIntervalSince1970])};json[@"state"]=@"rebuilt";
 NSData *output=[NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];if(![output writeToFile:path options:NSDataWritingAtomic error:nil])remaining=YES;
 }if(!remaining)[NSFileManager.defaultManager removeItemAtPath:pending error:nil];
}
