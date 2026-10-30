#import "ProjectTrash.h"
NSUInteger TMCPruneProjectTrash(NSString *trash,NSDate *now){
 NSFileManager *fm=NSFileManager.defaultManager;NSDictionary *parent=[fm attributesOfItemAtPath:trash error:nil];if(![parent[NSFileType] isEqual:NSFileTypeDirectory])return 0;
 NSUInteger removed=0;for(NSString *name in [fm contentsOfDirectoryAtPath:trash error:nil]){NSString *root=[trash stringByAppendingPathComponent:name];NSDictionary *attrs=[fm attributesOfItemAtPath:root error:nil];if(![attrs[NSFileType] isEqual:NSFileTypeDirectory])continue;
 NSString *path=[root stringByAppendingPathComponent:@".studio-trash.json"];if([[fm attributesOfItemAtPath:path error:nil][NSFileType] isEqual:NSFileTypeSymbolicLink])continue;
 NSData *data=[NSData dataWithContentsOfFile:path];id entry=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;id timestamp=[entry isKindOfClass:NSDictionary.class]?entry[@"deletedAt"]:nil;
 if(![timestamp isKindOfClass:NSNumber.class]||![timestamp doubleValue]||[timestamp doubleValue]>now.timeIntervalSince1970){NSMutableDictionary *fixed=[entry isKindOfClass:NSDictionary.class]?[entry mutableCopy]:[NSMutableDictionary new];fixed[@"deletedAt"]=@(now.timeIntervalSince1970);[[NSJSONSerialization dataWithJSONObject:fixed options:0 error:nil] writeToFile:path atomically:YES];continue;}
 if(now.timeIntervalSince1970-[timestamp doubleValue]>=7*24*60*60&&[fm removeItemAtPath:root error:nil])removed++;
 }return removed;
}
