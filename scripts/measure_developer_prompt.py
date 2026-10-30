#!/usr/bin/env python3
"""Compare request sizes using real schema definitions; bytes are not billed tokens."""
import argparse,json,pathlib,re,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--baseline',type=pathlib.Path,required=True);parser.add_argument('--output',type=pathlib.Path,required=True);args=parser.parse_args()
baseline=args.baseline.resolve()
toolbox=(root/'App/AI/Tools/TFAIToolbox.m').read_text()
helpers='\n'.join(line for line in toolbox.splitlines() if line.startswith('static NSDictionary *') and any(name in line for name in ['StringType(', 'NumberType(', 'Schema(']))
method=toolbox.split('+ (NSArray<NSDictionary *> *)schemas {',1)[1].split('\n- (BOOL)validRequest:',1)[0]
web=(root/'App/AI/Tools/TFAIWebTools.m').read_text()
webhelper=next(line for line in web.splitlines() if line.startswith('static NSDictionary *Schema(')).replace('Schema(', 'WebSchema(')
webmethod=next(line for line in web.splitlines() if line.startswith('+ (NSArray *)schemas{')).replace('+ (NSArray *)schemas{','static NSArray *WebSchemas(void){',1).replace('Schema(', 'WebSchema(')
legacy=(baseline/'TheosMobileCompiler/App/AI/Core/AIRuntime.m').read_text()
oldsystem=re.findall(r'\[self.messages addObject:@\{@"role":@"system",@"content":@"((?:[^"\\]|\\.)*)"\}\];',legacy)
assert len(oldsystem)==5,len(oldsystem)
source='''#import <Foundation/Foundation.h>
#define TFAIDeveloperPrompt TFAIDeveloperPrompt112
#import "BASELINE"
#undef TFAIDeveloperPrompt
#import "CURRENT"
HELPERS
WEBHELPER
WEBMETHOD
static NSArray *ProjectSchemas(void) { METHOD
static NSUInteger Bytes(id value){return [NSJSONSerialization dataWithJSONObject:value options:0 error:nil].length;}
int main(int argc,const char **argv){@autoreleasepool{
 NSArray *legacy=@[OLD_SYSTEMS];NSMutableArray *results=[NSMutableArray new];
 for(NSString *scenario in @[@"ordinary",@"ask",@"develop",@"header_loaded"]){BOOL hasProject=![scenario isEqual:@"ordinary"];BOOL develop=[scenario isEqual:@"develop"]||[scenario isEqual:@"header_loaded"];NSMutableArray *oldTools=[WebSchemas() mutableCopy];if(hasProject)for(NSDictionary *tool in ProjectSchemas())if(develop||[@[@"list_files",@"read_file",@"search_text",@"list_symbols",@"read_project_config",@"read_diagnostics",@"list_artifacts",@"git_status",@"git_diff",@"git_history"] containsObject:tool[@"name"]])[oldTools addObject:tool];NSMutableArray *newTools=[oldTools mutableCopy];[newTools insertObject:TFAIDevelopmentGuideSchema() atIndex:0];
 NSDictionary *env=@{@"hasProject":@(hasProject),@"mode":develop?@"develop":@"ask",@"model":@"fixture-model",@"protocol":@"chat",@"version":@"1.0.2",@"build":@"113",@"permission":@{@"preset":@"assisted",@"expiresAt":@1800000000},@"recoveryReadOnly":@NO,@"attachmentReferenceCount":@0};
 NSString *oldGuide=TFAIDeveloperPrompt112(env,oldTools),*newGuide=TFAIDeveloperPrompt(env,newTools);
 NSMutableArray *oldMessages=[NSMutableArray arrayWithObjects:@{@"role":@"system",@"content":legacy[0]},@{@"role":@"system",@"content":oldGuide},nil];if(!hasProject)[oldMessages addObject:@{@"role":@"system",@"content":legacy[2]}];else if(!develop)[oldMessages addObject:@{@"role":@"system",@"content":legacy[3]}];
 NSMutableArray *newMessages=[NSMutableArray arrayWithObject:@{@"role":@"system",@"content":newGuide}];
 if([scenario isEqual:@"header_loaded"]){[newMessages addObject:@{@"role":@"assistant",@"content":@"",@"tool_calls":@[@{@"id":@"guide-1",@"type":@"function",@"function":@{@"name":@"read_development_guide",@"arguments":@"{\\\"topic\\\":\\\"headers\\\"}"}}]}];[newMessages addObject:@{@"role":@"tool",@"tool_call_id":@"guide-1",@"content":[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:TFAIDevelopmentGuide(@{@"topic":@"headers"},nil) options:0 error:nil] encoding:NSUTF8StringEncoding]}];}
 NSDictionary *user=@{@"role":@"user",@"content":@"请根据头文件实现目标功能。"};[oldMessages addObject:user];[newMessages addObject:user];
 NSMutableArray *oldWire=[NSMutableArray new],*newWire=[NSMutableArray new];for(NSDictionary *schema in oldTools)[oldWire addObject:@{@"type":@"function",@"function":schema}];for(NSDictionary *schema in newTools)[newWire addObject:@{@"type":@"function",@"function":schema}];
 NSMutableDictionary *row=[@{@"scenario":scenario,@"oldSystemBytes":@(Bytes([oldMessages filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"role == 'system'"]])),@"newSystemBytes":@(Bytes([newMessages filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"role == 'system'"]])),@"oldRequestBytes":@(Bytes(@{@"messages":oldMessages,@"tools":oldWire})),@"newRequestBytes":@(Bytes(@{@"messages":newMessages,@"tools":newWire})),@"oldPrompt":oldMessages,@"newPrompt":newMessages} mutableCopy];[results addObject:row];
 }
 NSData *data=[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:nil];[data writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
}return 0;}
'''
replacements={'BASELINE':str(baseline/'TheosMobileCompiler/App/AI/Core/TFAIDeveloperPrompt.h'),'CURRENT':str(root/'App/AI/Core/TFAIDeveloperPrompt.h'),'HELPERS':helpers,'WEBHELPER':webhelper,'WEBMETHOD':webmethod,'METHOD':method,'OLD_SYSTEMS':','.join('@"'+value+'"' for value in oldsystem)}
for key,value in replacements.items():source=source.replace(key,value)
args.output.parent.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='tf-prompt-measure-') as tmp:
 p=pathlib.Path(tmp);(p/'measure.m').write_text(source)
 subprocess.run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fblocks','-fmodules','-framework','Foundation',str(p/'measure.m'),'-o',str(p/'measure')],check=True)
 subprocess.run([str(p/'measure'),str(args.output.resolve())],check=True)
rows=json.loads(args.output.read_text())
for row in rows:
 for prefix in ['System','Request']:
  row[prefix.lower()+'ReductionPercent']=round(100*(1-row['new'+prefix+'Bytes']/row['old'+prefix+'Bytes']),1)
 print(json.dumps({k:v for k,v in row.items() if k not in ['oldPrompt','newPrompt']},ensure_ascii=False))
args.output.write_text(json.dumps({'measurement':'UTF-8 JSON bytes, not provider billing tokens or latency','scenarios':rows},ensure_ascii=False,indent=2)+'\n')
