#import "../App/AI/UI/TFAICodeBlock.h"
#import <WebKit/WebKit.h>
#import "../App/GitDiffView.h"
// Include from the app's simulator-only test harness. Runs on main, no network/keychain writes.
#import "../App/AI/UI/AIUI.h"
// These synchronous fixtures isolate UIKit geometry. AIChat122Regression separately exercises
// the actual asynchronous batching/parse/lifecycle path without this test-only switch.
static UIViewController *TFAIChatFixtureController(NSString *root,NSString *project,id<TFAIRuntime> runtime,void(^open)(NSString *,NSUInteger)){UIViewController *chat=TFAIChatController(root,project,runtime,open);[chat setValue:@YES forKey:@"synchronousTestPresentation"];return chat;}
@interface UIViewController (TFAIUIFixturePrivate)
- (void)rebuildDisplay;
@end
@interface TFAIUIFixtureRuntime : NSObject <TFAIRuntime>
@property(nonatomic,copy) TFAIEvent event;
@property(nonatomic,copy) void (^approval)(NSDictionary *,void(^)(BOOL,NSArray<NSNumber *> *));
@property NSString *session;
@end
@implementation TFAIUIFixtureRuntime
- (void)activateSession:(NSString *)s{self.session=s;}
- (void)setBuildAllowed:(BOOL)allowed{}
- (BOOL)configurePermissionPreset:(NSString *)preset paths:(NSArray *)paths error:(NSError **)error{return YES;}
- (void)send:(NSArray *)messages session:(NSString *)session{}
- (void)stop{}
- (void)undo:(TFAIResult)completion{completion(@{@"undone":@YES},nil);}
@end
static NSDictionary *TFAICheckUIRegression(UIViewController *chat,TFAIUIFixtureRuntime *runtime,NSString *project,NSString *root) {
 NSMutableArray *checks=[NSMutableArray new];void(^check)(BOOL,NSString *)=^(BOOL pass,NSString *name){[checks addObject:@{@"name":name,@"pass":@(pass)}];};
 check(runtime.session.length>0,@"session activated on open");
 check([[chat valueForKey:@"attachments"] count]==1,@"selected code staged not sent");
 check([[chat valueForKey:@"messages"] count]==0,@"opening never sends context");
 UITableView *table=[chat valueForKey:@"table"];UITextView *input=[chat valueForKey:@"input"];
 check(table.bounds.size.width>0&&input.bounds.size.height==76,@"phone layout has stable composer");
 runtime.event(@{@"type":@"assistant_start"});runtime.event(@{@"type":@"text",@"text":@"First "});runtime.event(@{@"type":@"text",@"text":@"response"});
 check([[[chat valueForKey:@"messages"] lastObject][@"content"] isEqual:@"First response"],@"stream fragments append once");
 runtime.event(@{@"type":@"tool_result",@"id":@"fixture",@"name":@"read_file",@"result":@{@"content":@"int value = 1;"}});
 runtime.event(@{@"type":@"assistant_start"});runtime.event(@{@"type":@"text",@"text":@"After tool"});
 check([[chat valueForKey:@"messages"] count]==3,@"tool rounds use separate bubbles");
 NSArray *normalized=@[@{@"role":@"user",@"content":@"test"},@{@"role":@"assistant",@"content":@"done"}];runtime.event(@{@"type":@"done",@"state":@"completed",@"messages":normalized});
 check([[chat valueForKey:@"messages"] isEqual:normalized],@"normalized transcript retained");
 check(![[chat valueForKey:@"running"] boolValue],@"done clears active state");
 [chat rebuildDisplay];NSArray *rows=[chat valueForKey:@"displayed"];NSUInteger messageCount=0;for(NSDictionary *row in rows)if([@[@"user",@"assistant"] containsObject:row[@"role"]])messageCount++;check(messageCount==2&&[table numberOfRowsInSection:0]==rows.count&&[[chat valueForKey:@"processRecords"] count]==1,@"table retains messages and separate tool process");
 id cell=[table.dataSource tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];check([cell isKindOfClass:UITableViewCell.class],@"virtualized native message cell");
 UIViewController *settings=TFAISettingsController(project);[settings loadViewIfNeeded];check([settings isKindOfClass:UITableViewController.class],@"native connection settings");
 NSString *idValue=[[chat valueForKey:@"session"] objectForKey:@"id"];[TFAISessions remove:idValue project:project];[NSFileManager.defaultManager removeItemAtPath:root error:nil];BOOL all=YES;for(NSDictionary *c in checks)if(![c[@"pass"] boolValue])all=NO;
 return @{@"pass":@(all),@"checks":checks};
}

