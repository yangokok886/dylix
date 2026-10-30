#import <Foundation/Foundation.h>
@interface TFHeaderFixture:NSObject { int _counter; }
-(NSString *)greeting:(NSString *)name;
+(NSInteger)answer;
@end
@implementation TFHeaderFixture
-(NSString *)greeting:(NSString *)name{return name;}
+(NSInteger)answer{return 42;}
@end
@interface TFHeaderFixture (Extras)
-(BOOL)ready;
@end
@implementation TFHeaderFixture (Extras)
-(BOOL)ready{return YES;}
@end
