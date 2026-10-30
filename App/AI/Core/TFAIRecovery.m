#import "TFAIRecovery.h"
NSArray *TFAIRecoveryTranscript(NSArray *messages){
 NSMutableArray *out=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new],*owned=[NSMutableSet new];NSMutableDictionary *results=[NSMutableDictionary new];for(id item in messages){if(![item isKindOfClass:NSDictionary.class])continue;if([item[@"role"] isEqual:@"tool"]&&[item[@"tool_call_id"] isKindOfClass:NSString.class])results[item[@"tool_call_id"]]=item;for(id call in ([item[@"tool_calls"] isKindOfClass:NSArray.class]?item[@"tool_calls"]:@[]))if([call isKindOfClass:NSDictionary.class]&&[call[@"id"] isKindOfClass:NSString.class])[owned addObject:call[@"id"]];}
 for(id item in messages){if(![item isKindOfClass:NSDictionary.class])continue;NSString *role=item[@"role"];if(![@[@"user",@"assistant",@"tool"] containsObject:role])continue;
 if([role isEqual:@"tool"]){if(![owned containsObject:item[@"tool_call_id"]?:@""])[out addObject:@{@"role":@"assistant",@"content":[@"本机历史工具记录（仅供核对）：\n" stringByAppendingString:[item[@"content"] isKindOfClass:NSString.class]?item[@"content"]:@""],@"orphanToolResult":@YES}];continue;} // Owned results are placed immediately after the call.
 [out addObject:[item copy]];
 if(![role isEqual:@"assistant"])continue;
 for(id call in ([item[@"tool_calls"] isKindOfClass:NSArray.class]?item[@"tool_calls"]:@[])){NSString *identifier=[call isKindOfClass:NSDictionary.class]?call[@"id"]:nil;if(![identifier isKindOfClass:NSString.class]||!identifier.length||[seen containsObject:identifier])continue;[seen addObject:identifier];NSDictionary *result=results[identifier];
 [out addObject:result?:@{@"role":@"tool",@"tool_call_id":identifier,@"content":@"{\"state\":\"outcomeUnknown\",\"replayed\":false,\"advice\":\"No durable completion was received. Inspect current files, build artifacts and Git state before suggesting another operation. Do not assume rollback or replay side effects.\"}"}];
 }}return out;
}
NSDictionary *TFAIRecoveryContinuation(void){return @{@"role":@"user",@"messageID":NSUUID.UUID.UUIDString,@"timestamp":@(NSDate.date.timeIntervalSince1970),@"localRecovery":@YES,@"content":@"请从已保存的处理记录继续分析：先检查已有工具结果、文件及构建状态，补充未完成的结论。不要重复已完成操作；缺少完成记录的工具结果视为待核对。本次恢复只读，涉及文件修改、构建或上传请先说明核对结果，等我另行发起。"};}
