#import <Foundation/Foundation.h>
#import "../App/OutputNaming.h"
int main(void){@autoreleasepool{
 NSUserDefaults *u=[[NSUserDefaults alloc] initWithSuiteName:@"local.tmc.options.tests"];[u removePersistentDomainForName:@"local.tmc.options.tests"];
 NSDictionary *d=TMCEffectiveBuildOptions(@{},u);NSCAssert([d[@"package"] boolValue]&&[d[@"packageSchemes"] isEqual:@[@"rootless"]],@"factory defaults");
 [u setBool:NO forKey:@"StudioPackageEnabled"];[u setObject:@[@"rootless",@"rootful",@"roothide"] forKey:@"StudioPackageSchemes"];[u setObject:@"Global-{name}" forKey:@"StudioOutputPattern-deb"];
 d=TMCEffectiveBuildOptions(@{},u);NSCAssert(![d[@"package"] boolValue]&&[d[@"packageSchemes"] count]==3&&[d[@"outputPattern-deb"] isEqual:@"Global-{name}"],@"inherit all global defaults");
 d=TMCEffectiveBuildOptions(@{@"package":@YES,@"packageSchemes":@[@"roothide"],@"outputPattern-deb":@"Local-{version}"},u);NSCAssert([d[@"package"] boolValue]&&[d[@"packageSchemes"] isEqual:@[@"roothide"]]&&[d[@"outputPattern-deb"] isEqual:@"Local-{version}"],@"project overrides independent");
 d=TMCEffectiveBuildOptions(@{@"outputPattern-deb":@"",@"packageScheme":@"rootful"},u);NSCAssert([d[@"packageSchemes"] isEqual:@[@"rootful"]]&&[d[@"outputPattern-deb"] isEqual:@"Global-{name}"],@"legacy scheme and empty names");
 [u setObject:@"New-{name}" forKey:@"StudioOutputPattern-deb"];d=TMCEffectiveBuildOptions(@{},u);NSCAssert([d[@"outputPattern-deb"] isEqual:@"New-{name}"],@"inherit follows future changes");
 [u setBool:NO forKey:@"StudioExportDylib"];d=TMCEffectiveBuildOptions(@{},u);NSCAssert(![d[@"exportDylib"] boolValue],@"inherit dylib default");d=TMCEffectiveBuildOptions(@{@"exportDylib":@YES},u);NSCAssert([d[@"exportDylib"] boolValue],@"override dylib independent from deb");
 [u removePersistentDomainForName:@"local.tmc.options.tests"];puts("BuildOptions: 7 scenarios passed");
}return 0;}
