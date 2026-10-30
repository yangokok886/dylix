#if TARGET_OS_SIMULATOR
UIViewController *TMCMaintenanceRegression(void){
 NSString *root=[Docs() stringByAppendingPathComponent:[@"Maintenance-" stringByAppendingString:NSUUID.UUID.UUIDString]];
 [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 JSONWrite(@{@"name":@"Maintenance",@"productName":@"Maintenance",@"sources":@[@"A.c",@"B.c"],@"package":@NO},[root stringByAppendingPathComponent:@"MobileCompiler.json"],nil);
 [@"int a=1;\n" writeToFile:[root stringByAppendingPathComponent:@"A.c"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 [@"int b=2;\n" writeToFile:[root stringByAppendingPathComponent:@"B.c"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 StudioEditor *editor=[StudioEditor new];editor.root=root;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
 NSMutableDictionary *result=[NSMutableDictionary new];
 [editor openFile:@"A.c"];[editor.editor becomeFirstResponder];editor.editor.selectedRange=NSMakeRange(editor.editor.text.length,0);[editor.editor insertText:@"// edit A\n"];[editor save];
 [editor openFile:@"B.c"];NSString *before=editor.editor.text;BOOL canUndo=editor.editor.undoManager.canUndo;
 @try{[editor.editor.undoManager undo];result[@"crossFileUndoIsolated"]=@(!canUndo&&[before isEqual:editor.editor.text]);}@catch(NSException *e){result[@"crossFileUndoIsolated"]=@NO;result[@"undoException"]=e.reason;}
 [editor openFile:@"A.c"];[editor.editor insertText:@"// local\n"];
 [@"int external=99;\n" writeToFile:[root stringByAppendingPathComponent:@"A.c"] atomically:YES encoding:NSUTF8StringEncoding error:nil];BOOL saved=[editor save];
 result[@"externalWriteProtected"]=@(!saved&&editor.dirty&&[[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"A.c"] encoding:NSUTF8StringEncoding error:nil] containsString:@"external"]);
 [editor dismissViewControllerAnimated:NO completion:nil];editor.dirty=NO;[editor.editor resignFirstResponder];
 NSString *bad=[Docs() stringByAppendingPathComponent:[@"BadDraft-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtPath:bad withIntermediateDirectories:YES attributes:nil error:nil];
 JSONWrite(@{@"sources":@[@"A.c"]},[bad stringByAppendingPathComponent:@"MobileCompiler.json"],nil);[@"int a;" writeToFile:[bad stringByAppendingPathComponent:@"A.c"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[@"[]" writeToFile:[bad stringByAppendingPathComponent:@".studio-draft.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 @try{StudioEditor *v=[StudioEditor new];v.root=bad;[v loadViewIfNeeded];result[@"malformedDraftDoesNotCrash"]=@([v.filename isEqual:@"A.c"]&&v.editor.text.length>0);}@catch(NSException *e){result[@"malformedDraftDoesNotCrash"]=@NO;}
 result[@"symbolsScrollable"]=@(editor.symbolScroll!=nil);result[@"tabClose44pt"]=@(editor.tabScroll.bounds.size.height>=44);
 JSONWrite(result,[Docs() stringByAppendingPathComponent:@"maintenance-test.json"],nil);
 });return editor;
}
#endif
