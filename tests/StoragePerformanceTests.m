#import "../App/StorageSpace.m"
int main(void){@autoreleasepool{
 NSString *base=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString],*docs=Join(base,@"Documents"),*lib=Join(base,@"Library"),*temp=Join(base,@"tmp");NSString *headers=Join(docs,[@"ClassDump-" stringByAppendingString:NSUUID.UUID.UUIDString]);[NSFileManager.defaultManager createDirectoryAtPath:headers withIntermediateDirectories:YES attributes:nil error:nil];
 for(int i=0;i<10000;i++){@autoreleasepool{[@"@interface Fixture\n@end" writeToFile:Join(headers,[NSString stringWithFormat:@"Header-%d.h",i]) atomically:NO encoding:NSUTF8StringEncoding error:nil];}}
 CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();__block NSUInteger updates=0;NSDictionary *scan=StorageScan(docs,lib,temp,@"",^(NSDictionary *partial){updates++;NSCAssert([partial[@"pending"] boolValue],@"partial marked pending");});double elapsed=CFAbsoluteTimeGetCurrent()-start;
 NSCAssert(updates>0,@"progress delivered");NSDictionary *repeat=TMCStorageScan(docs,lib,temp,@"");NSCAssert([scan[@"entries"] isEqual:repeat[@"entries"]],@"order independent fingerprint stable");
 NSLog(@"PASS 10000 files: %.3f seconds (Mac fixture, not iPhone), %lu partial updates; repeat fingerprint stable",elapsed,(unsigned long)updates);[NSFileManager.defaultManager removeItemAtPath:base error:nil];
 }return 0;}
