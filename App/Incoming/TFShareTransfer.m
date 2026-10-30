#import "TFShareTransfer.h"
static NSString * const Prefix=@"TweakForge-Receive-";
NSString *TFShareTransferName(NSString *original,NSString *identifier){
 if(![original isKindOfClass:NSString.class]||![identifier isKindOfClass:NSString.class]||![[NSUUID alloc]initWithUUIDString:identifier])return nil;
 original=original.lastPathComponent;if(!original.length||[original hasPrefix:@"."])original=@"SharedFile";
 NSString *extension=original.pathExtension;if(extension.length>16||[extension lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>32)extension=@"";
 NSString *stem=extension.length?original.stringByDeletingPathExtension:original;
 NSMutableString *shortName=[NSMutableString new];
 [stem enumerateSubstringsInRange:NSMakeRange(0,stem.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *part,NSRange r,NSRange e,BOOL *stop){if([shortName lengthOfBytesUsingEncoding:NSUTF8StringEncoding]+[part lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>140){*stop=YES;return;}[shortName appendString:part];}];
 if(!shortName.length)[shortName appendString:@"SharedFile"];
 NSString *name=extension.length?[shortName stringByAppendingPathExtension:extension]:shortName;
 return [NSString stringWithFormat:@"%@%@--%@",Prefix,identifier,name];
}
NSString *TFShareTransferOriginalName(NSString *name){
 if(![name isKindOfClass:NSString.class]||![name isEqual:name.lastPathComponent]||![name hasPrefix:Prefix]||name.length<=Prefix.length+38)return nil;
 NSString *identifier=[name substringWithRange:NSMakeRange(Prefix.length,36)];
 if(![[NSUUID alloc]initWithUUIDString:identifier]||![[name substringWithRange:NSMakeRange(Prefix.length+36,2)] isEqual:@"--"])return nil;
 NSString *original=[name substringFromIndex:Prefix.length+38];
 return original.length&&![original hasPrefix:@"."]&&[original isEqual:original.lastPathComponent]?original:nil;
}
NSArray<NSURL *> *TFShareTransferPending(NSString *documents){
 NSFileManager *fm=NSFileManager.defaultManager;NSMutableArray *files=[NSMutableArray new];
 for(NSString *name in [fm contentsOfDirectoryAtPath:documents error:nil]){
  if(!TFShareTransferOriginalName(name))continue;
  NSString *path=[documents stringByAppendingPathComponent:name];NSDictionary *a=[fm attributesOfItemAtPath:path error:nil];
  if(![a[NSFileType] isEqual:NSFileTypeRegular]||[a[NSFileSize] unsignedLongLongValue]>4ULL*1024*1024*1024)continue;
  [files addObject:[NSURL fileURLWithPath:path]];if(files.count==20)break;
 }
 return files;
}
