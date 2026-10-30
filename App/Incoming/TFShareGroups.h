#import <Foundation/Foundation.h>
NSDictionary *TFShareSignedEntitlements(NSData *executable);
NSArray<NSString *> *TFShareCommonGroups(NSArray *mainGroups,NSArray *extensionGroups);
NSURL *TFShareContainer(void);
NSDictionary *TFShareContainerDiagnostics(void);

NSDictionary *TFShareResolveGroups(NSArray *mainGroups, NSArray *extensionGroups, NSURL *(^probe)(NSString *group));
