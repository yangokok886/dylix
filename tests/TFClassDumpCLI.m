#import "../App/AI/ClassDump/TFAIClassDump.h"
#include <stdio.h>
int main(int argc,const char **argv){@autoreleasepool{if(argc!=3)return 2;NSError *error=nil;NSDictionary *result=TFAIClassDumpFile(@(argv[1]),@(argv[2]),nil,^(double progress,NSString *message){fprintf(stderr,"%.0f%% %s\n",progress*100,message.UTF8String);},&error);if(!result){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];fwrite(json.bytes,1,json.length,stdout);return 0;}}
