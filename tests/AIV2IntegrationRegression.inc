@interface TMCNavigationController (TFAIThemeFixture)
- (void)applyStudioAppearance;
@end
#import "../App/AI/AIV2Contracts.h"
#import "AIV2SessionsUIRegression.inc"
#import "AIChatControlsV4Regression.inc"
#import "AIChatViewportRegression.inc"
#import "AIBuildAttachmentRegression.inc"
#import "AIV2ChatRegression.inc"
#import "AIPermissionPersistenceRegression.inc"
#import "AIV2AttachmentsUI.inc"
#import "AIV2RuntimeRegression.inc"
#import "AIChatPresentationRegression.inc"
#import "AIConnectionDetailsRegression.inc"
#import "AIPermissionV4Regression.inc"
static void TFAIV3WorkspaceRegression(UINavigationController *nav,void(^completion)(NSDictionary *)){
 NSString *root=[Docs() stringByAppendingPathComponent:[@"Imported-WorkspaceTest-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];[@"Package: test.workspace\nName: Workspace test\nVersion: 1.0\nAuthor: Fixture\n" writeToFile:[root stringByAppendingPathComponent:@"control"] atomically:YES encoding:NSUTF8StringEncoding error:nil];NSString *scope=TFAIProjectID(root);NSCAssert([[TFAIInternalProjects() valueForKey:@"id"] containsObject:scope],@"Imported projects must be discoverable by AI");NSMutableDictionary *session=[TFAISessions create:scope title:@"Workspace test"];session[@"storageProjectID"]=scope;[TFAISessions save:session project:scope error:nil];UIViewController *list=nav.topViewController;OpenAISession(nav,session,nil);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSMutableDictionary *checks=[NSMutableDictionary new];TFAIProjectWorkspace *workspace=[nav.topViewController isKindOfClass:TFAIProjectWorkspace.class]?(id)nav.topViewController:nil;checks[@"directListToWorkspace"]=@(workspace&&nav.viewControllers.count==2&&nav.viewControllers[0]==list);if(workspace){[workspace loadViewIfNeeded];UITextView *input=[workspace.chat valueForKey:@"input"];input.text=@"draft before switching";[workspace showEditor];checks[@"switchToSameEditor"]=@(workspace.active==workspace.editor&&workspace.editor.parentViewController==workspace);workspace.switcher.selectedSegmentIndex=0;[workspace changePage];checks[@"switchBackKeepsChatAndDraft"]=@(workspace.active==workspace.chat&&[input.text isEqual:@"draft before switching"]);UIButton *permission=[workspace.chat valueForKey:@"permissionButton"];checks[@"permissionInComposer"]=@(!permission.hidden);checks[@"switcherInNavigationBar"]=@(workspace.navigationItem.titleView==workspace.switcher);[nav popViewControllerAnimated:NO];checks[@"backReturnsToConversationList"]=@(nav.topViewController==list);}
 [TFAISessions remove:session[@"id"] project:scope];[NSFileManager.defaultManager removeItemAtPath:root error:nil];BOOL passed=checks.count==6;for(NSNumber *value in checks.allValues)passed&=value.boolValue;completion(@{@"passed":@(passed),@"checks":checks});});
}
static void TFAIV2NavigationRegression(UITabBarController *tabs,void (^completion)(NSDictionary *)) {
 NSMutableArray *checks=[NSMutableArray new];void(^check)(BOOL,NSString *)=^(BOOL ok,NSString *name){[checks addObject:@{@"ok":@(ok),@"name":name}];};
 TFAIBuildAttachmentRegression(check);TFAIChatPresentationRegression(check);TFAIConnectionDetailsRegression(check);TFAIChatControlsV4Regression(check);TFAIPermissionV4PolicyRegression(check);[tabs loadViewIfNeeded];check(tabs.viewControllers.count==3,@"three native root tabs");
 NSInteger originalTheme=[NSUserDefaults.standardUserDefaults integerForKey:@"StudioTheme"];for(NSNumber *theme in @[@1,@2,@0]){[NSUserDefaults.standardUserDefaults setInteger:theme.integerValue forKey:@"StudioTheme"];for(UINavigationController *stack in tabs.viewControllers){[(id)stack applyStudioAppearance];UIUserInterfaceStyle expected=theme.integerValue==1?UIUserInterfaceStyleDark:theme.integerValue==2?UIUserInterfaceStyleLight:UIUserInterfaceStyleUnspecified;check(stack.overrideUserInterfaceStyle==expected,[NSString stringWithFormat:@"%@ follows theme %@",stack.tabBarItem.title,theme]);}}[NSUserDefaults.standardUserDefaults setInteger:originalTheme forKey:@"StudioTheme"];for(UINavigationController *stack in tabs.viewControllers)[(id)stack applyStudioAppearance];

 UITableViewController *settings=(id)[(UINavigationController *)tabs.viewControllers[2] topViewController];[settings loadViewIfNeeded];check([settings.tableView.dataSource numberOfSectionsInTableView:settings.tableView]==7,@"settings separates AI and About");check([[settings.tableView.dataSource tableView:settings.tableView titleForHeaderInSection:1] isEqual:@"AI"],@"AI immediately below Git");check([[[settings.tableView.dataSource tableView:settings.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]] textLabel].text isEqual:@"AI 开发助手"],@"AI settings row routes independently");
 UITableViewController *testPage=[[NSClassFromString(@"TFAITestResults") alloc]initWithStyle:UITableViewStyleInsetGrouped];[testPage setValue:[@{@"name":@"Fixture",@"model":@"fixture",@"testResults":@{@"text":@{@"state":@"pass",@"detail":@"Fixture passed"},@"stream":@{@"state":@"fail",@"detail":@"Fixture failure"}}} mutableCopy] forKey:@"connection"];[testPage loadViewIfNeeded];check([[[testPage.tableView.dataSource tableView:testPage.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]] textLabel].text containsString:@"✅"],@"probe results visibly show pass");check([[[testPage.tableView.dataSource tableView:testPage.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]] textLabel].text containsString:@"❌"],@"probe results visibly show failure");

 check([tabs.viewControllers[0].tabBarItem.title isEqual:@"项目"]&&[tabs.viewControllers[1].tabBarItem.title isEqual:@"AI 会话"]&&[tabs.viewControllers[2].tabBarItem.title isEqual:@"设置"],@"project AI settings order");
 tabs.selectedIndex=1;UINavigationController *nav=(id)tabs.selectedViewController;UIViewController *original=nav.topViewController;[original loadViewIfNeeded];NSUInteger count=[TFAISessions summaries:nil].count;
 UIViewController *child=[UIViewController new];[nav pushViewController:child animated:NO];check(child.hidesBottomBarWhenPushed,@"detail hides root navigation");[nav popViewControllerAnimated:NO];check(nav.topViewController==original&&tabs.selectedIndex==1,@"return retains selected AI root");check([TFAISessions summaries:nil].count==count,@"root navigation does not create empty conversations");
 [TFAISessions create:@"v2-navigation-fixture" title:@"temporary"];for(NSDictionary *r in [TFAISessions summaries:@"v2-navigation-fixture"])[TFAISessions remove:r[@"id"] project:@"v2-navigation-fixture"];
 TFAIV3WorkspaceRegression(nav,^(NSDictionary *workspace){
 TFAIV2RunSessionHomeRegression(^(NSDictionary *home){
 BOOL all=YES;for(NSDictionary *r in checks)all&=[r[@"ok"] boolValue];
 TFAIRunV2ChatRegression(^(NSDictionary *chat){
 TFAIV2AttachmentsRegression(^(NSDictionary *attachments){
 TFAIRunV2RuntimeRegression(^(NSDictionary *runtime){
 TFAIRunPermissionV4Regression(^(NSDictionary *permissions){
 TFAIRunPermissionPersistenceRegression(^(NSDictionary *preferences){
 completion(@{@"passed":@(all&&[workspace[@"passed"] boolValue]&&[home[@"passed"] boolValue]&&[chat[@"pass"] boolValue]&&[attachments[@"passed"] integerValue]==[attachments[@"total"] integerValue]&&[runtime[@"pass"] boolValue]&&[permissions[@"pass"] boolValue]&&[preferences[@"pass"] boolValue]),@"tabTitles":@[[tabs.viewControllers[0] tabBarItem].title?:@"",[tabs.viewControllers[1] tabBarItem].title?:@"",[tabs.viewControllers[2] tabBarItem].title?:@""],@"checks":checks,@"sessionHome":home,@"chat":chat,@"attachments":attachments,@"runtime":runtime,@"permissions":permissions,@"permissionPersistence":preferences,@"workspace":workspace});
 });});});});});});});
}
