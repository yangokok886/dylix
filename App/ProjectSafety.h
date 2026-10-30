#import <Foundation/Foundation.h>
NSDictionary *TMCReadDraft(NSString *root);
BOOL TMCWriteDocument(NSString *path, NSData *expected, NSString *text, NSError **error);
BOOL TMCCopyProject(NSString *root, NSString *destination, BOOL sourceShare, NSProgress *progress, void (^update)(NSProgress *), NSError **error);
void TMCPruneBuildCaches(NSString *documents, NSString *project, NSString *keeping);
@interface TMCLineIndex : NSObject
@property(readonly) NSArray<NSNumber *> *starts;
- (void)update:(NSString *)text;
- (NSUInteger)lineAt:(NSUInteger)offset;
@end
