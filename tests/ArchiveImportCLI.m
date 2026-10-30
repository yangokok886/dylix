#import "../App/ArchiveImport.h"

int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc<3)return 2;
        NSString *mode=@(argv[1]);NSError *error=nil;id result=nil;
        if([mode isEqual:@"projects"])result=TMCArchiveProjects(@(argv[2]),[NSProgress progressWithTotalUnitCount:1],&error);
        else if([mode isEqual:@"prepare"])result=TMCPrepareImportedProject(@(argv[2]),@"Fixture",&error);
        else {
            if(argc<4)return 2;
            NSProgress *progress=[NSProgress progressWithTotalUnitCount:1];
            if([mode isEqual:@"cancel"])[progress cancel];
            BOOL ok=TMCExtractArchive([NSURL fileURLWithPath:@(argv[2])],[NSURL fileURLWithPath:@(argv[3])],argc>4?@(argv[4]):nil,progress,nil,&error);
            if(ok)result=@{@"extracted":@YES};
        }
        NSDictionary *report=result?@{@"ok":@YES,@"result":result}:@{@"ok":@NO,@"code":@(error.code),@"error":error.localizedDescription?:@"Unknown failure"};
        NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);
        return result?0:1;
    }
}
