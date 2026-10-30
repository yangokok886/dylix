// Public SDK 26 declarations for builds with an older simulator SDK.
// All references are availability guarded; no execution on iOS 18 simulators.
#if !defined(TFAI_BACKGROUND_FIXTURE) && __IPHONE_OS_VERSION_MAX_ALLOWED < 260000
API_AVAILABLE(ios(26.0))
@interface BGContinuedProcessingTask : BGTask
@property(readonly) NSProgress *progress;
- (void)updateTitle:(NSString *)title subtitle:(NSString *)subtitle;
@end
typedef NS_ENUM(NSInteger,BGContinuedProcessingTaskRequestSubmissionStrategy){BGContinuedProcessingTaskRequestSubmissionStrategyFail=0,BGContinuedProcessingTaskRequestSubmissionStrategyQueue=1};
API_AVAILABLE(ios(26.0))
@interface BGContinuedProcessingTaskRequest : BGTaskRequest
- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title subtitle:(NSString *)subtitle;
@property BGContinuedProcessingTaskRequestSubmissionStrategy strategy;
@end
#endif
