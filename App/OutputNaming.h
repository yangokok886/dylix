#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSDictionary<NSString *,NSString *> *TMCOutputContext(NSString *root, NSString *product, NSDate *date);
FOUNDATION_EXPORT NSString *TMCOutputFilename(NSString *pattern, NSString *extension, NSDictionary<NSString *,NSString *> *context, NSError **error);
FOUNDATION_EXPORT NSString *TMCDefaultOutputPattern(NSString *extension);

FOUNDATION_EXPORT NSDictionary *TMCEffectiveBuildOptions(NSDictionary *config, NSUserDefaults *defaults);
FOUNDATION_EXPORT NSDictionary *TMCNamingContextForScheme(NSDictionary *context, NSString *scheme);
FOUNDATION_EXPORT NSString *TMCVariantOutputFilename(NSString *pattern, NSString *extension, NSDictionary *context, NSArray *schemes, NSString *scheme, NSError **error);
