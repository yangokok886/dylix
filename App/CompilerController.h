#import <UIKit/UIKit.h>
@class MBProgressHUD;
@interface CompilerController : UIViewController <UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property(nonatomic) UITextView *console;
@property(nonatomic) NSString *importedSource;
@property(nonatomic) NSString *importedProject;
@property(nonatomic) UIDocumentPickerViewController *activePicker;
@property(nonatomic,weak) UIViewController *presentationHost;
@property(nonatomic) BOOL importInProgress;
@property(nonatomic) BOOL pickingArchive;
@property(nonatomic) NSProgress *archiveProgress;
@property(nonatomic) MBProgressHUD *archiveHUD;
@property(nonatomic) NSString *archiveWorkRoot;
@property(nonatomic) NSString *archiveInputPath;
@property(nonatomic) NSString *archiveProjectName;

@property(nonatomic) NSString *lastPackage;
@property(nonatomic) NSString *lastBuild;
@property(nonatomic) BOOL hasBuilt;
@property(nonatomic) NSString *pendingImportedProject;
@property(nonatomic,copy) void (^importCompletion)(NSString *path);
@property(nonatomic,copy) void (^buildCompletion)(BOOL success);
- (void)importSource;
- (void)importArchiveURL:(NSURL *)url;
- (void)importURLs:(NSArray<NSURL *> *)urls;
- (void)runProof;
- (void)exportResult;
@end
