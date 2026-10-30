#import <Foundation/Foundation.h>
NSDictionary *TFBinaryIndex(NSData *data);
NSDictionary *TFBuildProvenance(NSString *root, NSArray *sources, NSDictionary *config, NSString *build);
NSArray *TFRuntimeRisks(NSString *root);
NSString *TFCrashAnalysis(NSData *data, NSString *documents);
NSString *TFResolvedOptimization(NSDictionary *config);
