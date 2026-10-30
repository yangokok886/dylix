#import <Foundation/Foundation.h>

// Call on the build worker. SDK data is extracted locally, never executed.
NSString *TMCPrepareSDK(NSBundle *bundle, NSString *cacheRoot, NSError **error);

// Supported embedded SDK IDs and project overrides; nil settings means validation failed.
NSDictionary *TMCSDKBuildSettings(NSDictionary *config, NSUserDefaults *defaults, NSError **error);
NSString *TMCPrepareSelectedSDK(NSBundle *bundle, NSString *cacheRoot, NSString *version, NSError **error);
