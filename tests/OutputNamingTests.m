#import <Foundation/Foundation.h>
#import "../App/OutputNaming.h"
int main(void){@autoreleasepool{
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"NamingQA-" stringByAppendingString:NSUUID.UUID.UUIDString]];NSFileManager *fm=NSFileManager.defaultManager;[fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 [@"Package: com.example.test\nName: 测试插件\nVersion: 2.3.4\nArchitecture: iphoneos-arm64\nAuthor: Test/Author\n" writeToFile:[root stringByAppendingPathComponent:@"control"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 NSDictionary *c=TMCOutputContext(root,@"StableProduct",[NSDate dateWithTimeIntervalSince1970:1793000000]);NSError *error=nil;NSUInteger checks=0;
 NSCAssert([TMCOutputFilename(@"{name}_{version}_{architecture}",@"deb",c,&error) isEqual:@"测试插件_2.3.4_iphoneos-arm64.deb"],@"metadata substitution");checks++;
 NSCAssert([TMCOutputFilename(@"{product}_{author}.dylib",@"dylib",c,&error) isEqual:@"StableProduct_Test_Author.dylib"],@"extension and token sanitizing");checks++;
 NSCAssert(!TMCOutputFilename(@"../outside",@"deb",c,&error)&&error,@"path rejected");checks++;
 error=nil;NSCAssert(!TMCOutputFilename(@"{unknown}",@"deb",c,&error)&&error,@"unknown token rejected");checks++;
 NSCAssert(!TMCOutputFilename(@"{name",@"deb",c,nil),@"unbalanced braces rejected");checks++;
 NSCAssert(!TMCOutputFilename(@"  ",@"deb",c,nil),@"empty rejected");checks++;
 NSCAssert(!TMCOutputFilename([@"中" stringByPaddingToLength:61 withString:@"中" startingAtIndex:0],@"deb",c,nil),@"UTF8 filename length enforced");checks++;
 NSString *dated=TMCOutputFilename(@"{date}_{time}_{arch}",@"dylib",c,nil);NSCAssert([dated hasSuffix:@"_arm64.dylib"]&&dated.length==27,@"date/time/arch expand");checks++;
 [@"{\"name\":\"Pure\",\"package\":false}" writeToFile:[root stringByAppendingPathComponent:@"MobileCompiler.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[fm removeItemAtPath:[root stringByAppendingPathComponent:@"control"] error:nil];NSDictionary *pure=TMCOutputContext(root,@"Pure",NSDate.date);NSCAssert([pure[@"version"] isEqual:@"unversioned"]&&[pure[@"package"] isEqual:@"unpackaged"],@"pure-library metadata is not invented");checks++;
 NSArray *schemes=@[@"rootless",@"rootful",@"roothide"];NSCAssert([TMCVariantOutputFilename(@"{platform}_{packageArch}_{scheme}",@"deb",c,schemes,@"roothide",nil) isEqual:@"iphoneos_arm64e_roothide.deb"],@"split naming tokens");checks++;
 NSCAssert([TMCVariantOutputFilename(@"{product}",@"dylib",c,schemes,@"rootless",nil) isEqual:@"StableProduct.dylib"],@"no forced suffix");checks++;
 NSCAssert([TMCVariantOutputFilename(@"{product}",@"dylib",c,schemes,@"rootful",nil) isEqual:@"StableProduct-2.dylib"]&&[TMCVariantOutputFilename(@"{product}",@"dylib",c,schemes,@"roothide",nil) isEqual:@"StableProduct-3.dylib"],@"collision without package suffix");checks++;
 NSCAssert([TMCVariantOutputFilename(TMCDefaultOutputPattern(@"deb"),@"deb",c,schemes,@"rootful",nil) isEqual:@"测试插件_2.3.4_iphoneos-arm.deb"],@"default decomposed deb");checks++;
 [fm removeItemAtPath:root error:nil];printf("OutputNaming: %lu checks passed\n",(unsigned long)checks);
}return 0;}
