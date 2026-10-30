#import "../App/SDKResources.h"
int main(void){@autoreleasepool{
 NSUserDefaults *u=[[NSUserDefaults alloc] initWithSuiteName:@"tf-sdk118-tests"];
 [u removePersistentDomainForName:@"tf-sdk118-tests"];
 NSUInteger checks=0;
 #define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"failed %lu: %s\n",(unsigned long)checks,#x);return 1;}}while(0)
 CHECK([TMCSDKBuildSettings(@{},u,nil)[@"sdkVersion"] isEqual:@"16.4"]);
 CHECK([TMCSDKBuildSettings(@{},u,nil)[@"deploymentTarget"] isEqual:@"15.0"]);
 [u setObject:@"26.0" forKey:@"StudioSDKVersion"];[u setObject:@"18.6" forKey:@"StudioDeploymentTarget"];
 CHECK([TMCSDKBuildSettings(@{},u,nil)[@"deploymentTarget"] isEqual:@"18.6"]);
 CHECK([TMCSDKBuildSettings(@{@"deploymentTarget":@"26.0"},u,nil)[@"sdkVersion"] isEqual:@"26.0"]);
 CHECK(TMCSDKBuildSettings(@{@"sdkVersion":@"16.4",@"deploymentTarget":@"15.0"},u,nil)!=nil);
 for(id bad in @[@"14.0",@"26.1",@"15.0 -foo",@"",@15,NSNull.null]){CHECK(TMCSDKBuildSettings(@{@"deploymentTarget":bad},u,nil)==nil);}
 for(id bad in @[@"16.5",@"25.0",@26,NSNull.null]){CHECK(TMCSDKBuildSettings(@{@"sdkVersion":bad},u,nil)==nil);}
 CHECK(TMCSDKBuildSettings(@{@"sdkVersion":@"16.4"},u,nil)==nil);
 CHECK(TMCSDKBuildSettings(@{@"deploymentTarget":@"18.6.1"},u,nil)!=nil);
 [u removePersistentDomainForName:@"tf-sdk118-tests"];
 printf("{\"passed\":true,\"checks\":%lu}\n",(unsigned long)checks);return 0;
}}
