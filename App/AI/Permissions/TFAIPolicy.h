#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSError *TFAIToolError(NSString *message);
FOUNDATION_EXPORT NSString *TFAIDigest(NSData * _Nullable data);
FOUNDATION_EXPORT NSData * _Nullable TFAIJSON(id value,NSError **error);
FOUNDATION_EXPORT BOOL TFAIAllowedRelativePath(NSString *path);
FOUNDATION_EXPORT NSString * _Nullable TFAISafePath(NSString *root,NSString *relative,BOOL allowDirectory,NSError **error);
FOUNDATION_EXPORT NSString *TFAIPrivateDirectory(NSString *projectID,NSString *sessionID);
FOUNDATION_EXPORT BOOL TFAIWriteJSON(id value,NSString *path,NSError **error);
FOUNDATION_EXPORT id _Nullable TFAIReadJSON(NSString *path);
FOUNDATION_EXPORT BOOL TFAIContainsSecret(NSString *text);
NS_ASSUME_NONNULL_END
