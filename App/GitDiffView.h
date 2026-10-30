#import <UIKit/UIKit.h>

// Read-only, entirely bundled diff review. Restore/merge actions stay native.
@interface TFGitDiff : UIViewController
@property NSString *content;
@property BOOL compact; // Inline review uses the same diff renderer, without page chrome.
@property(copy) void (^contentHeightChanged)(CGFloat height);
@property NSString *primaryLabel;
@property NSDictionary *conflict;
@property(copy) void (^primary)(UIViewController *);
@end

FOUNDATION_EXPORT NSString *TFReviewPatch(NSString *before, NSString *after, NSString *path);
