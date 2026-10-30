#import "SDKResources.h"
#import "ArchiveImport.h"
#import <CommonCrypto/CommonDigest.h>

static NSError *SDKError(NSString *message){return [NSError errorWithDomain:@"TweakForgeSDK" code:4 userInfo:@{NSLocalizedDescriptionKey:message}];}
NSDictionary *TMCSDKBuildSettings(NSDictionary *config,NSUserDefaults *defaults,NSError **error){
 id sdk=config[@"sdkVersion"]?:[defaults objectForKey:@"StudioSDKVersion"]?:@"16.4";
 id minimum=config[@"deploymentTarget"]?:[defaults objectForKey:@"StudioDeploymentTarget"]?:@"15.0";
 if(![sdk isKindOfClass:NSString.class]||![@[@"16.4",@"26.0"] containsObject:sdk]){if(error)*error=SDKError(@"SDK 请选择 iOS 16.4 或 26.0");return nil;}
 NSRegularExpression *versionPattern=[NSRegularExpression regularExpressionWithPattern:@"^[0-9]{1,2}\\.[0-9]{1,2}(?:\\.[0-9]{1,2})?$" options:0 error:nil];
 if(![minimum isKindOfClass:NSString.class]||![versionPattern firstMatchInString:minimum options:0 range:NSMakeRange(0,[minimum length])]){if(error)*error=SDKError(@"最低系统版本格式如 15.0、16.4 或 26.0");return nil;}
 if([minimum compare:@"15.0" options:NSNumericSearch]==NSOrderedAscending||[minimum compare:sdk options:NSNumericSearch]==NSOrderedDescending){if(error)*error=SDKError([NSString stringWithFormat:@"最低系统版本应在 15.0 到 %@ 之间；这是当前内嵌工具链支持范围。",sdk]);return nil;}
 return @{@"sdkVersion":sdk,@"deploymentTarget":minimum};
}
NSString *TMCPrepareSDK(NSBundle *bundle,NSString *cacheRoot,NSError **error){return TMCPrepareSelectedSDK(bundle,cacheRoot,@"16.4",error);}
NSString *TMCPrepareSelectedSDK(NSBundle *bundle, NSString *cacheRoot, NSString *version,NSError **error) {
    if(![@[@"16.4",@"26.0"] containsObject:version]){if(error)*error=SDKError(@"内置 SDK 版本不受支持");return nil;}
    @synchronized(NSBundle.class) {
        NSFileManager *fm=NSFileManager.defaultManager;
        NSString *stem=[version isEqual:@"16.4"]?@"SDK":@"SDK26";
        NSString *archive=[bundle.bundlePath stringByAppendingPathComponent:[stem stringByAppendingString:@".zip"]];
        NSDictionary *manifest=[NSDictionary dictionaryWithContentsOfFile:[bundle.bundlePath stringByAppendingPathComponent:[stem stringByAppendingString:@"Resource.plist"]]];
        NSString *digest=manifest[@"sha256"];
        if(![digest isKindOfClass:NSString.class]||digest.length!=64||[digest rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet].location!=NSNotFound) {
            if(error)*error=[NSError errorWithDomain:@"TweakForgeSDK" code:1 userInfo:@{NSLocalizedDescriptionKey:@"内置 SDK 清单损坏，请重新安装软件。"}];
            return nil;
        }
        NSString *root=[cacheRoot stringByAppendingPathComponent:@"TweakForgeSDK"];
        NSString *destination=[root stringByAppendingPathComponent:digest];
        NSString *marker=[destination stringByAppendingPathComponent:@".complete"];
        if([[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil] isEqual:digest]&&[fm fileExistsAtPath:[destination stringByAppendingPathComponent:@"usr/include/stdio.h"]])return destination;
        NSData *data=[NSData dataWithContentsOfFile:archive options:NSDataReadingMappedIfSafe error:error];
        if(!data)return nil;
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,hash);
        NSMutableString *actual=[NSMutableString new];for(NSUInteger i=0;i<sizeof(hash);i++)[actual appendFormat:@"%02x",hash[i]];
        if(![actual isEqual:digest]) {
            if(error)*error=[NSError errorWithDomain:@"TweakForgeSDK" code:2 userInfo:@{NSLocalizedDescriptionKey:@"内置 SDK 校验失败，请重新安装软件。"}];
            return nil;
        }
        if(![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error])return nil;
        NSString *staging=[root stringByAppendingPathComponent:[@"preparing-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        if(!TMCExtractArchive([NSURL fileURLWithPath:archive],[NSURL fileURLWithPath:staging],nil,nil,nil,error))return nil;
        NSDictionary *settings=[NSDictionary dictionaryWithContentsOfFile:[staging stringByAppendingPathComponent:@"SDKSettings.plist"]];
        BOOL ok=[settings[@"Version"] isEqual:version]&&[fm fileExistsAtPath:[staging stringByAppendingPathComponent:@"usr/include/stdio.h"]];
        if(!ok&&error)*error=[NSError errorWithDomain:@"TweakForgeSDK" code:3 userInfo:@{NSLocalizedDescriptionKey:@"内置 SDK 缺少必要头文件。"}];
        if(ok)ok=[digest writeToFile:[staging stringByAppendingPathComponent:@".complete"] atomically:YES encoding:NSUTF8StringEncoding error:error];
        if(ok){[fm removeItemAtPath:destination error:nil];ok=[fm moveItemAtPath:staging toPath:destination error:error];}
        if(!ok){[fm removeItemAtPath:staging error:nil];return nil;}
        return destination;
    }
}
