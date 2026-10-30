#import <Foundation/Foundation.h>
@interface TFAIWebTools : NSObject <NSURLSessionDataDelegate>
+ (NSArray *)schemas;
+ (BOOL)enabled;
+ (NSString *)secret:(NSString *)account;
+ (BOOL)setSecret:(NSString *)secret account:(NSString *)account error:(NSError **)error;
+ (BOOL)validURL:(NSURL *)url error:(NSError **)error;
- (NSDictionary *)execute:(NSString *)tool arguments:(NSDictionary *)arguments error:(NSError **)error;
- (void)cancel;
@end
