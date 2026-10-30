#import <Foundation/Foundation.h>
@interface LocalImportTest : NSObject
-(NSString*)message;
@end
@implementation LocalImportTest
-(NSString*)message { return @"Imported project metadata"; }
@end
