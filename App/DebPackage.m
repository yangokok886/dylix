#import "DebPackage.h"

static void octal(char *field, size_t length, unsigned long long value) {
    snprintf(field, length, "%0*llo", (int)length - 1, value);
}
static void tarEntry(NSMutableData *tar, NSString *path, NSData *contents, BOOL executable) {
    char header[512] = {0};
    NSString *leaf=path; if([path lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>100){leaf=path.lastPathComponent;strncpy(header+345,path.stringByDeletingLastPathComponent.UTF8String,154);}strncpy(header, leaf.UTF8String,100);
    octal(header + 100, 8, executable ? 0755 : 0644);
    octal(header + 108, 8, 0); octal(header + 116, 8, 0);
    octal(header + 124, 12, contents.length); octal(header + 136, 12, 0);
    memset(header + 148, ' ', 8); header[156] = '0';
    memcpy(header + 257, "ustar", 5); memcpy(header + 263, "00", 2);
    memcpy(header + 265, "root", 4); memcpy(header + 297, "wheel", 5);
    unsigned checksum = 0;
    for (size_t i = 0; i < sizeof(header); i++) checksum += (unsigned char)header[i];
    snprintf(header + 148, 8, "%06o", checksum); header[155] = ' ';
    [tar appendBytes:header length:sizeof(header)]; [tar appendData:contents];
    NSUInteger padding = (512 - contents.length % 512) % 512;
    [tar increaseLengthBy:padding];
}
static void arEntry(NSMutableData *ar, const char *name, NSData *contents) {
    char header[61];
    snprintf(header, sizeof(header), "%-16s%-12d%-6d%-6d%-8o%-10llu`\n", name, 0, 0, 0, 0644, (unsigned long long)contents.length);
    [ar appendBytes:header length:60]; [ar appendData:contents];
    if (contents.length % 2) [ar appendBytes:"\n" length:1];
}
NSString *TMCPackageScheme(NSDictionary *config,NSString *control){
 if([@[@"rootless",@"rootful",@"roothide"] containsObject:config[@"packageScheme"]])return config[@"packageScheme"];
 for(NSString *line in [control componentsSeparatedByString:@"\n"]){NSArray *parts=[line componentsSeparatedByString:@":"];if(parts.count==2&&[parts[0] caseInsensitiveCompare:@"Architecture"]==NSOrderedSame){NSString *arch=[parts[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if([arch isEqual:@"iphoneos-arm"])return @"rootful";if([arch isEqual:@"iphoneos-arm64e"])return @"roothide";}}return @"rootless";
}
NSString *TMCControlForScheme(NSString *control,NSString *scheme){
 NSString *arch=[scheme isEqual:@"rootful"]?@"iphoneos-arm":[scheme isEqual:@"roothide"]?@"iphoneos-arm64e":@"iphoneos-arm64";NSMutableArray *lines=[NSMutableArray new];
 for(NSString *line in [control componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])if(line.length&&![line.lowercaseString hasPrefix:@"architecture:"])[lines addObject:line];[lines addObject:[@"Architecture: " stringByAppendingString:arch]];return [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}
NSData *TMCDebPackage(NSData *dylib, NSString *name, NSString *bundleID, NSError **error) {return TMCDebPackageForScheme(dylib,name,bundleID,@"rootless",error);}
NSData *TMCDebPackageForScheme(NSData *dylib, NSString *name, NSString *bundleID,NSString *scheme, NSError **error) {return TMCDebPackageForProject(dylib,name,bundleID,scheme,nil,@{},error);}
NSData *TMCDebPackageForProject(NSData *dylib, NSString *name, NSString *bundleID,NSString *scheme, NSString *root, NSDictionary *config, NSError **error) {
    NSString *control = [NSString stringWithFormat:@"Package: local.mobilecompiler.%@\nName: %@\nVersion: 1.0.0\nArchitecture: iphoneos-arm64\nMaintainer: Mobile Compiler\nSection: Tweaks\nDepends: mobilesubstrate, firmware (>= 15.0)\nDescription: Built locally by Mobile Compiler\n", name.lowercaseString, name];
    NSDictionary *filter = @{@"Filter": @{@"Bundles": @[bundleID ?: @"com.example.target"]}};
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:filter format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    return TMCDebPackageWithResources(dylib, name, plist, TMCControlForScheme(control,scheme), root, scheme, config, error);
}
NSData *TMCDebPackageWithMetadata(NSData *dylib, NSString *name, NSData *filterPlist, NSString *control, NSError **error) {return TMCDebPackageWithResources(dylib,name,filterPlist,control,nil,nil,@{},error);}
NSData *TMCDebPackageWithResources(NSData *dylib, NSString *name, NSData *filterPlist, NSString *control, NSString *root, NSString *scheme, NSDictionary *config, NSError **error) {
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-."] invertedSet];
    if (!dylib.length || !name.length || name.length > 64 || [name rangeOfCharacterFromSet:bad].location != NSNotFound) {
        if (error) *error = [NSError errorWithDomain:@"Compiler" code:1 userInfo:@{NSLocalizedDescriptionKey: @"包名或产物无效"}];
        return nil;
    }
    id filter = filterPlist ? [NSPropertyListSerialization propertyListWithData:filterPlist options:NSPropertyListImmutable format:nil error:error] : nil;
    if (![filter isKindOfClass:NSDictionary.class] || ![filter[@"Filter"] isKindOfClass:NSDictionary.class] || ![filter[@"Filter"] count]) {
        if (error) *error = [NSError errorWithDomain:@"Compiler" code:2 userInfo:@{NSLocalizedDescriptionKey: @"过滤 plist 需要非空的 Filter 字典"}];
        return nil;
    }
    control = [control stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *line in [control componentsSeparatedByString:@"\n"]) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location != NSNotFound && ![line hasPrefix:@" "] && ![line hasPrefix:@"\t"]) {
            fields[[[line substringToIndex:colon.location] lowercaseString]] = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        }
    }
    for (NSString *key in @[@"package", @"version", @"architecture", @"maintainer", @"description"]) {
        if (![fields[key] length]) {
            if (error) *error = [NSError errorWithDomain:@"Compiler" code:3 userInfo:@{NSLocalizedDescriptionKey: [@"control 缺少字段：" stringByAppendingString:key]}];
            return nil;
        }
    }
    if (![@[@"iphoneos-arm64",@"iphoneos-arm",@"iphoneos-arm64e"] containsObject:fields[@"architecture"]]) {
        if (error) *error = [NSError errorWithDomain:@"Compiler" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Architecture 需为 iphoneos-arm64（无根）、iphoneos-arm（有根）或 iphoneos-arm64e（隐根）"}];
        return nil;
    }
    if (![control hasSuffix:@"\n"]) control = [control stringByAppendingString:@"\n"];
    NSMutableData *controlTar = [NSMutableData data];
    tarEntry(controlTar, @"./control", [control dataUsingEncoding:NSUTF8StringEncoding], NO);
    NSMutableData *dataTar = [NSMutableData data];
    NSString *directory=[fields[@"architecture"] isEqual:@"iphoneos-arm64"]?@"./var/jb/Library/MobileSubstrate/DynamicLibraries/":@"./Library/MobileSubstrate/DynamicLibraries/";
    NSString *base = [directory stringByAppendingString:name];
    tarEntry(dataTar, [base stringByAppendingString:@".dylib"], dylib, YES);
    tarEntry(dataTar, [base stringByAppendingString:@".plist"], filterPlist, NO);
    NSMutableSet *destinations=[NSMutableSet setWithArray:@[[base stringByAppendingString:@".dylib"],[base stringByAppendingString:@".plist"]]];
    NSMutableArray *entries=[NSMutableArray new];
    NSString *layout=[root stringByAppendingPathComponent:@"layout"];
    if(root&&[NSFileManager.defaultManager fileExistsAtPath:layout]){
      NSDirectoryEnumerator *enumerator=[NSFileManager.defaultManager enumeratorAtPath:layout];
      for(NSString *relative in enumerator){NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:[layout stringByAppendingPathComponent:relative] error:nil];if([a[NSFileType] isEqual:NSFileTypeDirectory])continue;[entries addObject:@{@"source":[@"layout" stringByAppendingPathComponent:relative],@"destination":relative}];}
    }
    id resources=config[@"resources"];
    if(resources&&![resources isKindOfClass:NSArray.class]){if(error)*error=[NSError errorWithDomain:@"Compiler" code:6 userInfo:@{NSLocalizedDescriptionKey:@"resources 应为 source/destination 对象数组"}];return nil;}
    for(id resource in resources){
      if(![resource isKindOfClass:NSDictionary.class]||![resource[@"source"] isKindOfClass:NSString.class]||![resource[@"destination"] isKindOfClass:NSString.class]){if(error)*error=[NSError errorWithDomain:@"Compiler" code:6 userInfo:@{NSLocalizedDescriptionKey:@"资源需明确 source 和 destination"}];return nil;}
      NSString *source=resource[@"source"],*target=resource[@"destination"],*full=[root stringByAppendingPathComponent:source];BOOL directory=NO;
      if(![NSFileManager.defaultManager fileExistsAtPath:full isDirectory:&directory]){if(error)*error=[NSError errorWithDomain:@"Compiler" code:6 userInfo:@{NSLocalizedDescriptionKey:[@"资源不存在：" stringByAppendingString:source]}];return nil;}
      if(directory){for(NSString *relative in [NSFileManager.defaultManager enumeratorAtPath:full]){NSString *f=[full stringByAppendingPathComponent:relative];if(![[NSFileManager.defaultManager attributesOfItemAtPath:f error:nil][NSFileType] isEqual:NSFileTypeDirectory])[entries addObject:@{@"source":[source stringByAppendingPathComponent:relative],@"destination":[target stringByAppendingPathComponent:relative]}];}}
      else [entries addObject:resource];
    }
    unsigned long long total=0;
    for(NSDictionary *entry in entries){NSString *source=entry[@"source"],*destination=entry[@"destination"],*full=[root stringByAppendingPathComponent:source];
      BOOL safe=root.length&&!source.isAbsolutePath&&!destination.isAbsolutePath&&![source.pathComponents containsObject:@".."]&&![destination.pathComponents containsObject:@".."]&&destination.length&&[full.stringByResolvingSymlinksInPath hasPrefix:[root.stringByResolvingSymlinksInPath stringByAppendingString:@"/"]];
      NSDictionary *a=safe?[NSFileManager.defaultManager attributesOfItemAtPath:full error:nil]:nil;
      if(!safe||![a[NSFileType] isEqual:NSFileTypeRegular]){if(error)*error=[NSError errorWithDomain:@"Compiler" code:6 userInfo:@{NSLocalizedDescriptionKey:@"资源路径含链接、特殊文件或超出项目"}];return nil;}
      BOOL script=[destination hasPrefix:@"DEBIAN/"];if(script&&[destination isEqual:@"DEBIAN/control"])continue;
      if(script&&![@[@"preinst",@"postinst",@"prerm",@"postrm",@"extrainst_",@"config",@"triggers",@"conffiles"] containsObject:[destination substringFromIndex:7]]){if(error)*error=[NSError errorWithDomain:@"Compiler" code:6 userInfo:@{NSLocalizedDescriptionKey:@"DEBIAN 中含未支持的维护文件"}];return nil;}
      if([destination hasPrefix:@"var/jb/"])destination=[destination substringFromIndex:7];
      NSString *path=script?[@"./" stringByAppendingString:destination.lastPathComponent]:[([fields[@"architecture"] isEqual:@"iphoneos-arm64"]?@"./var/jb/":@"./") stringByAppendingString:destination];
      NSString *key=script?[@"control:" stringByAppendingString:path]:path;
      unsigned long long size=[a[NSFileSize] unsignedLongLongValue];total+=size;
      if([destinations containsObject:key]||size>64*1024*1024||total>128*1024*1024||[path.lastPathComponent lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>100||[path.stringByDeletingLastPathComponent lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>154){if(error)*error=[NSError errorWithDomain:@"Compiler" code:6 userInfo:@{NSLocalizedDescriptionKey:@"资源重复、路径过长或超过打包限制（单文件 64 MB / 总计 128 MB）"}];return nil;}
      [destinations addObject:key];NSData *contents=[NSData dataWithContentsOfFile:full options:0 error:error];if(!contents)return nil;
      tarEntry(script?controlTar:dataTar,path,contents,script||([a[NSFilePosixPermissions] unsignedIntegerValue]&0111));
    }
    [controlTar increaseLengthBy:1024];
    [dataTar increaseLengthBy:1024];
    NSMutableData *deb = [NSMutableData dataWithBytes:"!<arch>\n" length:8];
    arEntry(deb, "debian-binary", [@"2.0\n" dataUsingEncoding:NSASCIIStringEncoding]);
    arEntry(deb, "control.tar", controlTar); arEntry(deb, "data.tar", dataTar);
    return deb;
}
