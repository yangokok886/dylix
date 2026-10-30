// Simulator-only: real UIKit forms and App Keychain with disposable credentials.
static UIViewController *GitFriendlyRegression(void){
 TFGitSettings *settings=[[TFGitSettings alloc] initWithStyle:UITableViewStyleInsetGrouped];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
 NSArray *prior=TMCGitPreferences.accounts;NSDictionary *identity=TMCGitPreferences.global;
 [NSUserDefaults.standardUserDefaults setObject:@[] forKey:@"GitAccounts"];
 NSString *identifier=NSUUID.UUID.UUIDString;NSDictionary *account=@{@"id":identifier,@"origin":@"https://github.com",@"username":@"fixture-user",@"default":@YES};
 NSMutableDictionary *results=[NSMutableDictionary new];NSError *error=nil;
 results[@"accountSaved"]=@([TMCGitPreferences saveAccount:account token:@"fixture-only-token" error:&error]);
 [settings quickSetupForOrigin:@"https://github.com"];UINavigationController *sheet=(id)settings.presentedViewController;
 AfterGitNavigation(sheet,^{TFGitForm *form=(id)sheet.topViewController;[form loadViewIfNeeded];
 results[@"quickSetupRestoresUsername"]=@([form.fields[2].text isEqual:@"fixture-user"]);
 results[@"tokenStatusVisible"]=@([form.specs[3][@"title"] containsString:@"已保存"]);
 results[@"tokenRemainsSecureAndBlank"]=@(form.fields[3].secureTextEntry&&!form.fields[3].text.length);
 results[@"blankTokenSaveAccepted"]=@(form.submit(@[@"Fixture",@"fixture@example.com",@"fixture-user",@""]));
 results[@"blankTokenRetained"]=@([AccountSecret(account)[@"token"] isEqual:@"fixture-only-token"]);
 [sheet dismissViewControllerAnimated:YES completion:^{
 [settings editAccount:TMCGitPreferences.accounts.firstObject];UINavigationController *editSheet=(id)settings.presentedViewController;
 AfterGitNavigation(editSheet,^{TFGitForm *edit=(id)editSheet.topViewController;[edit loadViewIfNeeded];results[@"accountEditRestoresUsername"]=@([edit.fields[1].text isEqual:@"fixture-user"]);
 results[@"replacementAccepted"]=@(edit.submit(@[@"https://github.com",@"fixture-user",@"fixture-replacement-token"]));results[@"replacementStored"]=@([AccountSecret(account)[@"token"] isEqual:@"fixture-replacement-token"]);results[@"noDuplicateAccount"]=@(TMCGitPreferences.accounts.count==1);
 NSString *root=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"FriendlyGitFixture"];
 TFGitPanel *panel=(id)TMCGitController(root,nil);[panel loadViewIfNeeded];panel.snapshot=@{@"branch":@"main",@"remote":@"https://github.com/fixture/project.git",@"files":@[]};
 NSArray *labels=@[@"远程仓库与账号",@"保存本机版本",@"上传到远程仓库",@"下载仓库更新",@"自动保存与自动上传"];BOOL matches=YES;for(NSUInteger row=0;row<labels.count;row++)matches=matches&&[[panel tableView:panel.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]].textLabel.text isEqual:labels[row]];results[@"fiveSimpleActions"]=@(matches);results[@"advancedNotOnMainPage"]=@([panel tableView:panel.tableView numberOfRowsInSection:1]==2);panel.advanced=YES;results[@"advancedActionsRetained"]=@([panel tableView:panel.tableView numberOfRowsInSection:1]==6);
 [TMCGitPreferences deleteAccount:identifier];[NSUserDefaults.standardUserDefaults setObject:prior forKey:@"GitAccounts"];[TMCGitPreferences saveGlobal:identity];
 results[@"testCredentialRemoved"]=@(![AccountSecret(account)[@"token"] length]);
 [editSheet dismissViewControllerAnimated:YES completion:^{NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;[[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[docs stringByAppendingPathComponent:@"git-friendly-test.json"] atomically:YES];}];
 });}];});});return settings;
}
