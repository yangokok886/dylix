#import "../App/AI/UI/TFAISessionFiles.h"
UIViewController *TFAIFile135Regression(void){
 NSMutableArray *records=[NSMutableArray new];
 // Reuse genuine compiler outputs already on this simulator; never fabricate artifacts.
 for(NSString *identifier in [NSFileManager.defaultManager contentsOfDirectoryAtPath:Docs() error:nil]){
  if(![identifier hasPrefix:@"Build-"])continue;NSString *path=[Docs() stringByAppendingPathComponent:identifier];NSDictionary *report=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"report.json"]]?:NSData.data options:0 error:nil];if(![report[@"success"] boolValue])continue;
  NSMutableArray *artifacts=[NSMutableArray new];for(NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil])if([@[@"deb",@"dylib"] containsObject:file.pathExtension])[artifacts addObject:@{@"name":file}];if(!artifacts.count)continue;
  [records addObject:@{@"status":@"completed",@"name":@"build_project",@"result":@{@"buildID":identifier,@"artifacts":artifacts}}];if(records.count==2)break;
 }
 UIViewController *view=TFAISessionFilesController(@{@"messages":@[],@"processRecords":records},nil);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSArray *items=[view valueForKey:@"items"];BOOL times=items.count>=2;for(NSDictionary *item in items)times&=[item[@"modified"] doubleValue]>0;UITableView *table=[view valueForKey:@"tableView"];UITableViewCell *cell=items.count?[(id<UITableViewDataSource>)view tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]]:nil;JSONWrite(@{@"pass":@(times&&[cell.detailTextLabel.text containsString:@"修改于"]),@"items":@(items.count),@"firstSubtitle":cell.detailTextLabel.text?:@""},[Docs() stringByAppendingPathComponent:@"ai-files135-tests.json"],nil);});return view;
}
