// Exercise production workspace bridge, approvals, rebinding and project tools without network.
@interface NSObject (Workspace133Calls)
- (void)runCall:(NSUInteger)index;
- (NSArray *)requestSchemas;
@end
static id<TFAIRuntimeV2> Workspace133Runtime;
UIViewController *TFAIWorkspace133Regression(void){
 UIViewController *screen=[UIViewController new];screen.title=@"普通会话项目工具验证";screen.view.backgroundColor=UIColor.systemBackgroundColor;
 NSMutableArray *checks=[NSMutableArray new];void(^check)(BOOL,NSString *)=^(BOOL ok,NSString *name){[checks addObject:@{@"pass":@(ok),@"name":name}];};
 NSMutableDictionary *owner=[NSMutableDictionary new];NSString *name=[@"Workspace133-" stringByAppendingString:NSUUID.UUID.UUIDString];__block NSString *createdRoot=nil;__block NSUInteger approvals=0;
 id<TFAIRuntimeV2> runtime=TFAICreateRuntime(@"",@"general",^(NSString *tool,NSDictionary *args,TFAIResult done){AIWorkspaceTool(owner,tool,args,done);});Workspace133Runtime=runtime;[runtime activateSession:NSUUID.UUID.UUIDString];[runtime setInteractionMode:@"develop"];
 check([runtime configurePermissionPreset:@"full" paths:@[] error:nil],@"ordinary conversation accepts permission before project creation");
 NSArray *calls=@[@{@"id":@"ws-list",@"name":@"list_projects",@"arguments":@{}},@{@"id":@"ws-create",@"name":@"create_project",@"arguments":@{@"name":name,@"template":@"objectivec"}},@{@"id":@"ws-file",@"name":@"create_file",@"arguments":@{@"path":@"Extra.c",@"content":@"int extra(void){return 133;}"}},@{@"id":@"ws-build",@"name":@"build_project",@"arguments":@{}}];
 [(id)runtime setValue:@YES forKey:@"running"];[(id)runtime setValue:@"develop" forKey:@"requestMode"];[(id)runtime setValue:@{} forKey:@"promptEnvironment"];[(id)runtime setValue:[NSMutableArray new] forKey:@"messages"];[(id)runtime setValue:[NSMutableDictionary new] forKey:@"toolStarts"];[(id)runtime setValue:calls forKey:@"calls"];
 runtime.approval=^(NSDictionary *plan,void(^decision)(BOOL,NSArray *)){approvals++;decision(YES,nil);};
 runtime.event=^(NSDictionary *event){if([event[@"type"] isEqual:@"workspace_bound"]){createdRoot=event[@"root"];check([event[@"name"] isEqual:name],@"workspace bound in original general conversation");}
 if(![event[@"type"] isEqual:@"tool_result"])return;check(!event[@"result"][@"error"],event[@"name"]);if([event[@"name"] isEqual:@"create_project"])check(!event[@"result"][@"root"],@"tool result hides sandbox absolute path from provider");
 if(![event[@"id"] isEqual:@"ws-build"])return;
 check([event[@"result"][@"success"] boolValue],@"new project compiles using embedded compiler");check(approvals==1,@"creation confirmed once then scoped full access applies");check([NSFileManager.defaultManager fileExistsAtPath:[createdRoot stringByAppendingPathComponent:@"Extra.c"]],@"new file created inside selected project");
 check([[(id)runtime valueForKey:@"projectID"] isEqual:@"general"],@"conversation storage scope remains general");check([[(id)runtime valueForKey:@"workspaceToolID"] isEqual:TFAIProjectID(createdRoot)],@"project tool ledger is isolated by real project identity");
 [(id)runtime setValue:@NO forKey:@"running"];[runtime stop];runtime.event=nil;runtime.approval=nil;
 void(^finish)(void)=^{[NSFileManager.defaultManager removeItemAtPath:createdRoot error:nil];BOOL passed=YES;for(NSDictionary *c in checks)passed&=[c[@"pass"] boolValue];JSONWrite(@{@"pass":@(passed),@"checks":checks},[Docs() stringByAppendingPathComponent:@"ai-workspace133-tests.json"],nil);Workspace133Runtime=nil;};
 AIWorkspaceTool(owner,@"create_project",@{@"name":name,@"template":@"objectivec"},^(NSDictionary *r,NSError *e){check(e&&[NSFileManager.defaultManager fileExistsAtPath:[createdRoot stringByAppendingPathComponent:@"Extra.c"]],@"duplicate creation leaves existing project intact");
 AIWorkspaceTool(owner,@"select_project",@{@"project_id":TFAIProjectID(createdRoot)},^(NSDictionary *r,NSError *e){check(!e&&[r[@"root"] isEqual:createdRoot],@"select project resolves stable local ID");
 AIWorkspaceTool(owner,@"create_project",@{@"name":@"../outside",@"template":@"logos"},^(NSDictionary *r,NSError *e){check(e!=nil,@"project names reject traversal");
 AIWorkspaceTool(owner,@"clone_project",@{@"name":@"invalid-url-fixture",@"url":@"https://user:password@example.invalid/repo"},^(NSDictionary *r,NSError *e){check(e!=nil,@"clone rejects URLs containing credentials without network");
 NSString *cancelName=[name stringByAppendingString:@"-cancelled"];AIWorkspaceTool(owner,@"create_project",@{@"name":cancelName,@"template":@"logos"},^(NSDictionary *r,NSError *e){check(e!=nil&&![NSFileManager.defaultManager fileExistsAtPath:[Projects() stringByAppendingPathComponent:cancelName]],@"cancelled queued creation never publishes project");finish();});AIWorkspaceTool(owner,@"cancel_workspace",@{},^(NSDictionary *r,NSError *e){});
 });});});});

 };
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[(id)runtime runCall:0];});return screen;
}
