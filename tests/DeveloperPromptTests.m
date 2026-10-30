#import "../App/AI/Core/TFAIDeveloperPrompt.h"
static int failed=0,count=0;
static void Check(BOOL ok,const char *name){count++;if(!ok)failed++;printf("%s %s\n",ok?"PASS":"FAIL",name);}
static NSDictionary *Snapshot(NSString *prompt){NSString *tail=[[prompt componentsSeparatedByString:@"【本轮环境快照】\n"] lastObject];return [NSJSONSerialization JSONObjectWithData:[tail dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];}
int main(void){@autoreleasepool{
 NSDictionary *ordinary=@{@"hasProject":@NO,@"mode":@"ask",@"version":@"1.0.2",@"permission":@{@"preset":@"assisted"}};
 NSDictionary *schema=@{@"name":@"classdump_headers",@"description":@"UNIQUE_TOOL_DESCRIPTION",@"parameters":@{@"type":@"object",@"required":@[@"job_id",@"action"],@"properties":@{@"action":@{@"type":@"string",@"enum":@[@"list",@"search",@"read"]},@"line_count":@{@"type":@"integer",@"maximum":@120}}}};
 NSArray *schemas=@[TFAIDevelopmentGuideSchema(),schema,@{@"name":@"web_read"}];
 NSString *a=TFAIDeveloperPrompt(ordinary,schemas);NSDictionary *snapshot=Snapshot(a);
 Check([snapshot[@"environment"] isEqual:ordinary],"environment preserved");Check([snapshot[@"availableTools"] isEqual:@[@"read_development_guide",@"classdump_headers",@"web_read"]],"only current tools advertised");Check([snapshot[@"promptVersion"] isEqual:@"3.0"],"versioned lean prompt");
 Check(!snapshot[@"toolCatalog"]&&![a containsString:@"UNIQUE_TOOL_DESCRIPTION"]&&![a containsString:@"line_count"],"tool descriptions and parameters are not duplicated");
 Check([a containsString:@"未关联项目"]&&![a containsString:@"问答只读"],"ordinary scope is concise and accurate");
 NSString *ask=TFAIDeveloperPrompt(@{@"hasProject":@YES,@"mode":@"ask"},schemas);Check([ask containsString:@"问答只读"]&&![ask containsString:@"未关联项目"],"ask scope restricted");
 NSString *dev=TFAIDeveloperPrompt(@{@"hasProject":@YES,@"mode":@"develop"},schemas);Check(![dev containsString:@"问答只读"]&&![dev containsString:@"未关联项目"],"development scope does not invent restrictions");
 NSString *recovery=TFAIDeveloperPrompt(@{@"hasProject":@YES,@"mode":@"develop",@"recoveryReadOnly":@YES},schemas);Check([recovery containsString:@"中断后的只读核对"]&&[recovery containsString:@"不是恢复服务端流"],"recovery remains read-only review");
 NSString *noTools=TFAIDeveloperPrompt(ordinary,@[]);Check(![noTools containsString:@"【按需指南】"]&&[noTools containsString:@"根据头文件写功能"],"no-tool connection retains header essentials without unusable guide instruction");
 NSDictionary *empty=Snapshot(TFAIDeveloperPrompt(nil,nil));Check([empty[@"environment"] count]==0&&[empty[@"availableTools"] count]==0,"empty context invents no access");NSDictionary *bad=Snapshot(TFAIDeveloperPrompt(nil,@[NSNull.null,@{@"name":NSNull.null},schema,schema]));Check([bad[@"availableTools"] count]==1,"malformed and duplicate schema names ignored");
 for(NSString *rule in @[@"schema",@"最小修改",@"proposal_id",@"不提升权限",@"缺少结果",@"不伪造",@"进程终止",@"核心技能：根据头文件写功能",@"完整selector",@"声明存在不证明",@"观察版",@"原方法契约"]){Check([a containsString:rule],rule.UTF8String);}
 Check(![a containsString:@"iphoneos-arm64e"]&&![a containsString:@"LLVM/Clang 14"]&&![a containsString:@"给定密钥XOR"],"unrelated detailed guides stay out of initial prompt");
 NSDictionary *guideSchema=TFAIDevelopmentGuideSchema();Check([guideSchema[@"parameters"][@"required"] isEqual:@[@"topic"]]&&[guideSchema[@"parameters"][@"properties"][@"topic"][@"enum"] isEqual:TFAIDevelopmentGuideTopics()]&&![guideSchema[@"parameters"][@"additionalProperties"] boolValue],"guide schema is bounded to built-in topics");
 for(NSString *topic in TFAIDevelopmentGuideTopics()){
  NSError *error=nil;NSDictionary *result=TFAIDevelopmentGuide(@{@"topic":topic},&error);
  Check(result&&!error&&[result[@"topic"] isEqual:topic]&&[result[@"readOnly"] boolValue]&&[result[@"content"] length]>200,[[topic stringByAppendingString:@": real read-only guide available"] UTF8String]);
  Check([result[@"content"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<5000,[[topic stringByAppendingString:@": guide stays bounded"] UTF8String]);
 }
 Check([TFAIDevelopmentGuide(@{@"topic":@"deb"},nil)[@"content"] isEqual:TFAIDevelopmentGuide(@{@"topic":@"artifacts"},nil)[@"content"]],"deb alias preserves packaging guide");
 Check([TFAIDevelopmentGuide(@{@"topic":@"logos"},nil)[@"content"] containsString:@"%orig"],"Logos guide preserves method contracts");
 NSDictionary *headers=TFAIDevelopmentGuide(@{@"topic":@"headers"},nil);Check([headers[@"content"] containsString:@"父类及子类"]&&[headers[@"content"] containsString:@"完整selector"]&&[headers[@"content"] containsString:@"防重复UI"]&&[headers[@"content"] containsString:@"观察版"],"header guide retains signature/lifecycle/observation workflow");
 Check(![headers[@"content"] containsString:@"iphoneos-arm64e"]&&![headers[@"content"] containsString:@"给定密钥XOR"],"one guide does not load unrelated topics");
 for(id args in @[@{},@{@"topic":@"../../secret"},@{@"topic":@"headers",@"path":@"/private"},@{@"topic":NSNull.null},@{@"topic":@[@"headers"]},NSNull.null]){NSError *error=nil;Check(!TFAIDevelopmentGuide(args,&error)&&error!=nil,"invalid guide request fails without file access");}
 Check([a lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<5000,"ordinary core prompt has a size regression ceiling");
 printf("RESULT %d checks %d failures\n",count,failed);return failed?1:0;
}}
