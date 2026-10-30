#import <Foundation/Foundation.h>
// A user-mediated Files export bridge; never grants cross-sandbox access.
NSString *TFShareTransferName(NSString *original, NSString *identifier);
NSString *TFShareTransferOriginalName(NSString *name);
NSArray<NSURL *> *TFShareTransferPending(NSString *documents);
