@interface UIViewController (TFViewportTest)
- (void)rebuildDisplay;
- (NSDictionary *)captureViewport;
- (void)toggleFoldID:(NSString *)fold;
- (void)setAllFoldsExpanded:(BOOL)expanded;
- (void)jumpBottom;
@end
static void TFAIChatViewportRegression(UIViewController *chat,void(^check)(BOOL,NSString *)) {
 UIWindow *previous=nil;for(UIWindow *candidate in ((UIWindowScene *)chat.view.window.windowScene).windows)if(candidate.isKeyWindow)previous=candidate;UIWindowScene *scene=(UIWindowScene *)UIApplication.sharedApplication.connectedScenes.allObjects.firstObject; if(!previous)for(UIWindow *candidate in scene.windows)if(candidate.isKeyWindow)previous=candidate;UIWindow *fixture=[[UIWindow alloc]initWithWindowScene:scene];fixture.frame=UIScreen.mainScreen.bounds;fixture.rootViewController=chat;[fixture makeKeyAndVisible];[chat.view setNeedsLayout];[chat.view layoutIfNeeded];
 NSArray *keys=@[@"messages",@"folds",@"analysisSummaries",@"summaryText",@"processRecords",@"followBottom",@"restoringScroll"];
 NSMutableDictionary *saved=[NSMutableDictionary new];for(NSString *key in keys)saved[key]=[chat valueForKey:key]?:NSNull.null;
 UITableView *table=[chat valueForKey:@"table"];CGPoint offset=table.contentOffset;UIEdgeInsets inset=table.contentInset;
 NSMutableArray *messages=[NSMutableArray new];for(int i=0;i<18;i++)[messages addObject:@{@"role":@"user",@"messageID":[NSString stringWithFormat:@"viewport-%d",i],@"content":[NSString stringWithFormat:@"Message %d\nStable viewport fixture with enough text to wrap into multiple lines.",i]}];
 NSString *longText=[@"Detailed summary line with enough text to wrap.\n" stringByPaddingToLength:2400 withString:@"Detailed summary line with enough text to wrap.\n" startingAtIndex:0];
 [chat setValue:[NSMutableDictionary new] forKey:@"analysisSummaries"];[chat setValue:messages forKey:@"messages"];[chat setValue:[NSMutableDictionary new] forKey:@"folds"];[chat setValue:longText forKey:@"summaryText"];[chat setValue:[NSMutableArray arrayWithObject:@{@"id":@"viewport-tool",@"name":@"read_file",@"status":@"completed",@"result":longText}] forKey:@"processRecords"];[chat setValue:@NO forKey:@"restoringScroll"];[chat setValue:@YES forKey:@"followBottom"];[chat rebuildDisplay];[table layoutIfNeeded];
 check(table.bounds.size.height>300,@"viewport fixture has real visible table geometry");
 CGFloat(^screenY)(NSUInteger)=^CGFloat(NSUInteger row){return [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]].origin.y-table.contentOffset.y;};
 CGFloat before=screenY(18);[chat toggleFoldID:@"summary"];check(fabs(screenY(18)-before)<1&&![[chat valueForKey:@"followBottom"] boolValue],@"expanding summary keeps tapped header stationary and suspends bottom follow");
 before=screenY(18);[chat toggleFoldID:@"summary"];check(fabs(screenY(18)-before)<1,@"collapsing summary keeps same header screen position");
 [chat jumpBottom];before=screenY(19);[chat toggleFoldID:@"viewport-tool"];check(fabs(screenY(19)-before)<1,@"expanding tool result keeps tapped header stationary");before=screenY(19);[chat toggleFoldID:@"viewport-tool"];check(fabs(screenY(19)-before)<1,@"collapsing tool result does not clamp viewport upward");
 [table setContentOffset:CGPointMake(0,[table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:8 inSection:0]].origin.y+10) animated:NO];[table layoutIfNeeded];before=screenY(8);[chat setAllFoldsExpanded:YES];check(fabs(screenY(8)-before)<1,@"expand all preserves visible earlier message");[chat setAllFoldsExpanded:NO];check(fabs(screenY(8)-before)<1,@"collapse all preserves visible earlier message");
 [messages insertObject:@{@"role":@"assistant",@"messageID":@"viewport-insert",@"content":@"Inserted earlier message"} atIndex:0];[chat rebuildDisplay];check(fabs(screenY(9)-before)<1,@"stable message identity preserves viewport when rows inserted above");
 [messages addObject:@{@"role":@"assistant",@"messageID":@"viewport-new",@"content":@"New response"}];[chat rebuildDisplay];check(fabs(screenY(9)-before)<1,@"new message does not displace user browsing earlier content");
 CGFloat idleY=screenY(9);[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.15]];[table layoutIfNeeded];check(fabs(screenY(9)-idleY)<1,@"viewport remains stable after deferred UIKit layout and render timer");
 [table.delegate scrollViewWillBeginDragging:table];[table.delegate scrollViewDidEndDragging:table willDecelerate:YES];check(![[chat valueForKey:@"followBottom"] boolValue],@"decelerating user scroll stays independent of streaming auto follow");[table.delegate scrollViewDidEndDecelerating:table];check(![[chat valueForKey:@"followBottom"] boolValue],@"settled historical reading remains outside bottom follow");
 [chat jumpBottom];check([[chat valueForKey:@"followBottom"] boolValue]&&fabs([[chat valueForKey:@"viewportBottomSpace"] doubleValue])<.1,@"return to latest restores following and removes temporary bottom space");
 for(NSString *key in keys)[chat setValue:saved[key]==NSNull.null?nil:saved[key] forKey:key];[chat setValue:@0 forKey:@"viewportBottomSpace"];table.contentInset=inset;[chat rebuildDisplay];table.contentOffset=offset;fixture.hidden=YES;fixture.rootViewController=nil;[previous makeKeyWindow];
}
