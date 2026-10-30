#import "../App/SDKResources.h"
int main(int argc,const char **argv){@autoreleasepool{
    NSError *error=nil;NSString *path=TMCPrepareSelectedSDK([NSBundle bundleWithPath:@(argv[1])],@(argv[2]),argc>3?@(argv[3]):@"16.4",&error);
    if(!path){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}
    puts(path.UTF8String);return 0;
}}
