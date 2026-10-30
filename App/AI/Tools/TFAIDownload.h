#import <Foundation/Foundation.h>
// A bounded, credential-free, one-origin request. Every redirect needs a new preview.
@interface TFAIDownload : NSObject <NSURLSessionDataDelegate>
@property(atomic) BOOL cancelled;
- (NSData *)fetch:(NSURL *)url error:(NSError **)error;
- (void)cancel;
@end
