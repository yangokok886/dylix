#import <Foundation/Foundation.h>
#import "../App/AI/UI/TFAIConversationTimeline.h"
static NSUInteger checks;
static void Check(BOOL yes,NSString *name){checks++;if(!yes){NSLog(@"FAIL %@",name);exit(1);}}
int main(){@autoreleasepool{
 NSDictionary *empty=@{@"role":@"assistant",@"content":@"",@"messageID":@"active",@"rowID":@"message-active"};
 NSDictionary *prior=@{@"role":@"assistant",@"content":@"先前回复",@"messageID":@"prior",@"rowID":@"message-prior"};
 NSArray *source=@[prior,empty];NSArray *rows=TFAIConversationWithStatus(source,YES,@"读取文件 · 执行中",@"active");Check(rows.count==2,@"live status replaces empty placeholder");Check([rows[0] isEqual:prior],@"previous reply retained");Check([rows.lastObject[@"processing"] boolValue],@"explicit processing presentation flag");Check([rows.lastObject[@"content"] isEqual:@"读取文件 · 执行中"],@"current stage shown inline");Check([source[1] isEqual:empty]&&source.count==2,@"transcript is unchanged");
 rows=TFAIConversationWithStatus(@[prior],YES,@"",@"active");Check([rows.lastObject[@"content"] isEqual:@"正在响应"],@"default response state");
 rows=TFAIConversationWithStatus(@[prior],YES,@"正在生成回复",@"prior");Check(rows.count==2&&[rows.firstObject isEqual:prior],@"streamed reply is not replaced");
 rows=TFAIConversationWithStatus(source,NO,@"已完成",@"active");Check([rows isEqual:source],@"finished task removes transient status");
 NSDictionary *image=@{@"role":@"assistant",@"content":@"",@"messageID":@"active",@"images":@[@{}]};rows=TFAIConversationWithStatus(@[image],YES,@"正在分析",@"active");Check(rows.count==2,@"attachment-only row retained");
 rows=TFAIConversationWithStatus(@[],YES,@"等待批准",nil);Check([rows.lastObject[@"rowID"] isEqual:@"live-status"],@"stable row identity before first response");Check([rows.lastObject[@"content"] isEqual:@"等待批准"],@"approval stage visible");
 Check(TFAIConversationWithStatus(nil,NO,nil,nil).count==0,@"empty idle conversation");

 NSArray *conversation=@[@{@"role":@"user",@"messageID":@"u",@"content":@"Question"},@{@"role":@"assistant",@"messageID":@"a",@"content":@"Let me inspect",@"tool_calls":@[@{@"id":@"t"}]},@{@"role":@"tool",@"tool_call_id":@"t",@"content":@"result"},@{@"role":@"assistant",@"messageID":@"f",@"content":@"Final answer"}];
 NSMutableDictionary *record=[@{@"id":@"t",@"name":@"read_file",@"status":@"completed",@"assistantMessageID":@"a"} mutableCopy];
 NSArray *timeline=TFAIConversationTimeline(conversation,@[record],@{@"a":@"Reasoning"},@"",@{});NSArray *closed=TFAIConversationGrouped(timeline,@{});Check(closed.count==3,@"closed turn shows user, process disclosure and final answer only");Check([closed[1][@"groupHeader"] boolValue]&&![closed[1][@"expanded"] boolValue],@"process starts collapsed");Check([closed.lastObject[@"content"] isEqual:@"Final answer"],@"final answer remains outside disclosure");
 NSArray *opened=TFAIConversationGrouped(timeline,@{@"turn-u":@YES});Check(opened.count==6,@"open turn exposes intermediate text, reasoning and tool child");Check([opened[2][@"nested"] boolValue]&&[opened[3][@"nested"] boolValue],@"children have nested visual depth");Check([opened[4][@"foldID"] isEqual:@"t"]&&![opened[4][@"expanded"] boolValue],@"tool details stay independently collapsed");
 Check([timeline[3][@"processRecord"][@"status"] isEqual:@"completed"],@"tool state snapshot exists");record[@"status"]=@"failed";Check([timeline[3][@"processRecord"][@"status"] isEqual:@"completed"],@"later tool mutation does not corrupt previous render snapshot");
 NSArray *simple=TFAIConversationGrouped(TFAIConversationTimeline(@[conversation[0],conversation[3]],@[],@{},@"",@{}),@{});Check(simple.count==2,@"plain replies do not get empty process header");
 NSMutableArray *two=[conversation mutableCopy];[two addObjectsFromArray:@[@{@"role":@"user",@"messageID":@"u2",@"content":@"Next"},@{@"role":@"assistant",@"messageID":@"f2",@"content":@"Second final"}]];NSArray *multi=TFAIConversationGrouped(TFAIConversationTimeline(two,@[],@{},@"",@{}),@{});Check([multi.lastObject[@"content"] isEqual:@"Second final"]&&[[multi valueForKey:@"content"] containsObject:@"Final answer"],@"each turn keeps its own final reply");
 NSArray *active=TFAIConversationGrouped(TFAIConversationTimeline([conversation subarrayWithRange:NSMakeRange(0,3)],@[record],@{},@"",@{}),@{});Check(active.count==2&&[active.lastObject[@"groupHeader"] boolValue],@"tool-bearing intermediate response is hidden during execution");
 NSArray *statusRows=TFAIConversationWithStatus(active,YES,@"执行中",@"a");Check([statusRows.lastObject[@"processing"] boolValue],@"current loading row stays outside collapsed process");
 NSArray *timed=TFAIConversationTimed(closed,@{@"u":@{@"start":@100,@"end":@112.3,@"duration":@12.3}},200);Check([timed[1][@"foldTitle"] containsString:@"12.3"],@"finished turn shows durable duration");Check([closed[1][@"foldTitle"] rangeOfString:@"12.3"].location==NSNotFound,@"timing does not mutate source");
 NSArray *live=TFAIConversationTimed(closed,@{@"u":@{@"start":@100}},105);
 Check([live[1][@"foldTitle"] containsString:@"5.0 秒"],@"collapsed process clock advances without expansion");
 NSArray *tick=TFAIConversationTimed(live,@{@"u":@{@"start":@100}},107);
 Check([tick[1][@"foldTitle"] containsString:@"7.0 秒"]&&![tick[1][@"foldTitle"] containsString:@"5.0 秒"],@"repeated ticks replace elapsed suffix");
 NSDictionary *tool=@{@"role":@"process",@"foldID":@"tool",@"foldTitle":@"old",@"expanded":@YES,@"display":@"stable detail",@"processRecord":@{@"name":@"read_file",@"status":@"running",@"startedAt":@100}};
 NSArray *tools=TFAIConversationTimed(@[tool],@{},110);
 Check([tools[0][@"foldTitle"] containsString:@"10.0 秒"],@"running tool gets live elapsed");
 Check([tools[0][@"display"] isEqual:@"stable detail"]&&[tools[0][@"expanded"] boolValue],@"clock keeps disclosure and content stable");
 Check([TFAIConversationTimed(tools,@{},115)[0][@"foldTitle"] containsString:@"15.0 秒"],@"tool clock resumes from actual start");
 NSMutableDictionary *dump=[tool mutableCopy];dump[@"processRecord"]=@{@"name":@"classdump_export",@"status":@"running",@"startedAt":@100,@"summary":@"42% · 正在扫描"};
 NSString *title=TFAIConversationTimed(@[dump],@{},111)[0][@"foldTitle"];
 Check([title containsString:@"42%"]&&[title containsString:@"11.0 秒"],@"real export progress and elapsed coexist");
 NSMutableDictionary *done=[tool mutableCopy];done[@"foldTitle"]=@"已完成 · 4.0 秒";done[@"processRecord"]=@{@"name":@"read_file",@"status":@"completed",@"startedAt":@100,@"duration":@4};
 Check([TFAIConversationTimed(@[done],@{},999)[0][@"foldTitle"] isEqual:done[@"foldTitle"]],@"finished tool duration stays frozen");
 Check([TFAIConversationTimed(timed,@{@"u":@{@"start":@100,@"end":@112.3,@"duration":@12.3}},999)[1][@"foldTitle"] isEqual:timed[1][@"foldTitle"]],@"finished turn stays frozen across repeated ticks");
 NSLog(@"PASS %lu inline status checks",(unsigned long)checks);
}return 0;}
