#import <Foundation/Foundation.h>
// Bounded, read-only parsing. Never extracts files or executes package scripts.
NSDictionary *TFAIInspectArtifact(NSData *data, NSString *name, NSError **error);
