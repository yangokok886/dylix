// Simulator-only RPC fixture. Input file is consumed immediately, secrets are
// stored by the app's actual Keychain code; output never includes credentials.
UIViewController *TMCGitLiveRegression(void){
 NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
 NSString *request=[docs stringByAppendingPathComponent:@"git-live-request.json"];
 NSData *raw=[NSData dataWithContentsOfFile:request];[NSFileManager.defaultManager removeItemAtPath:request error:nil];
 NSDictionary *job=raw?[NSJSONSerialization JSONObjectWithData:raw options:0 error:nil]:@{};
 NSString *root=job[@"root"],*op=job[@"operation"];NSDictionary *input=job[@"input"]?:@{};
 TFGitPanel *panel=(id)TMCGitController(root,nil);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.4*NSEC_PER_SEC),dispatch_get_main_queue(),^{
 dispatch_async(TMCGitService.queue,^{@autoreleasepool{NSError *error=nil;id result=nil;TMCGitService *g=panel.git;
 if([op isEqual:@"credential"])result=@([TMCGitService saveCredentialForURL:input[@"url"] username:input[@"username"] token:input[@"token"] error:&error]);
 if([op isEqual:@"account"]){result=@([TMCGitPreferences saveAccount:@{@"origin":@"https://github.com",@"username":input[@"username"],@"default":@YES} token:input[@"token"] error:&error]);}
 if([op isEqual:@"credentialCleanup"]){[TMCGitService deleteCredentialForURL:input[@"url"]];for(NSDictionary *a in TMCGitPreferences.accounts)if([a[@"username"] isEqual:input[@"username"]])[TMCGitPreferences deleteAccount:a[@"id"]];result=@YES;}
 if([op isEqual:@"upstream"])result=@([g setUpstream:input[@"name"] error:&error]);
 if([op isEqual:@"status"])result=[g status:&error];
 if([op isEqual:@"init"])result=@([g initialize:&error]);
 if([op isEqual:@"stage"])result=@([g stage:input[@"paths"] remove:[input[@"remove"] boolValue] error:&error]);
 if([op isEqual:@"commit"])result=[g commit:input[@"message"] name:@"TweakForge Test" email:@"test@example.com" error:&error];
 if([op isEqual:@"branch"])result=@([g branch:input[@"name"] action:input[@"action"] error:&error]);
 if([op isEqual:@"remote"])result=@([g setRemote:input[@"url"] error:&error]);
 if([op isEqual:@"clone"])result=@([g cloneURL:input[@"url"] error:&error]);
 if([op isEqual:@"network"])result=@([g network:input[@"action"] name:@"TweakForge Test" email:@"test@example.com" error:&error]);
 if([op isEqual:@"conflicts"])result=[g conflicts:&error];
 if([op isEqual:@"resolve"])result=@([g resolve:input[@"path"] choice:input[@"choice"] text:input[@"text"] expected:input[@"fingerprint"] error:&error]);
 if([op isEqual:@"settingsUI"]){dispatch_async(dispatch_get_main_queue(),^{[panel.navigationController pushViewController:TMCGitSettingsController(nil) animated:NO];});result=@YES;}
 if([op isEqual:@"ui"]){dispatch_async(dispatch_get_main_queue(),^{[panel reload];});result=@YES;}
 NSDictionary *response=@{@"result":result?:NSNull.null,@"error":error.localizedDescription?:@""};NSData *data=[NSJSONSerialization dataWithJSONObject:response options:NSJSONWritingPrettyPrinted error:nil];[data writeToFile:[docs stringByAppendingPathComponent:@"git-live-response.json"] atomically:YES];
 }});
 });return panel;
}
