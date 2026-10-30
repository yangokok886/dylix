#import <Foundation/Foundation.h>
@interface BGTask : NSObject
@property(copy) void (^expirationHandler)(void);
@property NSString *identifier;
@property BOOL completed,success;
- (void)setTaskCompletedWithSuccess:(BOOL)success;
@end
@interface BGContinuedProcessingTask : BGTask
@property NSProgress *progress;
@property NSString *title,*subtitle;
- (void)updateTitle:(NSString *)title subtitle:(NSString *)subtitle;
@end
typedef NS_ENUM(NSInteger,BGContinuedProcessingTaskRequestSubmissionStrategy){BGContinuedProcessingTaskRequestSubmissionStrategyFail,BGContinuedProcessingTaskRequestSubmissionStrategyQueue};
@interface BGContinuedProcessingTaskRequest : NSObject
@property NSString *identifier,*title,*subtitle;
@property BGContinuedProcessingTaskRequestSubmissionStrategy strategy;
- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title subtitle:(NSString *)subtitle;
@end
@interface BGTaskScheduler : NSObject
@property(class,readonly) BGTaskScheduler *sharedScheduler;
@property BOOL denyRegistration,denySubmission;
@property NSUInteger registrations,submissions,cancellations;
@property(copy) void (^handler)(BGTask *);
- (BOOL)registerForTaskWithIdentifier:(NSString *)identifier usingQueue:(dispatch_queue_t)queue launchHandler:(void (^)(BGTask *))handler;
- (void)cancelTaskRequestWithIdentifier:(NSString *)identifier;
- (BOOL)submitTaskRequest:(BGContinuedProcessingTaskRequest *)request error:(NSError **)error;
@end
