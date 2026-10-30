#import <Foundation/Foundation.h>
// Each change carries an exact before/after snapshot. Planning never writes.
NSArray<NSDictionary *> *TMCCompatibilityPlan(NSString *root, NSArray<NSDictionary *> *diagnostics);
BOOL TMCApplyCompatibilityPlan(NSString *root, NSArray<NSDictionary *> *plan, NSError **error);
BOOL TMCUndoCompatibilityRepair(NSString *root, NSError **error);
// Catalog is bundled with the app; optional explicit path is only for the test CLI.
NSArray<NSDictionary *> *TMCCompatibilityRules(void);
NSArray<NSDictionary *> *TMCCompatibilityFindings(NSString *root, NSArray<NSDictionary *> *diagnostics);
NSArray<NSDictionary *> *TMCParseFixIts(NSString *log, NSString *root, NSString *snapshot);
NSArray<NSDictionary *> *TMCSelectedCompatibilityPlan(NSArray<NSDictionary *> *plan, NSSet<NSString *> *selected);
BOOL TMCRecordRepairContext(NSString *root, NSArray *diagnostics, NSString *log, NSError **error);
void TMCRecordRebuildDiagnostics(NSString *root, NSString *build, NSArray *diagnostics);
