#import "TFShareGroups.h"
#import "TFIncoming.h"
#import <mach-o/loader.h>
#import <mach-o/fat.h>
static BOOL Fits(NSUInteger total,uint64_t at,uint64_t count){return at<=total&&count<=total-at;}
static uint32_t Read32(NSData *d,NSUInteger at){uint32_t value=0;memcpy(&value,(const char *)d.bytes+at,4);return value;}
NSDictionary *TFShareSignedEntitlements(NSData *input){
 if(![input isKindOfClass:NSData.class]||input.length<32||input.length>64*1024*1024)return @{};
 NSData *d=input;uint32_t magic=Read32(d,0);
 if(magic==FAT_CIGAM||magic==FAT_CIGAM_64){BOOL wide=magic==FAT_CIGAM_64;uint32_t count=__builtin_bswap32(Read32(d,4));NSUInteger stride=wide?32:20;if(!count||count>32||!Fits(d.length,8,(uint64_t)stride*count))return @{};uint64_t offset=0,size=0;if(wide){memcpy(&offset,(const char *)d.bytes+16,8);memcpy(&size,(const char *)d.bytes+24,8);offset=__builtin_bswap64(offset);size=__builtin_bswap64(size);}else{offset=__builtin_bswap32(Read32(d,16));size=__builtin_bswap32(Read32(d,20));}if(!Fits(d.length,offset,size)||size<32)return @{};d=[d subdataWithRange:NSMakeRange(offset,size)];}
 if(Read32(d,0)!=MH_MAGIC_64)return @{};struct mach_header_64 h;memcpy(&h,d.bytes,sizeof(h));if(h.ncmds>10000||!Fits(d.length,32,h.sizeofcmds))return @{};
 NSUInteger at=32,end=32+h.sizeofcmds;for(uint32_t i=0;i<h.ncmds;i++){
  if(!Fits(end,at,8))return @{};uint32_t cmd=Read32(d,at),size=Read32(d,at+4);if(size<8||!Fits(end,at,size))return @{};
  if(cmd==LC_CODE_SIGNATURE){if(size<16)return @{};uint32_t offset=Read32(d,at+8),length=Read32(d,at+12);if(length>1024*1024||length<12||!Fits(d.length,offset,length))return @{};
   NSData *signature=[d subdataWithRange:NSMakeRange(offset,length)];if(__builtin_bswap32(Read32(signature,0))!=0xfade0cc0)return @{};uint32_t total=__builtin_bswap32(Read32(signature,4)),count=__builtin_bswap32(Read32(signature,8));if(total>length||total<12||count>128||!Fits(total,12,(uint64_t)count*8))return @{};
   for(uint32_t j=0;j<count;j++){uint32_t slot=__builtin_bswap32(Read32(signature,12+j*8)),p=__builtin_bswap32(Read32(signature,16+j*8));if(slot!=5)continue;if(!Fits(total,p,8)||__builtin_bswap32(Read32(signature,p))!=0xfade7171)return @{};uint32_t len=__builtin_bswap32(Read32(signature,p+4));if(len<8||!Fits(total,p,len))return @{};id plist=[NSPropertyListSerialization propertyListWithData:[signature subdataWithRange:NSMakeRange(p+8,len-8)] options:NSPropertyListImmutable format:nil error:nil];return [plist isKindOfClass:NSDictionary.class]?plist:@{};
   }return @{};
  }at+=size;
 }return @{};
}
static NSArray *Groups(NSBundle *bundle){
 NSString *path=bundle.executablePath;if(!path)return @[];NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];if(![attrs[NSFileType] isEqual:NSFileTypeRegular]||[attrs[NSFileSize] unsignedLongLongValue]>64*1024*1024)return @[];
 NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];id groups=TFShareSignedEntitlements(data)[@"com.apple.security.application-groups"];return [groups isKindOfClass:NSArray.class]?groups:@[];
}
NSArray<NSString *> *TFShareCommonGroups(NSArray *a,NSArray *b){
 if(![a isKindOfClass:NSArray.class]||![b isKindOfClass:NSArray.class])return @[];NSMutableArray *groups=[NSMutableArray new];for(id value in a){if(![value isKindOfClass:NSString.class]||![value hasPrefix:@"group."]||[value length]>255||![b containsObject:value]||[groups containsObject:value])continue;[groups addObject:value];}
 [groups sortUsingSelector:@selector(compare:)];if([groups containsObject:TFShareGroup]){[groups removeObject:TFShareGroup];[groups insertObject:TFShareGroup atIndex:0];}return groups;
}
NSDictionary *TFShareResolveGroups(NSArray *mainGroups,NSArray *extensionGroups,NSURL *(^probe)(NSString *)){
 NSArray *common=TFShareCommonGroups(mainGroups,extensionGroups);NSArray *candidates=common.count?common:@[TFShareGroup];
 NSMutableArray *attempted=[NSMutableArray new],*usable=[NSMutableArray new];NSURL *selected=nil;NSString *selectedGroup=@"";
 for(NSString *group in candidates){NSURL *url=probe?probe(group):nil;BOOL available=[url isKindOfClass:NSURL.class]&&url.isFileURL;[attempted addObject:@{@"group":group,@"containerAvailable":@(available)}];if(!available)continue;[usable addObject:group];if(!selected){selected=url;selectedGroup=group;}}
 return @{@"commonGroups":common,@"attemptedGroups":attempted,@"usableGroups":usable,@"selectedGroup":selectedGroup,@"containerURL":selected?:NSNull.null};
}
static NSDictionary *Resolve(void){
 NSBundle *current=NSBundle.mainBundle,*main=current,*extension=nil;
 if([current.bundlePath.pathExtension isEqual:@"appex"]){extension=current;main=[NSBundle bundleWithPath:current.bundlePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent];}
 else extension=[NSBundle bundleWithPath:[current.bundlePath stringByAppendingPathComponent:@"PlugIns/TweakForgeShare.appex"]];
 NSArray *mainGroups=Groups(main),*extGroups=Groups(extension);
 NSMutableDictionary *result=[TFShareResolveGroups(mainGroups,extGroups,^NSURL *(NSString *group){return [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];}) mutableCopy];
 result[@"bundleID"]=current.bundleIdentifier?:@"";result[@"mainBundleID"]=main.bundleIdentifier?:@"";result[@"mainGroups"]=mainGroups;result[@"extensionGroups"]=extGroups;return result;
}
NSURL *TFShareContainer(void){id url=Resolve()[@"containerURL"];return [url isKindOfClass:NSURL.class]?url:nil;}
NSDictionary *TFShareContainerDiagnostics(void){NSMutableDictionary *result=[Resolve() mutableCopy];[result removeObjectForKey:@"containerURL"];result[@"build"]=NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]?:@"";result[@"note"]=@"attemptedGroups 列出逐一查询的实际结果；usableGroups 仅列出系统返回了容器的组。没有读取证书、令牌或设备标识。";return result;}