static void TFAIRunUIRegressionAsync(void(^completion)(NSDictionary *)) {
 NSString *project=[@"ui-fixture-" stringByAppendingString:NSUUID.UUID.UUIDString];NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:project];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 TFAIUIFixtureRuntime *runtime=[TFAIUIFixtureRuntime new];UIViewController *chat=TFAIChatFixtureController(root,project,runtime,^(NSString *path,NSUInteger line){});TFAIAddContext(chat,@"int value = 1;",@"Selected.c:1");[chat loadViewIfNeeded];chat.view.frame=CGRectMake(0,0,390,844);[chat beginAppearanceTransition:YES animated:NO];[chat endAppearanceTransition];[chat.view setNeedsLayout];[chat.view layoutIfNeeded];
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];__block void(^poll)(void);poll=^{if(![[chat valueForKey:@"loading"] boolValue]||deadline.timeIntervalSinceNow<=0){NSDictionary *report=TFAICheckUIRegression(chat,runtime,project,root);completion(report);poll=nil;}else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),poll);};dispatch_async(dispatch_get_main_queue(),poll);
}
static NSDictionary *TFAIRunUIRegression(void) {
 __block NSDictionary *result=nil;TFAIRunUIRegressionAsync(^(NSDictionary *report){result=report;});NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
 while(!result&&deadline.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
 return result?:@{@"pass":@NO,@"error":@"Use TFAIRunUIRegressionAsync when invoked from main dispatch queue"};
}
UIViewController *TFAIVisualRegression(void) {
 NSString *project=@"ui-visual-fixture";NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:project];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 for(NSDictionary *old in [TFAISessions sessions:project])[TFAISessions remove:old[@"id"] project:project];
 NSMutableDictionary *session=[TFAISessions create:project title:@"修复构建并验证"];
 NSString *fence=[NSString stringWithFormat:@"%C%C%C",(unichar)96,(unichar)96,(unichar)96];
 session[@"messages"]=@[@{@"role":@"user",@"content":@"帮我检查这个编译错误，先给出修改预览。"},@{@"role":@"assistant",@"content":[NSString stringWithFormat:@"错误位于 **Tweak.xm:22**。先补充 **方法声明**，保留 `char *value;` 的原样代码：\n\n%@objc\n@interface UIView (ForgeDemo)\n- (void)refreshContent;\n@end\n%@\n\n**确认差异后再应用**，随后在本机重新编译。",fence,fence]},@{@"role":@"tool",@"content":@"构建完成 · 2.4 秒\n生成 MobileTweak.dylib 和 MobileTweak.deb\n编译成功仍需真机验证插件运行。",@"tool_call_id":@"visual-fixture"},@{@"role":@"assistant",@"content":@"本机编译已通过。你可以查看产物；如需继续调整，我会保留当前修改并在下一次操作前展示差异。"}];
 NSMutableArray *mixed=[session[@"messages"] mutableCopy];NSMutableDictionary *user=[mixed[0] mutableCopy];UIGraphicsBeginImageContextWithOptions(CGSizeMake(160,100),YES,1);[UIColor.systemTealColor setFill];UIRectFill(CGRectMake(0,0,160,100));NSData *photo=UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext());UIGraphicsEndImageContext();user[@"images"]=@[@{@"mime":@"image/png",@"data":[photo base64EncodedStringWithOptions:0]}];user[@"attachments"]=@[@{@"kind":@"image",@"path":@"测试照片.png",@"bytes":@(photo.length)},@{@"kind":@"text",@"path":@"Demo/Tweak.xm",@"bytes":@128,@"preview":@"%hook UIView\n%end"},@{@"kind":@"text",@"path":@"Demo/Headers/A.h",@"bytes":@32,@"preview":@"void refresh(void);"},@{@"kind":@"text",@"path":@"Demo/Headers/B.h",@"bytes":@24,@"preview":@"#define ENABLED 1"}];mixed[0]=user;session[@"messages"]=mixed;
 session[@"followBottom"]=@NO;session[@"scrollY"]=@0;session[@"analysisSummary"]=@"先检查编译器诊断与声明，再预览修改；这是一段用于验证折叠卡片的测试摘要。";session[@"messageTimes"]=@{@"0":@(NSDate.date.timeIntervalSince1970-60),@"1":@(NSDate.date.timeIntervalSince1970-45),@"3":@(NSDate.date.timeIntervalSince1970)};session[@"state"]=@"completed";[TFAISessions save:session project:project error:nil];
 TFAIUIFixtureRuntime *runtime=[TFAIUIFixtureRuntime new];UIViewController *chat=TFAIChatFixtureController(root,project,runtime,^(NSString *path,NSUInteger line){});TFAIAddContext(chat,@"int counter = 1;",@"Tweak.xm · 所选代码");dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSMutableDictionary *checks=[NSMutableDictionary new];UITableView *table=[chat valueForKey:@"table"];NSArray *rows=[chat valueForKey:@"displayed"];NSUInteger index=[rows indexOfObjectPassingTest:^BOOL(NSDictionary *r,NSUInteger i,BOOL *stop){return [r[@"content"] containsString:@"@interface"];}];if(index==NSNotFound)return;UITableViewCell *cell=[table.dataSource tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];UIStackView *stack=[cell valueForKey:@"richContent"];checks[@"separateCodeRenderer"]=@(!stack.hidden&&stack.arrangedSubviews.count==3);checks[@"titleRemoved"]=@(chat.title.length==0);UIView *code=stack.arrangedSubviews.count>1?stack.arrangedSubviews[1]:nil;if(![code respondsToSelector:NSSelectorFromString(@"copyCode")])return;UITextView *codeText=[code valueForKey:@"codeText"];checks[@"syntaxTokensRendered"]=@(TFAICodeTokens([code valueForKey:@"source"]).count>0);checks[@"originalCodePreserved"]=@([codeText.text containsString:@"@interface UIView"]);UIButton *copy=[code valueForKey:@"clipboardButton"];[copy sendActionsForControlEvents:UIControlEventTouchUpInside];checks[@"copyExactSource"]=@([UIPasteboard.generalPasteboard.string isEqual:[code valueForKey:@"source"]]);NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;[[NSJSONSerialization dataWithJSONObject:checks options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[docs stringByAppendingPathComponent:@"ai-code-renderer.json"] atomically:YES];});return chat;
}
extern UIViewController *TFAIApprovalController(NSDictionary *,void(^)(BOOL,NSArray *));
UIViewController *TFAIApprovalVisualRegression(void) {
 NSDictionary *plan=@{@"id":@"visual-plan",@"summary":@"添加缺失方法声明并调整项目编译配置",@"request":@{@"name":@"apply_approved_patch",@"arguments":@{@"reason":@"根据编译器诊断修复声明"}},@"edits":@[@{@"path":@"Tweak.xm",@"kind":@"source",@"reason":@"补充编译器可见的方法声明",@"before":@"#import <UIKit/UIKit.h>\n\n%hook UIView\n",@"after":@"#import <UIKit/UIKit.h>\n\n@interface UIView (ForgeDemo)\n- (void)refreshContent;\n@end\n\n%hook UIView\n"},@{@"path":@"MobileCompiler.json",@"kind":@"configuration",@"before":@"{ \"frameworks\": [\"Foundation\"] }",@"after":@"{ \"frameworks\": [\"Foundation\", \"UIKit\"] }"}]};
 UIViewController *review=TFAIApprovalController(plan,^(BOOL approved,NSArray *indexes){});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
 UITableViewController *table=(id)review;NSMutableDictionary *checks=[NSMutableDictionary new];checks[@"twoEditsWithSharedDiffRows"]=@([table.tableView numberOfRowsInSection:1]==4);checks[@"allSelectedInitially"]=@([[review valueForKey:@"selected"] count]==2);
 NSIndexPath *first=[NSIndexPath indexPathForRow:0 inSection:1],*second=[NSIndexPath indexPathForRow:2 inSection:1];[table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:first];checks[@"selectionMapsOriginalEditIndex"]=@(![[review valueForKey:@"selected"] containsIndex:0]&&[[review valueForKey:@"selected"] containsIndex:1]);[table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:second];checks[@"emptySelectionDisablesApproval"]=@(!review.navigationItem.rightBarButtonItem.enabled);[table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:first];[table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:second];
 for(NSUInteger n=0;n<2;n++)[table.tableView.dataSource tableView:table.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:n*2+1 inSection:1]];checks[@"usesExistingGitRenderer"]=@([[review valueForKey:@"diffViews"] count]==2);NSString *patch=TFReviewPatch(@"one\ntwo\nthree\n",@"ONE\ntwo\nTHREE\n",@"Sample.m");checks[@"unchangedContextPreserved"]=@([patch containsString:@" two\n"]&&[patch containsString:@"-one\n"]&&[patch containsString:@"+ONE\n"]);checks[@"noNewlineMarkerSupported"]=@([TFReviewPatch(@"old",@"new",@"File.m") containsString:@"No newline at end of file"]);checks[@"identicalTextHasNoHunk"]=@(![TFReviewPatch(@"same",@"same",@"File.m") containsString:@"@@"]);
 NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;[[NSJSONSerialization dataWithJSONObject:checks options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[docs stringByAppendingPathComponent:@"ai-approval-selection-test.json"] atomically:YES];
 });return review;
}
// build72 visual fixtures: fake runtime and local samples, never real model traffic.
#import "../App/AI/UI/TFAITestDetail.h"
UIViewController *TFAIControlsVisualRegression(void){
 UIViewController *chat=TFAIVisualRegression();dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[chat setValue:@{@"id":@"visual-only",@"name":@"演示连接",@"protocol":@"chat",@"baseURL":@"https://api.openai.com/v1",@"model":@"o3"} forKey:@"selectedConnection"];[chat setValue:@"medium" forKey:@"reasoningEffort"];[chat performSelector:NSSelectorFromString(@"updateControls")];[chat performSelector:NSSelectorFromString(@"modelControls")];});return chat;
}
UIViewController *TFAIProbeVisualRegression(void){
 UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(384,256)];UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *c){[UIColor.whiteColor setFill];[c fillRect:CGRectMake(0,0,384,256)];[UIColor.systemRedColor setFill];[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(35,70,110,110)] fill];[UIColor.systemBlueColor setFill];[c fillRect:CGRectMake(235,70,110,110)];}];
 NSMutableDictionary *connection=[@{@"id":@"visual-sample-only",@"name":@"内置演示连接",@"model":@"vision-fixture",@"protocol":@"gemini",@"baseURL":@"https://visual.example.invalid/v1beta"} mutableCopy];NSDictionary *record=@{@"state":@"unknown",@"detail":@"模型已响应，但本次回答没有覆盖图中两种形状的颜色；这不代表模型不支持图片。",@"diagnostics":@{@"protocol":@"gemini",@"model":@"vision-fixture",@"endpoint":@"https://visual.example.invalid/v1beta/models/vision-fixture:generateContent",@"httpStatus":@200,@"timestamp":@(NSDate.date.timeIntervalSince1970),@"duration":@1.82,@"requestSummary":@"Look at the attached image. Identify the color of the circle and the color of the square. Return a JSON object with keys circle and square.",@"expected":@"circle: red; square: blue",@"testImage":[UIImagePNGRepresentation(image) base64EncodedStringWithOptions:0],@"responseText":@"图中有两个彩色图形。",@"reason":@"回答未提供每种形状对应的颜色，本次未证实。"}};return TFAITestDetailController(connection,@"image",record,NO);
}

