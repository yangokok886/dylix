#import "TFAIBuildCache.h"
static NSArray *Owned(NSString *root,NSString *docs){
 NSString *prefix=[docs stringByAppendingString:@"/"];NSString *owner=[root hasPrefix:prefix]?[root substringFromIndex:prefix.length]:root;
 NSDictionary *value=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".studio-build-cache.json"]]?:NSData.data options:0 error:nil];
 return [value isKindOfClass:NSDictionary.class]&&[value[@"owner"] isEqual:owner]&&[value[@"items"] isKindOfClass:NSArray.class]?value[@"items"]:@[];
}
static NSString *BuildPath(NSString *docs,id name){
 if(![name isKindOfClass:NSString.class]||![name hasPrefix:@"Build-"]||![[NSUUID alloc]initWithUUIDString:[name substringFromIndex:6]])return nil;
 NSString *path=[docs stringByAppendingPathComponent:name];NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
 return [attrs[NSFileType] isEqual:NSFileTypeDirectory]&&[path.stringByResolvingSymlinksInPath isEqual:[docs.stringByResolvingSymlinksInPath stringByAppendingPathComponent:name]]?path:nil;
}
NSArray *TFAIProjectBuilds(NSString *root,NSString *docs){
 NSMutableArray *items=[NSMutableArray new];for(id name in Owned(root,docs)){NSString *path=BuildPath(docs,name);if(!path)continue;NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];NSMutableArray *files=[NSMutableArray new];for(NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil])if([@[@"deb",@"dylib"] containsObject:file.pathExtension])[files addObject:file];[items addObject:@{@"buildID":name,@"modified":@([attrs[NSFileModificationDate] timeIntervalSince1970]),@"artifacts":files}];}
 [items sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"modified"] compare:a[@"modified"]];}];return items;
}
NSDictionary *TFAICleanProjectBuilds(NSString *root,NSString *docs,NSArray *ids,NSError **error){
 NSArray *owned=Owned(root,docs);NSMutableArray *paths=[NSMutableArray new];
 if(!ids.count||ids.count>100){if(error)*error=[NSError errorWithDomain:@"AI.BuildCache" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请指定 1–100 个构建编号，先调用 list_builds"}];return nil;}
 for(id name in ids){NSString *path=BuildPath(docs,name);if(![owned containsObject:name]||!path){if(error)*error=[NSError errorWithDomain:@"AI.BuildCache" code:2 userInfo:@{NSLocalizedDescriptionKey:@"构建不属于当前项目、已移除或路径已变化；未开始清理"}];return nil;}if(![paths containsObject:path])[paths addObject:path];}
 NSMutableArray *deleted=[NSMutableArray new];for(NSString *path in paths){if(![NSFileManager.defaultManager removeItemAtPath:path error:error])return nil;[deleted addObject:path.lastPathComponent];}
 // Keep historical ownership entries: missing outputs are filtered above and other builds remain intact.
 return @{@"deletedBuildIDs":deleted,@"count":@(deleted.count),@"remainingBuilds":TFAIProjectBuilds(root,docs),@"message":@"已清理所选构建结果；项目源码和会话记录保留"};
}
