#import <Foundation/Foundation.h>

// A bounded, in-process subset of Make syntax. Never executes recipes or shell.
NSDictionary *TMCReadTheosMakefile(NSString *root, NSError **error);
NSArray<NSString *> *TMCMakeWords(NSString *value);