#import "../App/AI/LiveActivity/TFAILiveActivity.h"
@interface UIViewController (TFChat93Fixture)
- (void)toggleFoldID:(NSString *)fold;
- (void)jumpBottom;
@end
@interface TFChat93Runtime : TFAIUIFixtureRuntime
@end
@implementation TFChat93Runtime
- (void)send:(NSArray *)messages session:(NSString *)session{NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;[[NSJSONSerialization dataWithJSONObject:messages options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[docs stringByAppendingPathComponent:@"ai-chat93-resend.json"] atomically:YES];NSString *mid=NSUUID.UUID.UUIDString;self.event(@{@"type":@"assistant_start",@"messageID":mid});self.event(@{@"type":@"text",@"text":@"已收到重新编辑的消息，原会话记录已保留。"});NSMutableArray *reply=[messages mutableCopy];[reply addObject:@{@"role":@"assistant",@"messageID":mid,@"content":@"已收到重新编辑的消息，原会话记录已保留。",@"timestamp":@(NSDate.date.timeIntervalSince1970)}];self.event(@{@"type":@"done",@"state":@"completed",@"messages":reply});}
@end
UIViewController *TFAIChat93Regression(void){
 NSString *scope=@"chat93-fixture";NSMutableDictionary *session=[TFAISessions create:scope title:@"会话交互验证"];
 session[@"messages"]=@[@{@"role":@"user",@"messageID":@"fixture-user",@"content":@"检查插件产物并给出总结",@"timestamp":@(NSDate.date.timeIntervalSince1970-30)},@{@"role":@"assistant",@"messageID":@"fixture-analysis",@"content":@"我先读取包信息，再核对文件架构。",@"tool_calls":@[@{@"id":@"fixture-tool"}]},@{@"role":@"tool",@"tool_call_id":@"fixture-tool",@"content":@"已读取测试产物"},@{@"role":@"assistant",@"messageID":@"fixture-final",@"content":@"**检查总结**\n\n产物信息已读取。下方将继续整理结果。",@"timestamp":@(NSDate.date.timeIntervalSince1970)}];
 session[@"turnTimings"]=@{@"fixture-user":@{@"start":@(NSDate.date.timeIntervalSince1970-30),@"end":@(NSDate.date.timeIntervalSince1970),@"duration":@30}};session[@"analysisSummaries"]=@{@"fixture-analysis":@"核对 control、安装目录和 CPU 架构，三者需要分别判断。"};session[@"processRecords"]=@[@{@"id":@"fixture-tool",@"name":@"read_file_with_a_very_long_name_that_should_wrap_without_overlapping_the_expanded_content",@"status":@"completed",@"assistantMessageID":@"fixture-analysis",@"result":@{@"content":@"Architecture: iphoneos-arm64"}}];[TFAISessions save:session project:scope error:nil];
 NSString *project=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"Chat94Fixture"];[NSFileManager.defaultManager createDirectoryAtPath:project withIntermediateDirectories:YES attributes:nil error:nil];[@"// Local fixture only\n" writeToFile:[project stringByAppendingPathComponent:@"Tweak.xm"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 TFChat93Runtime *runtime=[TFChat93Runtime new];UIViewController *chat=TFAIChatFixtureController(project,scope,runtime,^(NSString *p,NSUInteger l){});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
 NSMutableArray *checks=[NSMutableArray new];void(^check)(BOOL,NSString *)=^(BOOL pass,NSString *name){[checks addObject:@{@"name":name,@"pass":@(pass)}];};
 if([NSProcessInfo.processInfo.arguments containsObject:@"--chat103-fixture"]){
 NSMutableDictionary *active=[chat valueForKey:@"session"];active[@"turnTimings"]=@{@"fixture-user":@{@"start":@(NSDate.date.timeIntervalSince1970-5)}};
 NSMutableArray *liveMessages=[[chat valueForKey:@"messages"] mutableCopy];[liveMessages filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *m,NSDictionary *bindings){return ![m[@"role"] isEqual:@"tool"];}]];[chat setValue:liveMessages forKey:@"messages"];
 NSMutableArray *records=[chat valueForKey:@"processRecords"];NSMutableDictionary *tool=[records[0] mutableCopy];tool[@"name"]=@"classdump_export";tool[@"status"]=@"running";tool[@"startedAt"]=@(NSDate.date.timeIntervalSince1970-3);tool[@"summary"]=@"20% · 正在扫描";[tool removeObjectForKey:@"result"];records[0]=tool;
 [chat setValue:@YES forKey:@"running"];[chat setValue:@NO forKey:@"dirtyRender"];[chat rebuildDisplay];UITableView *table=[chat valueForKey:@"table"];NSArray *initial=[chat valueForKey:@"displayed"];NSString *before=initial[1][@"foldTitle"];CGPoint offset=table.contentOffset;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.7*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSArray *next=[chat valueForKey:@"displayed"];check(![before isEqual:next[1][@"foldTitle"]],@"collapsed header advances without tapping or model events");UIButton *header=[[table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]] valueForKey:@"foldHeader"];check([header.configuration.title isEqual:next[1][@"foldTitle"]],@"visible header matches live clock snapshot");check(fabs(table.contentOffset.y-offset.y)<1,@"clock tick preserves viewport offset");
 [chat toggleFoldID:@"turn-fixture-user"];[chat toggleFoldID:@"fixture-tool"];NSArray *open=[chat valueForKey:@"displayed"];NSString *toolBefore=open[4][@"foldTitle"];CGPoint openOffset=table.contentOffset;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.7*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSArray *updated=[chat valueForKey:@"displayed"];check(![toolBefore isEqual:updated[4][@"foldTitle"]]&&[updated[4][@"foldTitle"] containsString:@"20%"],@"expanded tool elapsed advances and preserves real progress");check(fabs(table.contentOffset.y-openOffset.y)<1,@"expanded tool timer preserves scroll position");
 [chat performSelector:NSSelectorFromString(@"handleEvent:") withObject:@{@"type":@"tool_progress",@"id":@"fixture-tool",@"name":@"classdump_export",@"progress":@.65,@"message":@"正在输出头文件"}];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.3*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSArray *progress=[chat valueForKey:@"displayed"];check([progress[4][@"foldTitle"] containsString:@"65%"]&&[progress[4][@"display"] containsString:@"正在输出头文件"],@"tool event updates title and expanded detail without taps");NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;[[NSJSONSerialization dataWithJSONObject:checks options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[docs stringByAppendingPathComponent:@"ai-chat103-tests.json"] atomically:YES];});});});return;
 }
 NSArray *rows=[chat valueForKey:@"displayed"];check(rows.count==3&&[rows[1][@"groupHeader"] boolValue],@"only final reply is visible outside process disclosure");
 [chat toggleFoldID:@"turn-fixture-user"];rows=[chat valueForKey:@"displayed"];check(rows.count==6&&[rows[4][@"foldID"] isEqual:@"fixture-tool"]&&! [rows[4][@"expanded"] boolValue],@"process children appear with separate collapsed tool details");
 [chat toggleFoldID:@"fixture-tool"];rows=[chat valueForKey:@"displayed"];check([rows[4][@"expanded"] boolValue],@"nested tool expands");[chat toggleFoldID:@"fixture-tool"];[chat toggleFoldID:@"turn-fixture-user"];
 UITableView *table=[chat valueForKey:@"table"];UIView *composer=[chat valueForKey:@"composer"];[chat.view layoutIfNeeded];check(CGRectGetMaxY(table.frame)<=CGRectGetMinY(composer.frame)+1,@"chat viewport ends above composer");
 NSDictionary *message=rows.firstObject;UIContextMenuConfiguration *menu=[(id<UITableViewDelegate>)chat tableView:table contextMenuConfigurationForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] point:CGPointZero];check(menu!=nil&&[chat respondsToSelector:NSSelectorFromString(@"editMessage:")],@"sent message provides edit/resend entry point");
 [chat setValue:@YES forKey:@"running"];UILabel *status=[chat valueForKey:@"status"];status.text=@"正在整理分析结果";[chat rebuildDisplay];rows=[chat valueForKey:@"displayed"];check([rows.lastObject[@"processing"] boolValue],@"loading status exists in transcript while running");
 TFAISetSessionLiveRun(scope,session[@"id"],YES);check(TFAISessionHasLiveRun(scope,session[@"id"]),@"session list reads the active run registry");
 UIViewController *temporary=[UIViewController new];[chat.navigationController pushViewController:temporary animated:NO];[chat.navigationController popViewControllerAnimated:NO];rows=[chat valueForKey:@"displayed"];check([rows.lastObject[@"processing"] boolValue],@"returning to chat retains current processing row");
 TFAILiveUpdate(@"正在整理分析结果",1,3);
 [chat jumpBottom];NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;[[NSJSONSerialization dataWithJSONObject:checks options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[docs stringByAppendingPathComponent:@"ai-chat93-tests.json"] atomically:YES];[TFAILiveStatus() writeToFile:[docs stringByAppendingPathComponent:@"ai-chat93-live.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 if([NSProcessInfo.processInfo.arguments containsObject:@"--chat94-fixture"]){
 UITableViewCell *cell=[table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:rows.count-1 inSection:0]];UIStackView *rich=[cell valueForKey:@"richContent"];UIStackView *line=(id)rich.arrangedSubviews.firstObject;UILabel *label=(id)line.arrangedSubviews.firstObject;UILabel *shine=[label valueForKey:@"shine"];CALayer *mask=shine.layer.mask;CGFloat phase=((CALayer *)mask.presentationLayer).position.x;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.4*NSEC_PER_SEC),dispatch_get_main_queue(),^{CGFloat next=((CALayer *)mask.presentationLayer).position.x;check([mask animationForKey:@"sweep"]!=nil&&fabs(next-phase)>1,@"shimmer presentation position moves over time");[chat performSelector:NSSelectorFromString(@"sessionFiles")];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.4*NSEC_PER_SEC),dispatch_get_main_queue(),^{UIViewController *files=chat.navigationController.topViewController;NSArray *items=[files valueForKey:@"items"];check([files.title isEqual:@"会话文件"]&&items.count==1&&[items[0][@"folder"] boolValue],@"session files exposes only linked project fixture");[(id<UITableViewDelegate>)files tableView:[files valueForKey:@"tableView"] didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.2*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSArray *children=[chat.navigationController.topViewController valueForKey:@"items"];check(children.count==1&&[children[0][@"name"] isEqual:@"Tweak.xm"],@"session folder opens real local child file");[[NSJSONSerialization dataWithJSONObject:checks options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[docs stringByAppendingPathComponent:@"ai-chat94-tests.json"] atomically:YES];});});});
 }
 if([NSProcessInfo.processInfo.arguments containsObject:@"--notification-fixture"]){UIBackgroundTaskIdentifier lease=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"Notification regression" expirationHandler:^{}];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{runtime.event(@{@"type":@"done",@"state":@"completed"});TFAILiveEnd(YES);[UIApplication.sharedApplication endBackgroundTask:lease];});}
 if([NSProcessInfo.processInfo.arguments containsObject:@"--edit-fixture"]){[chat setValue:@NO forKey:@"running"];TFAISetSessionLiveRun(scope,session[@"id"],NO);[chat performSelector:NSSelectorFromString(@"updateSend")];[chat rebuildDisplay];[chat performSelector:NSSelectorFromString(@"editMessage:") withObject:[[chat valueForKey:@"messages"] firstObject]];}

 });return chat;
}
