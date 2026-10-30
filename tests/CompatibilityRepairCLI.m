#import "../App/CompatibilityRepair.h"
int main(int argc,char **argv){@autoreleasepool{
 if(argc<3)return 2;NSString *root=@(argv[2]);NSError *error=nil;BOOL success=NO;id result=nil;
 if(!strcmp(argv[1],"undo"))success=TMCUndoCompatibilityRepair(root,&error);
 else if(!strcmp(argv[1],"rebuild")){TMCRecordRebuildDiagnostics(root,@(argv[3]),@[]);success=YES;}
 else{
  if(argc<4)return 2;NSData *data=[NSData dataWithContentsOfFile:@(argv[3])];NSArray *diags=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:&error]:nil;
  if(!strcmp(argv[1],"fixits")){NSString *log=[NSString stringWithContentsOfFile:@(argv[3]) encoding:NSUTF8StringEncoding error:nil];result=TMCParseFixIts(log,root,argc>4?@(argv[4]):nil);success=YES;}
  else if(!strcmp(argv[1],"apply-plan")){result=diags;success=TMCApplyCompatibilityPlan(root,diags,&error);}
  else if(!strcmp(argv[1],"findings")){result=TMCCompatibilityFindings(root,diags?:@[]);success=YES;}
  else {NSArray *plan=TMCCompatibilityPlan(root,diags?:@[]);
   if(argc>4){NSArray *ids=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[4])] options:0 error:nil];plan=TMCSelectedCompatibilityPlan(plan,[NSSet setWithArray:ids]);}
   result=plan;success=!strcmp(argv[1],"apply")?(TMCRecordRepairContext(root,diags,@"test original log",&error)&&TMCApplyCompatibilityPlan(root,plan,&error)):YES;
  }
 }
 NSDictionary *output=@{@"success":@(success),@"plan":result?:@[],@"error":error.localizedDescription?:@""};NSData *json=[NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingPrettyPrinted error:nil];fwrite(json.bytes,1,json.length,stdout);return success?0:1;
}}
