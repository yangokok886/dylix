#import "ArchiveImport.h"
#import "TheosMakefile.h"
#import "../Vendor/libarchive-headers/archive.h"
#import "../Vendor/libarchive-headers/archive_entry.h"
#import <CoreFoundation/CoreFoundation.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

static const unsigned long long TMCMaxExpanded = 4ULL * 1024 * 1024 * 1024;
static const unsigned long long TMCMaxFile = 1024ULL * 1024 * 1024;
static const NSUInteger TMCMaxEntries = 100000;

static NSError *ImportError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"TweakForgeArchive" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL Fail(NSError **error, NSInteger code, NSString *message) {
    if(error)*error=ImportError(code,message);return NO;
}
static NSString *ArchiveFailure(struct archive *reader) {
    const char *raw=archive_error_string(reader);
    return raw ? ([NSString stringWithUTF8String:raw] ?: @"压缩包读取失败") : @"压缩包已损坏或使用了尚未支持的压缩方式";
}
static NSString *EntryName(struct archive_entry *entry) {
    const char *raw=archive_entry_pathname_utf8(entry);
    if(raw)return [NSString stringWithUTF8String:raw];
    raw=archive_entry_pathname(entry);if(!raw)return nil;
    NSString *name=[NSString stringWithUTF8String:raw];
    if(!name)name=[[NSString alloc] initWithBytes:raw length:strlen(raw) encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
    return name;
}
static NSString *CleanRelativePath(NSString *name) {
    if(!name.length||[name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return nil;
    name=[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    if([name hasPrefix:@"/"]||[name rangeOfString:@":"].location!=NSNotFound)return nil;
    NSMutableArray *parts=[NSMutableArray new];
    for(NSString *part in [name componentsSeparatedByString:@"/"]){
        if([part isEqual:@".."])return nil;
        if(part.length&&![part isEqual:@"."])[parts addObject:part];
    }
    return [parts componentsJoinedByString:@"/"];
}
static BOOL IgnoreMetadata(NSString *path) {
    for(NSString *part in path.pathComponents)
        if([part isEqual:@"__MACOSX"]||[part isEqual:@".DS_Store"]||[part hasPrefix:@"._"])return YES;
    return NO;
}

BOOL TMCExtractArchive(NSURL *input, NSURL *destination, NSString *password,
                       NSProgress *cancellation, TMCArchiveProgress progress, NSError **outError) {
    NSError *failure=nil;
    NSFileManager *fm=NSFileManager.defaultManager;
    if([fm fileExistsAtPath:destination.path])return Fail(outError,TMCArchiveInvalid,@"解压目标目录已存在");
    if(![fm createDirectoryAtURL:destination withIntermediateDirectories:YES attributes:nil error:outError])return NO;
    struct archive *reader=archive_read_new();
    // Only in-process filters: never let libarchive fall back to a child process.
    archive_read_support_filter_none(reader);
    archive_read_support_filter_gzip(reader);archive_read_support_filter_bzip2(reader);
    archive_read_support_filter_xz(reader);archive_read_support_filter_lzma(reader);
    archive_read_support_filter_compress(reader);
    archive_read_support_format_zip(reader);archive_read_support_format_7zip(reader);
    archive_read_support_format_rar(reader);archive_read_support_format_rar5(reader);
    archive_read_support_format_tar(reader);archive_read_support_format_cpio(reader);
    archive_read_support_format_ar(reader);archive_read_support_format_xar(reader);
    archive_read_support_format_lha(reader);archive_read_support_format_cab(reader);
    archive_read_support_format_raw(reader);
    if(password.length)archive_read_add_passphrase(reader,password.UTF8String);
    BOOL ok=YES;NSUInteger count=0;unsigned long long total=0;
    NSMutableSet *seen=[NSMutableSet new];
    if(archive_read_open_filename(reader,input.path.fileSystemRepresentation,65536)!=ARCHIVE_OK){
        NSString *message=ArchiveFailure(reader);
        NSInteger code=([message.lowercaseString containsString:@"passphrase"]||[message.lowercaseString containsString:@"password"])?TMCArchivePassword:TMCArchiveInvalid;
        ok=Fail(&failure,code,message);
    }
    struct archive_entry *entry=NULL;int status=ARCHIVE_EOF;
    while(ok&&(status=archive_read_next_header(reader,&entry))!=ARCHIVE_EOF){
        @autoreleasepool {
            if(cancellation.cancelled){ok=Fail(&failure,TMCArchiveCancelled,@"已取消解压");break;}
            if(status<ARCHIVE_WARN){
                NSString *message=ArchiveFailure(reader);
                ok=Fail(&failure,([message.lowercaseString containsString:@"passphrase"]||[message.lowercaseString containsString:@"password"])?TMCArchivePassword:TMCArchiveInvalid,message);break;
            }
            if(++count>TMCMaxEntries){ok=Fail(&failure,TMCArchiveLimit,@"压缩包条目超过 100000 个");break;}
            NSString *name=EntryName(entry);NSString *relative=CleanRelativePath(name);
            if(!relative){ok=Fail(&failure,TMCArchiveInvalid,@"压缩包包含越界路径或无效文件名");break;}
            if(IgnoreMetadata(relative)){if(archive_read_data_skip(reader)<ARCHIVE_WARN){ok=Fail(&failure,TMCArchiveInvalid,ArchiveFailure(reader));break;}continue;}
            mode_t type=archive_entry_filetype(entry);
            if(archive_format(reader)==ARCHIVE_FORMAT_RAW){
                if(archive_filter_code(reader,0)==ARCHIVE_FILTER_NONE){ok=Fail(&failure,TMCArchiveInvalid,@"所选文件不是支持的压缩包");break;}
                relative=CleanRelativePath(input.lastPathComponent.stringByDeletingPathExtension);
                if(!relative.length){ok=Fail(&failure,TMCArchiveInvalid,@"压缩文件没有有效的文件名");break;}
            }
            if(archive_entry_symlink(entry)||archive_entry_hardlink(entry)||!(type==AE_IFREG||type==AE_IFDIR)){
                ok=Fail(&failure,TMCArchiveInvalid,[NSString stringWithFormat:@"压缩包包含链接或特殊文件：%@。请使用普通源码文件重新压缩。",relative]);break;
            }
            if(!relative.length){if(type==AE_IFDIR)continue;ok=Fail(&failure,TMCArchiveInvalid,@"压缩包包含空文件路径");break;}
            NSString *target=[destination.path stringByAppendingPathComponent:relative];
            if(type==AE_IFDIR){
                if(![fm createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:&failure]){ok=NO;break;}
                continue;
            }
            NSString *collision=relative.precomposedStringWithCanonicalMapping.lowercaseString;
            if([seen containsObject:collision]){ok=Fail(&failure,TMCArchiveInvalid,[NSString stringWithFormat:@"压缩包有重名文件：%@",relative]);break;}
            [seen addObject:collision];
            la_int64_t declared=archive_entry_size(entry);
            if(declared>(la_int64_t)TMCMaxFile||(declared>0&&(unsigned long long)declared>TMCMaxExpanded-total)){
                ok=Fail(&failure,TMCArchiveLimit,@"解压限制：单文件 1 GB，工程总计 4 GB");break;
            }
            if(![fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&failure]){ok=NO;break;}
            int fd=open(target.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);
            if(fd<0){ok=Fail(&failure,TMCArchiveInvalid,[NSString stringWithFormat:@"创建解压文件失败：%@（%s）",relative,strerror(errno)]);break;}
            unsigned long long fileBytes=0;char buffer[65536];la_ssize_t length;
            while((length=archive_read_data(reader,buffer,sizeof(buffer)))>0){
                if(cancellation.cancelled){ok=Fail(&failure,TMCArchiveCancelled,@"已取消解压");break;}
                if((unsigned long long)length>TMCMaxFile-fileBytes||(unsigned long long)length>TMCMaxExpanded-total){ok=Fail(&failure,TMCArchiveLimit,@"解压限制：单文件 1 GB，工程总计 4 GB");break;}
                size_t written=0;
                while(written<(size_t)length){ssize_t n=write(fd,buffer+written,(size_t)length-written);if(n<0&&errno==EINTR)continue;if(n<=0){ok=Fail(&failure,TMCArchiveInvalid,@"写入解压文件失败，请检查剩余存储空间");break;}written+=(size_t)n;}
                if(!ok)break;
                fileBytes+=(unsigned long long)length;total+=(unsigned long long)length;
                if(progress)progress(count,total);
            }
            if(length<0&&ok){
                NSString *message=ArchiveFailure(reader);BOOL encrypted=archive_entry_is_encrypted(entry)>0;
                BOOL asksPassword=[message.lowercaseString containsString:@"passphrase"]||[message.lowercaseString containsString:@"password"];
                BOOL unsupported=[message.lowercaseString containsString:@"unsupported"]||[message.lowercaseString containsString:@"not supported"]||[message.lowercaseString containsString:@"unavailable"];
                ok=Fail(&failure,(!unsupported&&(asksPassword||encrypted))?TMCArchivePassword:TMCArchiveInvalid,message);
            }
            if(ok&&archive_entry_size_is_set(entry)&&declared>=0&&fileBytes!=(unsigned long long)declared)ok=Fail(&failure,TMCArchiveInvalid,@"解压文件长度与记录不一致，压缩包可能已损坏");
            if(close(fd)!=0&&ok)ok=Fail(&failure,TMCArchiveInvalid,@"保存解压文件失败");
            if(ok){
                // File data is inert; the app never executes extracted scripts.
                [fm setAttributes:@{NSFilePosixPermissions:@(archive_entry_perm(entry)&0111?0700:0600),NSFileModificationDate:[NSDate dateWithTimeIntervalSince1970:archive_entry_mtime(entry)]} ofItemAtPath:target error:nil];
                if(progress)progress(count,total);
            }
        }
    }
    if(archive_read_free(reader)<ARCHIVE_WARN&&ok)ok=Fail(&failure,TMCArchiveInvalid,@"压缩包校验失败");
    if(cancellation.cancelled&&ok)ok=Fail(&failure,TMCArchiveCancelled,@"已取消解压");
    if(!ok)[fm removeItemAtURL:destination error:nil];
    if(outError)*outError=failure;
    return ok;
}

static BOOL SkipDirectory(NSString *name) {
    return [@[@".git",@".svn",@".theos",@".build",@"build",@"DerivedData",@"packages",@"node_modules",@"__MACOSX",@"SDK",@"ClangInclude"] containsObject:name]
        ||[@[@"framework",@"xcframework",@"app",@"bundle",@"xcodeproj",@"xcworkspace"] containsObject:name.pathExtension.lowercaseString];
}
static NSArray *SourceFiles(NSString *root, NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;NSMutableArray *sources=[NSMutableArray new];
    NSDirectoryEnumerator *enumerator=[fm enumeratorAtPath:root];NSUInteger count=0;
    for(NSString *relative in enumerator){
        if(++count>TMCMaxEntries){if(error)*error=ImportError(TMCArchiveLimit,@"工程文件数量超出限制");return nil;}
        NSDictionary *attributes=[enumerator fileAttributes];
        if([attributes[NSFileType] isEqual:NSFileTypeDirectory]){if(SkipDirectory(relative.lastPathComponent)||relative.pathComponents.count>32)[enumerator skipDescendants];continue;}
        if(![attributes[NSFileType] isEqual:NSFileTypeRegular])continue;
        if([@[@"x",@"xm",@"m",@"mm",@"c",@"cpp"] containsObject:relative.pathExtension.lowercaseString])[sources addObject:relative];
    }
    return [sources sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}
static NSDictionary *ReadManifest(NSString *root,NSError **error) {
    NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"MobileCompiler.json"] options:0 error:error];
    if(!data)return nil;
    id result=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if(![result isKindOfClass:NSDictionary.class]){if(error)*error=ImportError(TMCArchiveProjectInvalid,@"MobileCompiler.json 应为 JSON 对象");return nil;}
    return result;
}

NSArray<NSDictionary *> *TMCArchiveProjects(NSString *root, NSProgress *cancellation, NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;NSMutableArray *candidates=[NSMutableArray new];
    NSMutableArray *queue=[NSMutableArray arrayWithObject:root];NSUInteger inspected=0;
    while(queue.count){
        if(cancellation.cancelled){if(error)*error=ImportError(TMCArchiveCancelled,@"已取消工程识别");return nil;}
        NSString *path=queue.firstObject;[queue removeObjectAtIndex:0];
        if(++inspected>TMCMaxEntries){if(error)*error=ImportError(TMCArchiveLimit,@"工程目录数量超出限制");return nil;}
        NSArray *names=[fm contentsOfDirectoryAtPath:path error:error];if(!names)return nil;
        BOOL manifest=[names containsObject:@"MobileCompiler.json"];
        BOOL marker=manifest||[names containsObject:@"control"]||[names containsObject:@"Makefile"]||[names containsObject:@"makefile"];
        if(marker){
            NSArray *sources=SourceFiles(path,error);if(!sources)return nil;
            if(sources.count||manifest){
                NSDictionary *config=manifest?ReadManifest(path,nil):nil;
                NSString *name=[config[@"name"] isKindOfClass:NSString.class]?config[@"name"]:path.lastPathComponent;
                [candidates addObject:@{@"root":path,@"name":name,@"relative":[path isEqual:root]?@"压缩包根目录":[path substringFromIndex:root.length+1],@"sources":@(sources.count)}];
                continue;
            }
        }
        for(NSString *name in [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)]){
            if(SkipDirectory(name))continue;
            NSString *child=[path stringByAppendingPathComponent:name];
            if([[fm attributesOfItemAtPath:child error:nil][NSFileType] isEqual:NSFileTypeDirectory]&&[child substringFromIndex:root.length].pathComponents.count<=32)[queue addObject:child];
        }
    }
    if(candidates.count)return candidates;
    NSArray *sources=SourceFiles(root,error);if(!sources)return nil;
    if(!sources.count){if(error)*error=ImportError(TMCArchiveProjectInvalid,@"压缩包中没有识别到 Objective-C、C/C++ 或 Logos 源码工程");return nil;}
    // Remove only a common wrapper directory; keep headers/resources beside sources.
    NSString *project=root;
    while(YES){
        NSMutableArray *useful=[NSMutableArray new];for(NSString *name in [fm contentsOfDirectoryAtPath:project error:nil])if(!IgnoreMetadata(name)&&![name hasPrefix:@"."])[useful addObject:name];
        if(useful.count!=1)break;
        NSString *child=[project stringByAppendingPathComponent:useful.firstObject];
        if(![[fm attributesOfItemAtPath:child error:nil][NSFileType] isEqual:NSFileTypeDirectory]||SkipDirectory(child.lastPathComponent))break;
        project=child;
    }
    return @[@{@"root":project,@"name":project.lastPathComponent,@"relative":[project isEqual:root]?@"压缩包根目录":[project substringFromIndex:root.length+1],@"sources":@(sources.count)}];
}

NSDictionary *TMCPrepareImportedProject(NSString *root, NSString *fallbackName, NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;NSString *manifest=[root stringByAppendingPathComponent:@"MobileCompiler.json"];
    BOOL existing=[fm fileExistsAtPath:manifest];
    NSMutableDictionary *config=existing?[ReadManifest(root,error) mutableCopy]:[NSMutableDictionary new];if(!config)return nil;
    for(NSString *key in @[@"packageSchemes",@"sources",@"includeDirectories",@"defines",@"warningFlags",@"frameworks",@"libraries",@"forcedIncludes"]){
        id value=config[key];if(!value)continue;
        if(![value isKindOfClass:NSArray.class]){if(error)*error=ImportError(TMCArchiveProjectInvalid,[key stringByAppendingString:@" 应为数组"]);return nil;}
        for(id item in value)if(![item isKindOfClass:NSString.class]){if(error)*error=ImportError(TMCArchiveProjectInvalid,[key stringByAppendingString:@" 应只包含字符串"]);return nil;}
    }
    for(NSString *key in @[@"name",@"productName",@"prefixHeader",@"optimization",@"logosGenerator",@"sdkVersion",@"deploymentTarget",@"cxxStandard",@"cStandard",@"outputPattern-deb",@"outputPattern-dylib"])if(config[key]&&![config[key] isKindOfClass:NSString.class]){if(error)*error=ImportError(TMCArchiveProjectInvalid,[key stringByAppendingString:@" 应为字符串"]);return nil;}
    if(config[@"packageSchemes"]&&![config[@"packageSchemes"] count]){if(error)*error=ImportError(TMCArchiveProjectInvalid,@"packageSchemes 至少选择一项");return nil;}
    for(NSString *scheme in config[@"packageSchemes"])if(![@[@"rootless",@"rootful",@"roothide"] containsObject:scheme]){if(error)*error=ImportError(TMCArchiveProjectInvalid,@"packageSchemes 包类型无效");return nil;}
    for(NSString *key in @[@"packageScheme",@"cpuArchitecture"]){NSArray *allowed=[key isEqual:@"packageScheme"]?@[@"rootless",@"rootful",@"roothide"]:@[@"arm64",@"arm64e"];if(config[key]&&![allowed containsObject:config[key]]){if(error)*error=ImportError(TMCArchiveProjectInvalid,[key stringByAppendingString:@" 值不受支持"]);return nil;}}
    for(NSString *key in @[@"package",@"exportDylib",@"collectErrors",@"objcArc"])if(config[key]&&![config[key] isKindOfClass:NSNumber.class]){if(error)*error=ImportError(TMCArchiveProjectInvalid,[key stringByAppendingString:@" 应为布尔值"]);return nil;}
    NSArray *sources=existing&&config[@"sources"]?config[@"sources"]:nil;
    NSDictionary *makeResult=existing?@{@"settings":@{},@"unresolved":@{},@"notes":@[]}:TMCReadTheosMakefile(root,error);
    if(!makeResult)return nil;
    NSDictionary *make=makeResult[@"settings"],*unresolved=makeResult[@"unresolved"];
    NSArray *targets=make[@"TWEAK_NAME"]?:make[@"LIBRARY_NAME"];
    NSString *target=targets.count==1?targets.firstObject:nil;
    NSString *sourceKey=target?[target stringByAppendingString:@"_FILES"]:nil;
    if((sourceKey&&unresolved[sourceKey])||unresolved[@"TWEAK_NAME"]||unresolved[@"LIBRARY_NAME"]){if(error)*error=ImportError(TMCArchiveProjectInvalid,@"Makefile 源列表含尚未支持的表达式，请在 MobileCompiler.json 中明确配置 sources；未执行 shell 或自定义命令。");return nil;}
    if(([make[@"TWEAK_NAME"] count]&&[make[@"LIBRARY_NAME"] count])||targets.count>1){if(error)*error=ImportError(TMCArchiveProjectInvalid,@"Makefile 包含多个构建目标，请分别导入并配置 MobileCompiler.json。");return nil;}
    NSArray *makeSources=sourceKey?make[sourceKey]:nil;
    if(makeSources)sources=[NSOrderedSet orderedSetWithArray:makeSources].array;
    else if(!sources)sources=SourceFiles(root,error);
    if(![sources isKindOfClass:NSArray.class]||!sources.count){if(error)*error=ImportError(TMCArchiveProjectInvalid,@"工程没有配置可编译的源码文件");return nil;}
    for(id source in sources){
        NSString *relative=[source isKindOfClass:NSString.class]?CleanRelativePath(source):nil;
        NSDictionary *attributes=relative?[fm attributesOfItemAtPath:[root stringByAppendingPathComponent:relative] error:nil]:nil;
        if(!relative.length||![attributes[NSFileType] isEqual:NSFileTypeRegular]||![@[@"x",@"xm",@"m",@"mm",@"c",@"cpp"] containsObject:relative.pathExtension.lowercaseString]){if(error)*error=ImportError(TMCArchiveProjectInvalid,[NSString stringWithFormat:@"工程源码路径无效：%@",source]);return nil;}
    }
    BOOL needsSourceList=existing&&!config[@"sources"];
    if(needsSourceList)config[@"sources"]=sources;
    if(!existing){
        NSString *name=fallbackName.length?fallbackName:root.lastPathComponent;
        config[@"name"]=name;config[@"sources"]=sources;
        NSMutableSet *includes=[NSMutableSet setWithObject:@"."];
        NSDirectoryEnumerator *files=[fm enumeratorAtPath:root];
        for(NSString *path in files){
            if([[files fileAttributes][NSFileType] isEqual:NSFileTypeDirectory]){if(SkipDirectory(path.lastPathComponent))[files skipDescendants];continue;}
            if([@[@"h",@"hpp"] containsObject:path.pathExtension.lowercaseString]&&includes.count<512)[includes addObject:path.stringByDeletingLastPathComponent.length?path.stringByDeletingLastPathComponent:@"."];
        }
        config[@"includeDirectories"]=[includes.allObjects sortedArrayUsingSelector:@selector(compare:)];
        config[@"frameworks"]=@[@"Foundation",@"UIKit"];config[@"libraries"]=@[];
        if(target.length){
            config[@"productName"]=target;
            NSArray *frameworks=[(make[@"ADDITIONAL_FRAMEWORKS"]?:@[]) arrayByAddingObjectsFromArray:make[[target stringByAppendingString:@"_FRAMEWORKS"]]?:@[]];
            if(frameworks.count)config[@"frameworks"]=[@[@"Foundation",@"UIKit"] arrayByAddingObjectsFromArray:frameworks];
            NSArray *libraries=[(make[@"ADDITIONAL_LIBRARIES"]?:@[]) arrayByAddingObjectsFromArray:make[[target stringByAppendingString:@"_LIBRARIES"]]?:@[]];if(libraries)config[@"libraries"]=libraries;
            NSMutableArray *defines=[NSMutableArray new],*warnings=[NSMutableArray new],*forced=[NSMutableArray new];
            NSMutableArray *flags=[NSMutableArray new];
            for(NSString *suffix in @[@"CFLAGS",@"CCFLAGS",@"OBJCFLAGS"]){
                [flags addObjectsFromArray:make[[@"ADDITIONAL_" stringByAppendingString:suffix]]?:@[]];
                [flags addObjectsFromArray:make[[target stringByAppendingFormat:@"_%@",suffix]]?:@[]];
            }
            for(NSUInteger i=0;i<flags.count;i++){
                NSString *flag=flags[i],*value=nil;
                if([@[@"-D",@"-I",@"-include"] containsObject:flag]){if(i+1<flags.count)value=flags[++i];}
                if([flag isEqual:@"-D"]&&value)[defines addObject:value];
                else if([flag hasPrefix:@"-D"]&&flag.length>2)[defines addObject:[flag substringFromIndex:2]];
                else if([flag isEqual:@"-I"]&&value){NSString *relative=[value isEqual:@"."]?@".":CleanRelativePath(value);if(relative)[includes addObject:relative];}
                else if([flag hasPrefix:@"-I"]&&flag.length>2){NSString *relative=CleanRelativePath([flag substringFromIndex:2]);if(relative)[includes addObject:relative];}
                else if([flag isEqual:@"-include"]&&value){NSString *relative=CleanRelativePath(value);if(relative.length)[forced addObject:relative];}
                else if([flag hasPrefix:@"-W"]||[flag isEqual:@"-w"])[warnings addObject:flag];
                else if([@[@"-O0",@"-O1",@"-O2",@"-O3",@"-Os",@"-Oz"] containsObject:flag])config[@"optimization"]=flag;
                else if([flag isEqual:@"-fno-objc-arc"])config[@"objcArc"]=@NO;
                else if([flag isEqual:@"-fobjc-arc"])config[@"objcArc"]=@YES;
                else if([flag hasPrefix:@"-std="]){NSString *standard=[flag substringFromIndex:5];if([standard containsString:@"++"])config[@"cxxStandard"]=standard;else config[@"cStandard"]=standard;}
            }
            config[@"defines"]=[NSOrderedSet orderedSetWithArray:defines].array;config[@"warningFlags"]=[NSOrderedSet orderedSetWithArray:warnings].array;config[@"includeDirectories"]=[includes.allObjects sortedArrayUsingSelector:@selector(compare:)];
            if(forced.count)config[@"forcedIncludes"]=[NSOrderedSet orderedSetWithArray:forced].array;
            NSArray *privateFrameworks=make[[target stringByAppendingString:@"_PRIVATE_FRAMEWORKS"]];
            if(privateFrameworks.count)config[@"frameworks"]=[config[@"frameworks"] arrayByAddingObjectsFromArray:privateFrameworks];
            NSMutableArray *linkFlags=[NSMutableArray new];[linkFlags addObjectsFromArray:make[@"ADDITIONAL_LDFLAGS"]?:@[]];[linkFlags addObjectsFromArray:make[[target stringByAppendingString:@"_LDFLAGS"]]?:@[]];
            NSMutableArray *linkLibraries=[config[@"libraries"] mutableCopy],*linkFrameworks=[config[@"frameworks"] mutableCopy];
            for(NSUInteger i=0;i<linkFlags.count;i++){NSString *flag=linkFlags[i];if([flag hasPrefix:@"-l"]&&flag.length>2)[linkLibraries addObject:[flag substringFromIndex:2]];else if([flag isEqual:@"-framework"]&&i+1<linkFlags.count)[linkFrameworks addObject:linkFlags[++i]];}
            config[@"frameworks"]=[NSOrderedSet orderedSetWithArray:linkFrameworks].array;config[@"libraries"]=[NSOrderedSet orderedSetWithArray:linkLibraries].array;
            NSString *generator=[make[@"LOGOS_DEFAULT_GENERATOR"] firstObject];if([@[@"internal",@"MobileSubstrate",@"libhooker"] containsObject:generator])config[@"logosGenerator"]=generator;
        }
        if([makeResult[@"present"] boolValue]){
            NSMutableArray *notes=[makeResult[@"notes"] mutableCopy];
            [notes addObject:@"已在本机解析常用 Make 变量、wildcard 和静态配置；SCHEME 按 rootless 选择。未执行 make、shell、配方或安装命令；未识别的编译/链接参数请核对。"];
            for(NSString *key in [unresolved.allKeys sortedArrayUsingSelector:@selector(compare:)])if(target&&[key hasPrefix:[target stringByAppendingString:@"_"]])[notes addObject:[@"待手动补充的 Make 变量：" stringByAppendingString:key]];
            config[@"importNotes"]=notes;
        }
        // Keep metadata as provided. Plain source archives build a dylib by default.
        NSUInteger filterCount=0;
        for(NSString *file in [fm contentsOfDirectoryAtPath:root error:nil])if([file.pathExtension.lowercaseString isEqual:@"plist"])filterCount++;
        config[@"package"]=@([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"control"]]&&filterCount==1);
        config[@"collectErrors"]=@YES;
    }
    if(!existing||needsSourceList){NSData *data=[NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:error];if(!data||![data writeToFile:manifest options:NSDataWritingAtomic error:error])return nil;}
    return @{@"sources":sources,@"name":[config[@"name"] isKindOfClass:NSString.class]?config[@"name"]:(fallbackName?:root.lastPathComponent),@"generatedManifest":@(!existing)};
}
