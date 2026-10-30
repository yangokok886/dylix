#import "OutputNaming.h"
#import "DebPackage.h"

NSString *TMCDefaultOutputPattern(NSString *extension){return [extension isEqual:@"deb"]?@"{name}_{version}_{platform}-{packageArch}":@"{name}";}
NSDictionary<NSString *,NSString *> *TMCOutputContext(NSString *root,NSString *product,NSDate *date){
 NSString *control=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"control"] encoding:NSUTF8StringEncoding error:nil];NSMutableDictionary *meta=[NSMutableDictionary new];
 for(NSString *line in [control componentsSeparatedByString:@"\n"]){NSRange colon=[line rangeOfString:@":"];if(colon.location!=NSNotFound&&![line hasPrefix:@" "]&&![line hasPrefix:@"\t"])meta[[[line substringToIndex:colon.location] lowercaseString]]=[[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
 NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"MobileCompiler.json"]];id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;NSDictionary *config=TMCEffectiveBuildOptions([value isKindOfClass:NSDictionary.class]?value:@{},NSUserDefaults.standardUserDefaults);
 NSDateFormatter *formatter=[NSDateFormatter new];formatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];formatter.dateFormat=@"yyyyMMdd";NSString *day=[formatter stringFromDate:date];formatter.dateFormat=@"HHmmss";NSString *time=[formatter stringFromDate:date];
 NSString *name=[meta[@"name"] length]?meta[@"name"]:[config[@"name"] isKindOfClass:NSString.class]?config[@"name"]:product;
 NSString *scheme=TMCPackageScheme(config,control);NSString *packageArch=[scheme isEqual:@"rootful"]?@"iphoneos-arm":[scheme isEqual:@"roothide"]?@"iphoneos-arm64e":@"iphoneos-arm64";
 BOOL defaultMetadata=!control.length&&![config[@"package"] isEqual:@NO];
 return @{@"name":name?:product,@"product":product,@"version":[meta[@"version"] length]?meta[@"version"]:defaultMetadata?@"1.0.0":@"unversioned",@"platform":@"iphoneos",@"packageArch":[packageArch componentsSeparatedByString:@"-"].lastObject,@"scheme":scheme,@"architecture":packageArch,@"arch":[config[@"cpuArchitecture"] isEqual:@"arm64e"]?@"arm64e":@"arm64",@"date":day,@"time":time,@"package":[meta[@"package"] length]?meta[@"package"]:defaultMetadata?[@"local.mobilecompiler." stringByAppendingString:product.lowercaseString]:@"unpackaged",@"author":[meta[@"author"] length]?meta[@"author"]:[meta[@"maintainer"] length]?meta[@"maintainer"]:@"Unknown"};
}
static NSString *InvalidOutput(NSError **error,NSString *message){if(error)*error=[NSError errorWithDomain:@"OutputNaming" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];return nil;}
NSString *TMCOutputFilename(NSString *pattern,NSString *extension,NSDictionary<NSString *,NSString *> *context,NSError **error){
 if(![pattern isKindOfClass:NSString.class]||!pattern.length)return InvalidOutput(error,@"文件名模板不能为空");
 NSMutableString *name=[pattern mutableCopy];NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"\\{([^{}]+)\\}" options:0 error:nil];NSArray *matches=[regex matchesInString:pattern options:0 range:NSMakeRange(0,pattern.length)];
 NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:@"/\\:"] mutableCopy];NSMutableCharacterSet *unsafe=[bad mutableCopy];[unsafe formUnionWithCharacterSet:NSCharacterSet.controlCharacterSet];
 for(NSTextCheckingResult *match in matches.reverseObjectEnumerator){NSString *key=[pattern substringWithRange:[match rangeAtIndex:1]],*value=context[key];if(!value)return InvalidOutput(error,[@"未知模板参数：" stringByAppendingString:key]);value=[[value componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"_"];[name replaceCharactersInRange:match.range withString:value];}
 if([name rangeOfCharacterFromSet:unsafe].location!=NSNotFound||[name containsString:@"{"]||[name containsString:@"}"])return InvalidOutput(error,@"文件名模板含路径字符、控制符或未配对的大括号");
 NSString *base=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSString *suffix=[@"." stringByAppendingString:extension];if([base.lowercaseString hasSuffix:suffix])base=[base substringToIndex:base.length-suffix.length];
 if(!base.length||[base hasPrefix:@"."]||[base lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>180)return InvalidOutput(error,@"文件名应为可见名称，且展开后不超过180个UTF-8字节");
 return [base stringByAppendingPathExtension:extension];
}

NSDictionary *TMCEffectiveBuildOptions(NSDictionary *config,NSUserDefaults *defaults){
 NSMutableDictionary *resolved=[config mutableCopy]?:[NSMutableDictionary new];
 resolved[@"exportDylib"]=config[@"exportDylib"]?:([defaults objectForKey:@"StudioExportDylib"]?:@YES);
 resolved[@"package"]=config[@"package"]?:([defaults objectForKey:@"StudioPackageEnabled"]?:@YES);
 NSArray *schemes=config[@"packageSchemes"];if(![schemes isKindOfClass:NSArray.class]){NSString *legacy=config[@"packageScheme"];schemes=legacy?@[legacy]:[defaults arrayForKey:@"StudioPackageSchemes"]?:@[@"rootless"];}
 NSMutableArray *valid=[NSMutableArray new];for(NSString *scheme in @[@"rootless",@"rootful",@"roothide"])if([schemes containsObject:scheme])[valid addObject:scheme];resolved[@"packageSchemes"]=valid;resolved[@"packageScheme"]=valid.firstObject?:@"rootless";
 for(NSString *ext in @[@"deb",@"dylib"]){NSString *key=[@"outputPattern-" stringByAppendingString:ext];NSString *pattern=[config[key] isKindOfClass:NSString.class]?config[key]:nil;resolved[key]=pattern.length?pattern:([defaults stringForKey:[@"StudioOutputPattern-" stringByAppendingString:ext]]?:TMCDefaultOutputPattern(ext));}
 return resolved;
}

NSDictionary *TMCNamingContextForScheme(NSDictionary *context,NSString *scheme){NSMutableDictionary *c=[context mutableCopy];c[@"platform"]=@"iphoneos";c[@"packageArch"]=[scheme isEqual:@"rootful"]?@"arm":[scheme isEqual:@"roothide"]?@"arm64e":@"arm64";c[@"scheme"]=scheme;c[@"architecture"]=[NSString stringWithFormat:@"%@-%@",c[@"platform"],c[@"packageArch"]];return c;}
NSString *TMCVariantOutputFilename(NSString *pattern,NSString *extension,NSDictionary *context,NSArray *schemes,NSString *scheme,NSError **error){
 NSMutableSet *used=[NSMutableSet new];for(NSString *item in schemes){NSString *base=TMCOutputFilename(pattern,extension,TMCNamingContextForScheme(context,item),error);if(!base)return nil;NSString *name=base;NSUInteger number=2;while([used containsObject:name.lowercaseString]){name=[[base.stringByDeletingPathExtension stringByAppendingFormat:@"-%lu",(unsigned long)number++] stringByAppendingPathExtension:extension];}if([name lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>190)return InvalidOutput(error,@"重名编号后的文件名过长");[used addObject:name.lowercaseString];if([item isEqual:scheme])return name;}return InvalidOutput(error,@"构建包类型未包含当前目标");
}
