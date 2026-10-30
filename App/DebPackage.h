#import <Foundation/Foundation.h>
NSData *TMCDebPackage(NSData *dylib, NSString *name, NSString *bundleID, NSError **error);
NSData *TMCDebPackageWithMetadata(NSData *dylib, NSString *name, NSData *filterPlist, NSString *control, NSError **error);

NSString *TMCPackageScheme(NSDictionary *config, NSString *control);
NSString *TMCControlForScheme(NSString *control, NSString *scheme);
NSData *TMCDebPackageForScheme(NSData *dylib, NSString *name, NSString *bundleID, NSString *scheme, NSError **error);

NSData *TMCDebPackageWithResources(NSData *dylib, NSString *name, NSData *filterPlist, NSString *control, NSString *root, NSString *scheme, NSDictionary *config, NSError **error);

NSData *TMCDebPackageForProject(NSData *dylib, NSString *name, NSString *bundleID, NSString *scheme, NSString *root, NSDictionary *config, NSError **error);
