#import <Foundation/Foundation.h>
NSArray<NSDictionary *> *TFAIAttachmentCandidates(NSString *root,NSError **error);
NSArray<NSDictionary *> *TFAIStageAttachmentFiles(NSString *root,NSArray<NSString *> *relativePaths,NSString *source,NSError **error);
NSArray<NSDictionary *> *TFAIResolveAttachments(NSArray<NSDictionary *> *entries,NSError **error);
NSString *TFAIAttachmentLocalPath(NSDictionary *entry,NSError **error);
BOOL TFAIAttachmentSensitive(NSString *text);

NSDictionary *TFAIReadAttachmentReferences(NSDictionary *references,NSDictionary *arguments,NSError **error);

// Opaque, revocable local directory grant. No content is copied or enumerated here.
NSDictionary *TFAIAuthorizeDirectory(NSURL *url,NSString *source,NSError **error);
BOOL TFAIRevokeDirectory(NSDictionary *entry,NSError **error);
NSDictionary *TFAIReadDirectoryReference(NSDictionary *entry,NSDictionary *arguments,NSError **error);

// Local UI only. Caller balances security-scoped access; never include in model data.
NSURL *TFAIDirectoryBrowserURL(NSDictionary *entry,NSError **error);
