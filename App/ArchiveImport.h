#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TMCArchiveErrorCode) {
    TMCArchiveInvalid = 1,
    TMCArchivePassword = 2,
    TMCArchiveCancelled = 3,
    TMCArchiveLimit = 4,
    TMCArchiveProjectInvalid = 5,
};

typedef void (^TMCArchiveProgress)(NSUInteger files, unsigned long long bytes);

// Extracts into a new, private directory. No external commands or code execution.
BOOL TMCExtractArchive(NSURL *input, NSURL *destination, NSString *password,
                       NSProgress *cancellation, TMCArchiveProgress progress, NSError **error);
NSArray<NSDictionary *> *TMCArchiveProjects(NSString *root, NSProgress *cancellation, NSError **error);
// Preserves an existing manifest; creates one for a plain source/Theos directory.
NSDictionary *TMCPrepareImportedProject(NSString *root, NSString *fallbackName, NSError **error);
