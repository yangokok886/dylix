#import <Foundation/Foundation.h>
// Explicit roots keep scanning/test fixtures separate from the user's projects.
NSDictionary *TMCStorageScan(NSString *documents,NSString *library,NSString *temporary,NSString *bundle);
NSDictionary *TMCStorageClean(NSDictionary *snapshot,NSSet<NSString *> *categories,NSError **error);
NSArray<NSDictionary *> *TMCStorageChildren(NSDictionary *snapshot,NSString *category,NSString *directory,NSError **error);
NSDictionary *TMCStorageCleanItems(NSDictionary *snapshot,NSArray<NSDictionary *> *items,NSError **error);
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
UIViewController *TMCStorageController(void);
#endif
