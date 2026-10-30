#import "TFAIPolicy.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
NSError *TFAIToolError(NSString *message){return [NSError errorWithDomain:@"TweakForge.AI.Tools" code:1 userInfo:@{NSLocalizedDescriptionKey:message?:@"AI 工具操作失败"}];}
NSString *TFAIDigest(NSData *data){if(!data)return @"missing";unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);NSMutableString *s=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",bytes[i]];return s;}
NSData *TFAIJSON(id value,NSError **error){if(![NSJSONSerialization isValidJSONObject:value]){if(error)*error=TFAIToolError(@"工具数据应为有效 JSON 对象");return nil;}return [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:error];}
BOOL TFAIAllowedRelativePath(NSString *path){
 if(![path isKindOfClass:NSString.class]||!path.length||path.isAbsolutePath||[path containsString:@"\\"]||[path containsString:@":"]||[path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return NO;
 NSSet *blocked=[NSSet setWithArray:@[@".git",@".theos",@"build",@".build",@"deriveddata",@"packages",@"node_modules",@".package-link-cache",@".studiotrash",@"__macosx",@"credentials",@"credentials.json",@"secrets",@"secrets.json",@"token",@"token.json",@"tokens.json",@"apikey",@"apikey.json",@"api_key",@"api_key.json",@"auth.json",@".git-credentials",@".netrc",@".ssh",@".aws",@".ds_store"]];
 for(NSString *part in path.pathComponents){NSString *p=part.lowercaseString;if([p isEqual:@".."]||[p isEqual:@"."]||[blocked containsObject:p]||[p hasPrefix:@".studio-"]||[p hasPrefix:@".env"]||[p hasPrefix:@"build-"]||[p hasPrefix:@"snapshot-"])return NO;}
 return ![@[@"p12",@"pfx",@"pem",@"key",@"cer",@"mobileprovision",@"o",@"dylib",@"deb",@"ipa",@"tmp",@"swp"] containsObject:path.pathExtension.lowercaseString];
}
NSString *TFAISafePath(NSString *root,NSString *relative,BOOL allowDirectory,NSError **error){
 if(!TFAIAllowedRelativePath(relative)){if(error)*error=TFAIToolError(@"路径越界、凭据或构建缓存不在 AI 工具允许范围内");return nil;}
 NSString *base=root.stringByResolvingSymlinksInPath.stringByStandardizingPath;NSString *full=[base stringByAppendingPathComponent:relative].stringByStandardizingPath;
 if(![full hasPrefix:[base stringByAppendingString:@"/"]]){if(error)*error=TFAIToolError(@"路径须位于当前项目内");return nil;}
 NSString *walk=base;NSArray *parts=[relative pathComponents];
 for(NSUInteger i=0;i<parts.count;i++) {walk=[walk stringByAppendingPathComponent:parts[i]];struct stat st;if(lstat(walk.fileSystemRepresentation,&st)==0){if(S_ISLNK(st.st_mode)||(!S_ISREG(st.st_mode)&&!S_ISDIR(st.st_mode))||((i+1<parts.count||allowDirectory)&&!S_ISDIR(st.st_mode)&&i+1<parts.count)){if(error)*error=TFAIToolError(@"AI 工具不跟随符号链接或特殊文件");return nil;}if(i+1==parts.count&&!allowDirectory&&S_ISDIR(st.st_mode)){if(error)*error=TFAIToolError(@"此操作只接受普通文件");return nil;}}}
 return full;
}
NSString *TFAIPrivateDirectory(NSString *projectID,NSString *sessionID){NSString *base=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;NSString *project=TFAIDigest([projectID dataUsingEncoding:NSUTF8StringEncoding]),*session=TFAIDigest([sessionID dataUsingEncoding:NSUTF8StringEncoding]);return [[[base stringByAppendingPathComponent:@"TweakForgeAI/Tools"] stringByAppendingPathComponent:project] stringByAppendingPathComponent:session];}
BOOL TFAIWriteJSON(id value,NSString *path,NSError **error){NSData *data=TFAIJSON(value,error);if(!data)return NO;if(![NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return NO;BOOL ok=[data writeToFile:path options:NSDataWritingAtomic error:error];if(ok)[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];return ok;}
id TFAIReadJSON(NSString *path){NSData *data=[NSData dataWithContentsOfFile:path];return data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil]:nil;}
BOOL TFAIContainsSecret(NSString *text){if(!text.length)return NO;NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"(?i)(-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|github_pat_[A-Za-z0-9_]{12,}|gh[pousr]_[A-Za-z0-9]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{20,}|(?:authorization\\s*[:=]\\s*[\\\"']?(?:bearer|basic)\\s+[A-Za-z0-9+/_.-]{12,}))" options:0 error:nil];return [rx firstMatchInString:text options:0 range:NSMakeRange(0,text.length)]!=nil;}
