#import "../App/AI/UI/TFAISessionFilePaths.h"
static int failures=0,checks=0;
static void Check(BOOL condition,const char *name){checks++;if(!condition){failures++;printf("FAIL %s\n",name);}}
int main(void){@autoreleasepool{
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSFileManager *fm=NSFileManager.defaultManager;[fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 NSString *allowed=[root stringByAppendingPathComponent:@"allowed"],*outside=[root stringByAppendingPathComponent:@"outside"];
 [fm createDirectoryAtPath:allowed withIntermediateDirectories:YES attributes:nil error:nil];[fm createDirectoryAtPath:outside withIntermediateDirectories:YES attributes:nil error:nil];
 Check(SFPath(allowed,@"nested/file.h")!=nil,"project relative path accepted");
 for(NSString *path in @[@"../outside/secret",@"/etc/passwd",@"nested/../../outside",@"a\\b",@""])Check(SFPath(allowed,path)==nil,"unscoped path rejected");
 Check(!SFInside(allowed,[root stringByAppendingPathComponent:@"allowed-other/file"]),"component prefix collision rejected");
 [fm createSymbolicLinkAtPath:[allowed stringByAppendingPathComponent:@"link"] withDestinationPath:outside error:nil];Check(SFPath(allowed,@"link/file.h")==nil,"symlink traversal rejected");
 NSString *identifier=[@"Build-" stringByAppendingString:NSUUID.UUID.UUIDString];Check(SFBuildPath(root,identifier)!=nil,"local build UUID accepted");
 for(id value in @[@"Build-../../outside",@"Build-other",@"ClassDump-123",@"/Build-123",NSNull.null,@13])Check(SFBuildPath(root,value)==nil,"untrusted build id rejected");
 [fm removeItemAtPath:root error:nil];printf("RESULT %d checks %d failures\n",checks,failures);return failures?1:0;
}}
