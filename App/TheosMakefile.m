#import "TheosMakefile.h"
#import <glob.h>
#import <fnmatch.h>

NSArray<NSString *> *TMCMakeWords(NSString *value) {
    NSMutableArray *words=[NSMutableArray new];NSMutableString *word=[NSMutableString new];
    unichar quote=0;BOOL escape=NO;
    for(NSUInteger i=0;i<value.length;i++){
        unichar c=[value characterAtIndex:i];
        if(escape){[word appendFormat:@"%C",c];escape=NO;continue;}
        if(c=='\\'){escape=YES;continue;}
        if(quote){if(c==quote)quote=0;else [word appendFormat:@"%C",c];continue;}
        if(c=='\''||c=='"'){quote=c;continue;}
        if([NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:c]){if(word.length){[words addObject:word.copy];[word setString:@""];}continue;}
        [word appendFormat:@"%C",c];
    }
    if(escape)[word appendString:@"\\"];
    if(word.length)[words addObject:word.copy];return words;
}
static NSString *Trim(NSString *s){return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static NSError *MakeError(NSString *s){return [NSError errorWithDomain:@"TweakForgeMakefile" code:1 userInfo:@{NSLocalizedDescriptionKey:s}];}
static NSString *Relative(NSString *s){
    s=[s stringByStandardizingPath];
    if(s.isAbsolutePath||[s.pathComponents containsObject:@".."]||[s containsString:@":"]||[s rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return nil;
    return s;
}
static NSArray *Arguments(NSString *s){
    NSMutableArray *a=[NSMutableArray new];NSUInteger start=0;NSInteger depth=0;
    for(NSUInteger i=0;i<s.length;i++){
        unichar c=[s characterAtIndex:i];if(c=='('||c=='{')depth++;if(c==')'||c=='}')depth--;
        if(c==','&&depth==0){[a addObject:[s substringWithRange:NSMakeRange(start,i-start)]];start=i+1;}
    }
    [a addObject:[s substringFromIndex:start]];return a;
}
@interface TMCMakeReader:NSObject
@property NSString *root;
@property NSMutableDictionary<NSString *,NSString *> *values;
@property NSMutableSet *simple;
@property NSMutableArray *notes;
@property NSMutableSet *stack;
@property NSError *failure;
@property NSUInteger lines;
- (NSString *)expand:(NSString *)text depth:(NSUInteger)depth;
- (void)read:(NSString *)path depth:(NSUInteger)depth;
@end
@implementation TMCMakeReader
- (void)note:(NSString *)text {if(self.notes.count<100&&![self.notes containsObject:text])[self.notes addObject:text];}
- (NSString *)variable:(NSString *)name depth:(NSUInteger)depth {
    name=Trim(name);NSString *value=self.values[name];
    if(!value){
        // Undefined ordinary Make variables expand to empty. Host/toolchain variables
        // are deliberately unresolved rather than read from the process environment.
        if([name hasPrefix:@"THEOS"]||[@[@"HOME",@"PATH",@"SDKROOT"] containsObject:name])return nil;
        return @"";
    }
    return [self.simple containsObject:name]?value:[self expand:value depth:depth+1];
}
- (NSString *)expression:(NSString *)expression depth:(NSUInteger)depth {
    NSRange space=[expression rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(space.location==NSNotFound){NSString *name=[self expand:expression depth:depth+1];return name?[self variable:name depth:depth+1]:nil;}
    NSString *function=[expression substringToIndex:space.location];NSArray *raw=Arguments([expression substringFromIndex:space.location+1]);
    if(![@[@"wildcard",@"addprefix",@"addsuffix",@"filter",@"filter-out",@"sort",@"strip",@"patsubst",@"subst"] containsObject:function]){[self note:[NSString stringWithFormat:@"未执行 Make 函数 %@；相关配置请手动补充。",function]];return nil;}
    NSMutableArray *args=[NSMutableArray new];for(NSString *a in raw){NSString *v=[self expand:a depth:depth+1];if(!v)return nil;[args addObject:v];}
    if([function isEqual:@"subst"]){if(args.count!=3)return nil;return [args[2] stringByReplacingOccurrencesOfString:args[0] withString:args[1]];}
    if([function isEqual:@"strip"]&&args.count==1)return [TMCMakeWords(args[0]) componentsJoinedByString:@" "];
    NSMutableArray *out=[NSMutableArray new];
    if([function isEqual:@"wildcard"]&&args.count==1){
        for(NSString *pattern in TMCMakeWords(args[0])){
            NSString *relative=Relative(pattern);if(!relative){[self note:@"已跳过工程目录以外的 wildcard 路径。"];return nil;}
            glob_t found={0};int status=glob([[self.root stringByAppendingPathComponent:relative] fileSystemRepresentation],0,NULL,&found);
            if(status!=0&&status!=GLOB_NOMATCH){globfree(&found);return nil;}
            for(size_t i=0;i<found.gl_pathc;i++){
                NSString *p=[NSFileManager.defaultManager stringWithFileSystemRepresentation:found.gl_pathv[i] length:strlen(found.gl_pathv[i])];
                if([p hasPrefix:[self.root stringByAppendingString:@"/"]])[out addObject:[p substringFromIndex:self.root.length+1]];
                if(out.count>100000){globfree(&found);return nil;}
            }
            globfree(&found);
        }
    }else if([function isEqual:@"sort"]&&args.count==1){[out addObjectsFromArray:[NSOrderedSet orderedSetWithArray:TMCMakeWords(args[0])].array];[out sortUsingSelector:@selector(compare:)];}
    else if(( [function isEqual:@"addprefix"]||[function isEqual:@"addsuffix"])&&args.count==2){
        for(NSString *word in TMCMakeWords(args[1]))[out addObject:[function isEqual:@"addprefix"]?[Trim(args[0]) stringByAppendingString:word]:[word stringByAppendingString:Trim(args[0])]];
    }else if(( [function isEqual:@"filter"]||[function isEqual:@"filter-out"])&&args.count==2){
        for(NSString *word in TMCMakeWords(args[1])){BOOL matched=NO;for(NSString *pattern in TMCMakeWords(args[0]))if(fnmatch([[pattern stringByReplacingOccurrencesOfString:@"%" withString:@"*"] UTF8String],word.UTF8String,0)==0)matched=YES;if(matched==[function isEqual:@"filter"])[out addObject:word];}
    }else if([function isEqual:@"patsubst"]&&args.count==3){
        NSString *pattern=Trim(args[0]),*replacement=Trim(args[1]);NSArray *pieces=[pattern componentsSeparatedByString:@"%"];
        for(NSString *word in TMCMakeWords(args[2])){
            if(pieces.count==2&&word.length>=[pieces[0] length]+[pieces[1] length]&&(![pieces[0] length]||[word hasPrefix:pieces[0]])&&(![pieces[1] length]||[word hasSuffix:pieces[1]])){
                NSString *stem=[word substringWithRange:NSMakeRange([pieces[0] length],word.length-[pieces[0] length]-[pieces[1] length])];[out addObject:[replacement stringByReplacingOccurrencesOfString:@"%" withString:stem]];
            }else [out addObject:[word isEqual:pattern]?replacement:word];
        }
    }else return nil;
    return [out componentsJoinedByString:@" "];
}
- (NSString *)expand:(NSString *)text depth:(NSUInteger)depth {
    if(depth>32||text.length>1024*1024||[text containsString:@"`"])return nil;
    NSMutableString *out=[NSMutableString new];
    for(NSUInteger i=0;i<text.length;i++){
        unichar c=[text characterAtIndex:i];if(c!='$'){[out appendFormat:@"%C",c];continue;}
        if(++i>=text.length)return nil;c=[text characterAtIndex:i];
        if(c=='$'){[out appendString:@"$"];continue;}
        if(c!='('&&c!='{')return nil;
        NSUInteger start=i+1;NSMutableArray *closing=[NSMutableArray arrayWithObject:@(c=='('?')':'}')];
        for(i=start;i<text.length;i++){
            unichar next=[text characterAtIndex:i];
            if(next=='('||next=='{')[closing addObject:@(next=='('?')':'}')];
            else if(next==[closing.lastObject unsignedShortValue]){[closing removeLastObject];if(!closing.count)break;}
        }
        if(closing.count)return nil;
        NSString *value=[self expression:[text substringWithRange:NSMakeRange(start,i-start)] depth:depth+1];if(!value)return nil;
        [out appendString:value];if(out.length>1024*1024)return nil;
    }
    return out;
}
- (NSDictionary *)condition:(NSString *)statement {
    NSString *directive=TMCMakeWords(statement).firstObject;
            NSString *body=Trim([statement substringFromIndex:directive.length]);BOOL known=YES,truth=NO;
            if([directive isEqual:@"ifdef"]||[directive isEqual:@"ifndef"]){NSString *name=[self expand:body depth:0];NSString *v=name?[self variable:name depth:0]:nil;known=v!=nil;truth=v.length>0;if([directive isEqual:@"ifndef"])truth=!truth;}
            else {
                NSArray *pair=[body hasPrefix:@"("]&&[body hasSuffix:@")"]?Arguments([body substringWithRange:NSMakeRange(1,body.length-2)]):TMCMakeWords(body);
                NSString *a=pair.count==2?[self expand:pair[0] depth:0]:nil,*b=pair.count==2?[self expand:pair[1] depth:0]:nil;known=a&&b;truth=known&&[Trim(a) isEqual:Trim(b)];if([directive isEqual:@"ifneq"])truth=!truth;
            }
    return @{@"known":@(known),@"truth":@(truth)};
}
- (void)read:(NSString *)path depth:(NSUInteger)depth {
    if(depth>16||[self.stack containsObject:path]){self.failure=MakeError(@"Makefile include 循环或层级过深");return;}
    NSString *resolved=path.stringByResolvingSymlinksInPath;
    if(![resolved hasPrefix:[self.root.stringByResolvingSymlinksInPath stringByAppendingString:@"/"]]){self.failure=MakeError(@"Makefile include 超出工程目录");return;}
    NSString *text=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if(!text||text.length>1024*1024){self.failure=MakeError(@"Makefile 读取失败或体积超出限制");return;}
    [self.stack addObject:path];
    text=[[text stringByReplacingOccurrencesOfString:@"\\\r\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\\\n" withString:@" "];
    NSMutableArray<NSMutableDictionary *> *conditions=[NSMutableArray new];BOOL active=YES;BOOL inDefine=NO;
    NSRegularExpression *assignment=[NSRegularExpression regularExpressionWithPattern:@"^(.+?)\\s*([+:?]?=)\\s*(.*)$" options:0 error:nil];
    for(NSString *rawLine in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){
        if(++self.lines>100000){self.failure=MakeError(@"Makefile 行数超出限制");break;}
        if([rawLine hasPrefix:@"\t"])continue;
        NSMutableString *line=[NSMutableString new];BOOL escaped=NO;
        for(NSUInteger i=0;i<rawLine.length;i++){unichar c=[rawLine characterAtIndex:i];if(c=='#'&&!escaped)break;[line appendFormat:@"%C",c];escaped=c=='\\'&&!escaped;}
        NSString *s=Trim(line);if(!s.length)continue;
        if([s hasPrefix:@"define "]){inDefine=YES;continue;}if([s isEqual:@"endef"]){inDefine=NO;continue;}if(inDefine)continue;
        NSArray *words=TMCMakeWords(s);NSString *directive=words.firstObject;
        if([@[@"ifeq",@"ifneq",@"ifdef",@"ifndef"] containsObject:directive]){
            NSDictionary *v=[self condition:s];BOOL known=[v[@"known"] boolValue],truth=[v[@"truth"] boolValue];
            if(!known)[self note:@"含未知条件的 Makefile 分支已跳过，请核对导入配置。"];
            [conditions addObject:[@{@"parent":@(active),@"taken":@(known&&truth),@"blocked":@(!known),@"else":@NO} mutableCopy]];active=active&&known&&truth;continue;
        }
        if([directive isEqual:@"else"]){
            if(!conditions.count||[conditions.lastObject[@"else"] boolValue]){self.failure=MakeError(@"Makefile else 缺少条件或重复出现");break;}
            NSMutableDictionary *frame=conditions.lastObject;BOOL available=![frame[@"taken"] boolValue]&&![frame[@"blocked"] boolValue];
            if(words.count==1){frame[@"else"]=@YES;active=[frame[@"parent"] boolValue]&&available;frame[@"taken"]=@YES;}
            else{
                NSString *next=Trim([s substringFromIndex:4]);NSString *kind=TMCMakeWords(next).firstObject;
                if(![@[@"ifeq",@"ifneq",@"ifdef",@"ifndef"] containsObject:kind]){self.failure=MakeError(@"尚未支持此 Makefile else 条件写法");break;}
                NSDictionary *v=available?[self condition:next]:@{@"known":@YES,@"truth":@NO};
                if(available&&![v[@"known"] boolValue]){frame[@"blocked"]=@YES;[self note:@"含未知条件的 Makefile 分支已跳过，请核对导入配置。"];
                }
                BOOL selected=available&&[v[@"known"] boolValue]&&[v[@"truth"] boolValue];active=[frame[@"parent"] boolValue]&&selected;if(selected)frame[@"taken"]=@YES;
            }
            continue;
        }
        if([directive isEqual:@"endif"]){if(!conditions.count){self.failure=MakeError(@"Makefile endif 缺少对应条件");break;}active=[conditions.lastObject[@"parent"] boolValue];[conditions removeLastObject];continue;}
        if(!active)continue;
        if([@[@"include",@"-include",@"sinclude"] containsObject:directive]){
            NSString *body=Trim([s substringFromIndex:directive.length]);
            if([body containsString:@"$(THEOS)"]||[body containsString:@"${THEOS}"]||[body containsString:@"THEOS_MAKE_PATH"]){continue;}
            NSString *expanded=[self expand:body depth:0];if(!expanded){[self note:@"有 include 路径待手动配置。"];continue;}
            for(NSString *include in TMCMakeWords(expanded)){
                NSString *relative=Relative(include);if(!relative){self.failure=MakeError(@"Makefile include 超出工程目录");break;}
                NSString *child=[self.root stringByAppendingPathComponent:relative];
                if([NSFileManager.defaultManager fileExistsAtPath:child])[self read:child depth:depth+1];
                else if([directive isEqual:@"include"]){self.failure=MakeError([@"缺少 Makefile include 文件：" stringByAppendingString:include]);break;}
            }
            if(self.failure)break;continue;
        }
        for(NSString *prefix in @[@"export ",@"override ",@"private "])if([s hasPrefix:prefix])s=Trim([s substringFromIndex:prefix.length]);
        NSTextCheckingResult *match=[assignment firstMatchInString:s options:0 range:NSMakeRange(0,s.length)];if(!match)continue;
        NSString *key=[self expand:Trim([s substringWithRange:[match rangeAtIndex:1]]) depth:0];
        if(!key.length||[key rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound)continue;
        if([@[@"CURDIR",@"THEOS_PROJECT_DIR",@"SCHEME"] containsObject:key])continue;
        NSString *op=[s substringWithRange:[match rangeAtIndex:2]],*value=[s substringWithRange:[match rangeAtIndex:3]];
        if([op isEqual:@"?="]&&self.values[key])continue;
        if([op isEqual:@":="]||([op isEqual:@"+="]&&[self.simple containsObject:key])){
            NSString *expanded=[self expand:value depth:0];
            if(!expanded){self.values[key]=@"$(TMC_UNSUPPORTED unresolved)";[self.simple removeObject:key];continue;}
            value=expanded;
        }
        if([op isEqual:@"+="]&&self.values[key])value=[NSString stringWithFormat:@"%@ %@",self.values[key],value];
        else if([op isEqual:@":="])[self.simple addObject:key];else [self.simple removeObject:key];
        self.values[key]=value;
    }
    if(conditions.count&&!self.failure)self.failure=MakeError(@"Makefile 条件缺少 endif");
    [self.stack removeObject:path];
}
@end

NSDictionary *TMCReadTheosMakefile(NSString *root,NSError **error){
    NSString *path=[root stringByAppendingPathComponent:@"Makefile"];
    if(![NSFileManager.defaultManager fileExistsAtPath:path])path=[root stringByAppendingPathComponent:@"makefile"];
    if(![NSFileManager.defaultManager fileExistsAtPath:path])return @{@"settings":@{},@"unresolved":@{},@"notes":@[]};
    TMCMakeReader *reader=[TMCMakeReader new];reader.root=root.stringByStandardizingPath;
    reader.values=[@{@"CURDIR":@".",@"THEOS_PROJECT_DIR":@".",@"SCHEME":@"rootless"} mutableCopy];
    reader.simple=[NSMutableSet setWithArray:reader.values.allKeys];reader.notes=[NSMutableArray new];reader.stack=[NSMutableSet new];
    [reader read:path depth:0];if(reader.failure){if(error)*error=reader.failure;return nil;}
    NSMutableDictionary *settings=[NSMutableDictionary new],*unresolved=[NSMutableDictionary new];
    for(NSString *key in [reader.values.allKeys sortedArrayUsingSelector:@selector(compare:)]){
        NSString *value=[reader variable:key depth:0];if(value)settings[key]=TMCMakeWords(value);else unresolved[key]=reader.values[key];
    }
    return @{@"settings":settings,@"unresolved":unresolved,@"notes":reader.notes,@"present":@YES};
}
