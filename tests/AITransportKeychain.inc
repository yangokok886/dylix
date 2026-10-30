// Include only in simulator regression entrypoint after AIContracts.h.
// Uses fresh random account IDs and dummy fixture keys; restores all preferences.
static NSDictionary *TFAITransportRunKeychainRegression(void){
 NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;NSArray *keys=@[@"TFAI.Connections.v1",@"TFAI.DefaultConnection.v1",@"TFAI.ProjectConnections.v1"];NSMutableDictionary *backup=[NSMutableDictionary new];for(NSString *key in keys)backup[key]=[defaults objectForKey:key]?:NSNull.null;
 NSMutableArray *checks=[NSMutableArray new];void (^check)(BOOL,NSString *)=^(BOOL ok,NSString *name){[checks addObject:@{@"name":name,@"ok":@(ok)}];};NSString *a=NSUUID.UUID.UUIDString,*b=NSUUID.UUID.UUIDString,*project=NSUUID.UUID.UUIDString;NSError *error=nil;
 @try{
  NSMutableDictionary *connection=[@{@"id":a,@"name":@"AI credential fixture",@"protocol":@"chat",@"baseURL":@"https://example.test/v1",@"model":@"",@"models":@[]} mutableCopy];
  check([TFAIConnections save:connection secret:@"fixture-ai-token-one" error:&error],@"save new account with empty model");
  check([[TFAIConnections secret:a] isEqual:@"fixture-ai-token-one"],@"keychain readback");
  connection[@"name"]=@"Renamed fixture";check([TFAIConnections save:connection secret:nil error:&error]&&[[TFAIConnections secret:a] isEqual:@"fixture-ai-token-one"],@"nil retains credential after metadata save");
  check([TFAIConnections save:connection secret:@"fixture-ai-token-two" error:&error]&&[[TFAIConnections secret:a] isEqual:@"fixture-ai-token-two"],@"replace credential");
  [TFAIConnections setConnection:a project:nil];check([[TFAIConnections effectiveForProject:project][@"id"] isEqual:a]&&[[TFAIConnections effectiveForProject:project][@"source"] isEqual:@"global"],@"global inherited");
  connection[@"id"]=b;connection[@"name"]=@"Project connection";check([TFAIConnections save:connection secret:nil error:&error],@"second account");[TFAIConnections setConnection:b project:project];check([[TFAIConnections effectiveForProject:project][@"id"] isEqual:b]&&[[TFAIConnections effectiveForProject:project][@"source"] isEqual:@"project"],@"explicit project override");
  [TFAIConnections setConnection:nil project:project];check([[TFAIConnections effectiveForProject:project][@"id"] isEqual:a],@"reset inheritance");
  NSString *serialized=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:[TFAIConnections all] options:0 error:nil] encoding:NSUTF8StringEncoding];check(![serialized containsString:@"fixture-ai-token"],@"metadata excludes all secrets");
  connection[@"id"]=a;check([TFAIConnections save:connection secret:@"" error:&error]&&![TFAIConnections secret:a].length,@"explicit empty deletes key");
  [TFAIConnections save:connection secret:@"fixture-ai-token-three" error:&error];[TFAIConnections remove:a];check(![TFAIConnections secret:a].length,@"remove connection deletes key");
 }@finally{[TFAIConnections remove:a];[TFAIConnections remove:b];for(NSString *key in keys){id value=backup[key];if(value==NSNull.null)[defaults removeObjectForKey:key];else[defaults setObject:value forKey:key];}}
 NSUInteger passed=0;for(NSDictionary *item in checks)if([item[@"ok"] boolValue])passed++;return @{@"checks":checks,@"passed":@(passed),@"total":@(checks.count),@"ok":@(passed==checks.count),@"fixtureCredentialsRemoved":@YES};
}
