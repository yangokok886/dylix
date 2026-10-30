#import <Foundation/Foundation.h>
typedef void(^TFShareOpenAction)(NSURL *url, void(^completion)(BOOL success));
@interface TFShareLauncher:NSObject
@property(copy) TFShareOpenAction primary;
@property(copy) TFShareOpenAction fallback;
@property(copy) void(^updated)(NSDictionary *snapshot);
@property NSTimeInterval timeout;
@property(readonly) NSDictionary *snapshot;
- (BOOL)openIncomingJob:(NSString *)job;
@end
