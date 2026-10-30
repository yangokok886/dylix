#import "StorageSpace.h"
#import <sys/stat.h>
#import <CommonCrypto/CommonDigest.h>
static NSError *SE(NSString *text){return [NSError errorWithDomain:@"TweakForge.Storage" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
static NSString *Join(NSString *base,NSString *name){return [base stringByAppendingPathComponent:name];}
static BOOL RealDirectory(NSString *path){struct stat st;return lstat(path.fileSystemRepresentation,&st)==0&&S_ISDIR(st.st_mode);}
static NSString *Category(NSString *relative,BOOL documents){
 NSArray *parts=relative.pathComponents;NSString *top=parts.firstObject?:@"";
 if(documents){
  if([top isEqual:@"Projects"])return @"projects";
  if([top isEqual:@".StudioTrash"])return @"trash";
  if([top isEqual:@"AIClassDumpInputs"])return @"ipa";
  if([top isEqual:@"ClassDumpExports"])return @"exports";
  if([top hasPrefix:@"ClassDump-"]){NSString *suffix=[top substringFromIndex:10];if(suffix.length>=36&&[[NSUUID alloc]initWithUUIDString:[suffix substringToIndex:36]]&&(suffix.length==36||(suffix.length==82&&[[suffix substringFromIndex:36] hasPrefix:@".previous-"]&&[[NSUUID alloc]initWithUUIDString:[suffix substringFromIndex:46]])))return @"headers";}
  for(NSString *prefix in @[@"Build-",@"Snapshot-"])if([top hasPrefix:prefix]&&[[NSUUID alloc]initWithUUIDString:[top substringFromIndex:prefix.length]])return @"builds";
 }else{
  if([top isEqual:@"Caches"])return @"cache";
  if([relative hasPrefix:@"Application Support/TweakForgeAI/Sessions/"])return @"sessions";
  if([relative hasPrefix:@"Application Support/TweakForgeAI/Attachments/"]||[relative hasPrefix:@"Application Support/TweakForgeAI/Binaries/"])return @"attachments";
  if([relative hasPrefix:@"Application Support/TweakForgeAI/Tools/"])return @"backups";
 }
 return @"other";
}
static NSArray *Definitions(void){return @[
 @{@"id":@"cache",@"name":@"SDK 与缓存",@"level":@"可重新生成",@"impact":@"SDK 会在下次构建时重新解压，首次构建稍慢。",@"clear":@YES,@"symbol":@"arrow.triangle.2.circlepath"},
 @{@"id":@"temporary",@"name":@"过期临时文件",@"level":@"低重要性",@"impact":@"仅清理本软件生成且超过 24 小时的临时文件。",@"clear":@YES,@"symbol":@"clock.arrow.circlepath"},
 @{@"id":@"builds",@"name":@"构建结果与源码快照",@"level":@"请先导出产物",@"impact":@"删除 dylib、deb、构建日志和快照；项目源码保留，需重新构建生成结果。",@"clear":@YES,@"symbol":@"shippingbox"},
 @{@"id":@"exports",@"name":@"头文件导出 ZIP",@"level":@"影响分享",@"impact":@"删除导出的 ZIP，包括历史备份。保留的 IPA 可再次生成；先保存需要的副本。",@"clear":@YES,@"symbol":@"doc.zipper"},
 @{@"id":@"headers",@"name":@"导出头文件",@"level":@"重要文件",@"impact":@"会话里的头文件目录将失效，包括旧版备份。需保留原 IPA 才能重新导出。",@"clear":@YES,@"symbol":@"curlybraces"},
 @{@"id":@"ipa",@"name":@"AI 导入的 IPA 副本",@"level":@"重要输入",@"impact":@"AI 将失去这些 IPA 的本机读取入口，后续导出需重新选择原 IPA。外部原文件保留。",@"clear":@YES,@"symbol":@"app.badge"},
 @{@"id":@"attachments",@"name":@"AI 参考附件与二进制",@"level":@"重要输入",@"impact":@"删除本机参考副本；相关会话再次读取或分析时需重新添加。聊天记录保留。",@"clear":@YES,@"symbol":@"paperclip"},
 @{@"id":@"trash",@"name":@"项目回收站",@"level":@"清理后不可恢复",@"impact":@"永久删除回收站项目，提前结束剩余的 7 天恢复期。",@"clear":@YES,@"symbol":@"trash"},
 @{@"id":@"projects",@"name":@"项目源码与 Git 历史",@"level":@"保留",@"impact":@"通过项目列表管理，清理不会删除这些内容。",@"clear":@NO,@"symbol":@"folder"},
 @{@"id":@"sessions",@"name":@"AI 会话记录",@"level":@"保留",@"impact":@"包括消息中的图片与已发送文本；通过会话列表管理。",@"clear":@NO,@"symbol":@"bubble.left.and.bubble.right"},
 @{@"id":@"backups",@"name":@"AI 修改备份与操作记录",@"level":@"保留",@"impact":@"用于撤回与审查操作，清理不会删除。",@"clear":@NO,@"symbol":@"arrow.uturn.backward"},
 @{@"id":@"application",@"name":@"软件与内置工具链",@"level":@"必要内容",@"impact":@"程序、编译器和内置资源，保留。",@"clear":@NO,@"symbol":@"app"},
 @{@"id":@"other",@"name":@"设置与其他本机数据",@"level":@"保留",@"impact":@"包含偏好、导入文件及未分类内容，清理不会删除。",@"clear":@NO,@"symbol":@"internaldrive"}];}
// Physical blocks, never following symbolic links. Fingerprint includes descendants,
// so a changed nested file invalidates a previously confirmed deletion plan.
static NSDictionary *Measure(NSString *path){
 struct stat st;if(lstat(path.fileSystemRepresentation,&st)!=0||S_ISLNK(st.st_mode))return @{@"bytes":@0,@"signature":@"missing-or-link"};
 NSMutableData *digest=[NSMutableData dataWithLength:32];__block unsigned long long bytes=0;NSMutableSet *inodes=[NSMutableSet new];
 void (^visit)(NSString *,struct stat)=^(NSString *relative,struct stat s){
 NSString *entry=[NSString stringWithFormat:@"%@|%llu|%llu|%llu|%u|%lld.%ld|%lld.%ld",relative,(unsigned long long)s.st_dev,(unsigned long long)s.st_ino,(unsigned long long)s.st_size,s.st_mode,(long long)s.st_mtimespec.tv_sec,s.st_mtimespec.tv_nsec,(long long)s.st_ctimespec.tv_sec,s.st_ctimespec.tv_nsec];NSData *data=[entry dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[32];CC_SHA256(data.bytes,(CC_LONG)data.length,hash);for(int i=0;i<32;i++)((unsigned char *)digest.mutableBytes)[i]^=hash[i];
 // Only multiply-linked regular files need inode bookkeeping.
 BOOL duplicate=NO;if(S_ISREG(s.st_mode)&&s.st_nlink>1){NSString *inode=[NSString stringWithFormat:@"%llu:%llu",(unsigned long long)s.st_dev,(unsigned long long)s.st_ino];duplicate=[inodes containsObject:inode];[inodes addObject:inode];}if(!duplicate)bytes+=(unsigned long long)s.st_blocks*512;
 };
 visit(@"",st);if(S_ISDIR(st.st_mode)){NSDirectoryEnumerator *enumerator=[NSFileManager.defaultManager enumeratorAtPath:path];for(NSString *relative in enumerator){@autoreleasepool{struct stat child;if(lstat(Join(path,relative).fileSystemRepresentation,&child))continue;if(S_ISLNK(child.st_mode))[enumerator skipDescendants];visit(relative,child);}}}
 NSMutableString *signature=[NSMutableString new];for(int i=0;i<32;i++)[signature appendFormat:@"%02x",((unsigned char *)digest.bytes)[i]];return @{@"bytes":@(bytes),@"signature":signature};
}
static void Roots(NSString *base,BOOL documents,NSMutableArray *out){if(!RealDirectory(base))return;for(NSString *top in [NSFileManager.defaultManager contentsOfDirectoryAtPath:base error:nil]){NSString *path=Join(base,top);struct stat st;if(lstat(path.fileSystemRepresentation,&st)||S_ISLNK(st.st_mode))continue;
 if(!documents&&[top isEqual:@"Application Support"]&&RealDirectory(path)){NSString *ai=Join(path,@"TweakForgeAI");for(NSString *name in RealDirectory(ai)?[NSFileManager.defaultManager contentsOfDirectoryAtPath:ai error:nil]:@[]){NSString *child=Join(ai,name);if(!RealDirectory(ai)||!RealDirectory(child))continue;[out addObject:@{@"path":child,@"category":Category([[@"Application Support/TweakForgeAI" stringByAppendingPathComponent:name] stringByAppendingString:@"/"],NO)}];} // Count other Application Support paths without double-counting AI.
 for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil])if(![name isEqual:@"TweakForgeAI"])[out addObject:@{@"path":Join(path,name),@"category":@"other"}];continue;}
 [out addObject:@{@"path":path,@"category":Category(top,documents)}];}}
static NSDictionary *StorageScan(NSString *documents,NSString *library,NSString *temporary,NSString *bundle,void(^progress)(NSDictionary *)){
 NSMutableArray *roots=[NSMutableArray new];Roots(documents,YES,roots);Roots(library,NO,roots);
 for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:temporary error:nil]){NSString *path=Join(temporary,name);struct stat st;if(lstat(path.fileSystemRepresentation,&st)||S_ISLNK(st.st_mode))continue;BOOL known=NO;for(NSString *prefix in @[@"classdump-image-",@"TFAI-Extract-",@"ClassDump-",@"TweakForge-"])if([name hasPrefix:prefix])known=YES;BOOL old=NSDate.date.timeIntervalSince1970-st.st_mtimespec.tv_sec>86400;[roots addObject:@{@"path":path,@"category":known&&old?@"temporary":@"other"}];}
 if(bundle.length)[roots addObject:@{@"path":bundle,@"category":@"application"}];
 NSMutableArray *entries=[NSMutableArray new];NSMutableDictionary *totals=[NSMutableDictionary new];
 NSDictionary *fs=[NSFileManager.defaultManager attributesOfFileSystemForPath:documents error:nil]?:@{};
 NSMutableDictionary *remaining=[NSMutableDictionary new];for(NSDictionary *r in roots)remaining[r[@"category"]]=@([remaining[r[@"category"]] integerValue]+1);
 for(NSDictionary *root in roots){@autoreleasepool{NSDictionary *size=nil;
 if(progress&&[root[@"category"] isEqual:@"application"]){static NSDictionary *cachedBundle;static NSString *cachedPath;@synchronized(NSProcessInfo.class){if(![cachedPath isEqual:root[@"path"]]){cachedBundle=Measure(root[@"path"]);cachedPath=root[@"path"];}size=cachedBundle;}}else size=Measure(root[@"path"]);NSMutableDictionary *entry=[root mutableCopy];[entry addEntriesFromDictionary:size];entry[@"resolved"]=[root[@"path"] stringByResolvingSymlinksInPath];[entries addObject:entry];totals[root[@"category"]]=@([totals[root[@"category"]] unsignedLongLongValue]+[size[@"bytes"] unsignedLongLongValue]);
 remaining[root[@"category"]]=@([remaining[root[@"category"]] integerValue]-1);
 if(progress&&[remaining[root[@"category"]] integerValue]==0){NSMutableArray *partial=[NSMutableArray new];unsigned long long total=0;for(NSDictionary *d in Definitions()){NSMutableDictionary *g=[d mutableCopy];g[@"bytes"]=totals[g[@"id"]]?:@0;g[@"pending"]=@([remaining[g[@"id"]] integerValue]>0);total+=[g[@"bytes"] unsignedLongLongValue];[partial addObject:g];}progress(@{@"groups":partial,@"total":@(total),@"pending":@YES,@"deviceTotal":fs[NSFileSystemSize]?:@0,@"deviceFree":fs[NSFileSystemFreeSize]?:@0});}
 }}
 NSMutableArray *groups=[NSMutableArray new];unsigned long long total=0;for(NSDictionary *definition in Definitions()){NSMutableDictionary *g=[definition mutableCopy];g[@"bytes"]=totals[g[@"id"]]?:@0;total+=[g[@"bytes"] unsignedLongLongValue];[groups addObject:g];}
 return @{@"groups":groups,@"entries":entries,@"total":@(total),@"deviceTotal":fs[NSFileSystemSize]?:@0,@"deviceFree":fs[NSFileSystemFreeSize]?:@0,@"documents":documents,@"library":library,@"temporary":temporary,@"bundle":bundle?:@""};
}
NSDictionary *TMCStorageScan(NSString *documents,NSString *library,NSString *temporary,NSString *bundle){return StorageScan(documents,library,temporary,bundle,nil);}

NSDictionary *TMCStorageClean(NSDictionary *snapshot,NSSet<NSString *> *categories,NSError **error){
 NSMutableSet *allowed=[NSMutableSet new];for(NSDictionary *d in Definitions())if([d[@"clear"] boolValue])[allowed addObject:d[@"id"]];if(!categories.count||![categories isSubsetOfSet:allowed]){if(error)*error=SE(@"请选择可清理的类别");return nil;}
 // Resolve allowlisted roots again. UI-provided paths are never deletion authority.
 NSDictionary *fresh=TMCStorageScan(snapshot[@"documents"],snapshot[@"library"],snapshot[@"temporary"],snapshot[@"bundle"]);NSMutableDictionary *current=[NSMutableDictionary new];for(NSDictionary *e in fresh[@"entries"])current[e[@"path"]]=e;
 NSMutableArray *plan=[NSMutableArray new];for(NSDictionary *e in snapshot[@"entries"]){if(![categories containsObject:e[@"category"]])continue;NSDictionary *now=current[e[@"path"]];if(!now||![now[@"category"] isEqual:e[@"category"]]||![now[@"signature"] isEqual:e[@"signature"]]||![now[@"resolved"] isEqual:e[@"resolved"]]){if(error)*error=SE(@"所选文件在统计后发生变化，请刷新并重新确认清理");return nil;}[plan addObject:now];}
 unsigned long long removed=0;NSUInteger count=0;for(NSDictionary *e in plan){NSDictionary *now=Measure(e[@"path"]);if(![now[@"signature"] isEqual:e[@"signature"]]||![[e[@"path"] stringByResolvingSymlinksInPath] isEqual:e[@"resolved"]]){if(error)*error=SE(@"清理期间文件发生变化，已停止剩余操作");break;}NSError *failure=nil;if(![NSFileManager.defaultManager removeItemAtPath:e[@"path"] error:&failure]){if(error)*error=failure;break;}removed+=[e[@"bytes"] unsignedLongLongValue];count++;}
 return @{@"removed":@(removed),@"items":@(count)};
}

static NSDictionary *ItemRoot(NSDictionary *snapshot,NSString *category,NSString *path){
 BOOL allowed=NO;for(NSDictionary *d in Definitions())if([d[@"id"] isEqual:category])allowed=[d[@"clear"] boolValue];if(!allowed||!path.length||![path isEqual:path.stringByStandardizingPath])return nil;
 for(NSDictionary *root in snapshot[@"entries"]){NSString *base=root[@"path"];if(![root[@"category"] isEqual:category]||!([path isEqual:base]||[path hasPrefix:[base stringByAppendingString:@"/"]]))continue;
 if(![[base stringByResolvingSymlinksInPath] isEqual:root[@"resolved"]])return nil;
 NSString *relative=[path substringFromIndex:base.length];NSString *walk=base;struct stat st;if(lstat(base.fileSystemRepresentation,&st)||S_ISLNK(st.st_mode))return nil;
 for(NSString *part in relative.pathComponents){if([part isEqual:@"/"]||!part.length)continue;walk=Join(walk,part);if(lstat(walk.fileSystemRepresentation,&st)||S_ISLNK(st.st_mode))return nil;}return root;
 }return nil;
}
static NSDictionary *StorageItem(NSDictionary *snapshot,NSString *category,NSString *path){if(!ItemRoot(snapshot,category,path))return nil;struct stat st;if(lstat(path.fileSystemRepresentation,&st))return nil;NSMutableDictionary *item=[Measure(path) mutableCopy];item[@"path"]=path;item[@"category"]=category;item[@"directory"]=@(S_ISDIR(st.st_mode));item[@"resolved"]=path.stringByResolvingSymlinksInPath;return item;}
NSArray *TMCStorageChildren(NSDictionary *snapshot,NSString *category,NSString *directory,NSError **error){
 NSMutableArray *paths=[NSMutableArray new];if(directory){if(!ItemRoot(snapshot,category,directory)||!RealDirectory(directory)){if(error)*error=SE(@"目录已变化，请刷新统计");return nil;}for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:error])[paths addObject:Join(directory,name)];}
 else for(NSDictionary *root in snapshot[@"entries"])if([root[@"category"] isEqual:category]){NSString *path=root[@"path"];if([@[@"cache",@"exports",@"ipa",@"attachments",@"trash"] containsObject:category]&&RealDirectory(path)){for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:error])[paths addObject:Join(path,name)];}else[paths addObject:path];}
 NSMutableArray *items=[NSMutableArray new];for(NSString *path in [paths sortedArrayUsingSelector:@selector(localizedStandardCompare:)]){@autoreleasepool{NSDictionary *item=StorageItem(snapshot,category,path);if(item)[items addObject:item];}}return items;
}
NSDictionary *TMCStorageCleanItems(NSDictionary *snapshot,NSArray *items,NSError **error){
 if(!items.count){if(error)*error=SE(@"请选择文件或目录");return nil;}NSMutableArray *plan=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];
 for(NSDictionary *item in items){NSString *path=item[@"path"];if(![path isKindOfClass:NSString.class]){if(error)*error=SE(@"无效文件选择");return nil;}if([seen containsObject:path])continue;[seen addObject:path];NSDictionary *now=StorageItem(snapshot,item[@"category"],path);if(!now||![now[@"signature"] isEqual:item[@"signature"]]||![now[@"resolved"] isEqual:item[@"resolved"]]){if(error)*error=SE(@"所选文件已变化，请重新选择");return nil;}[plan addObject:item];}
 // Parent selection subsumes children; never count or delete them twice.
 NSMutableArray *minimal=[NSMutableArray new];for(NSDictionary *item in plan){BOOL covered=NO;for(NSDictionary *parent in plan)if(parent!=item&&[item[@"path"] hasPrefix:[parent[@"path"] stringByAppendingString:@"/"]]){covered=YES;break;}if(!covered)[minimal addObject:item];}
 unsigned long long bytes=0;NSUInteger count=0;for(NSDictionary *item in minimal){NSDictionary *now=StorageItem(snapshot,item[@"category"],item[@"path"]);if(!now||![now[@"signature"] isEqual:item[@"signature"]]){if(error)*error=SE(@"文件在清理期间变化，已停止剩余操作");break;}if(![NSFileManager.defaultManager removeItemAtPath:item[@"path"] error:error])break;bytes+=[item[@"bytes"] unsignedLongLongValue];count++;}if(count){NSString *sdkRoot=Join(snapshot[@"library"],@"Caches/TweakForgeSDK");NSMutableSet *markers=[NSMutableSet new];for(NSUInteger i=0;i<count;i++){NSString *path=minimal[i][@"path"];if([path hasPrefix:[sdkRoot stringByAppendingString:@"/"]]){NSString *relative=[path substringFromIndex:sdkRoot.length+1];NSString *digest=relative.pathComponents.firstObject;if(digest.length==64)[markers addObject:Join(Join(sdkRoot,digest),@".complete")];}}for(NSString *marker in markers)if(ItemRoot(snapshot,@"cache",marker))[NSFileManager.defaultManager removeItemAtPath:marker error:nil];}return @{@"removed":@(bytes),@"items":@(count)};
}

#if __has_include(<UIKit/UIKit.h>) && !defined(TMC_STORAGE_TEST)
#import "GitPreferences.h"
extern BOOL TFAIHasLiveRuns(void);
extern BOOL TFAIClassDumpIsActive(void);
static NSString *Bytes(unsigned long long size){return size?[NSByteCountFormatter stringFromByteCount:size countStyle:NSByteCountFormatterCountStyleFile]:@"0 KB";}
static UIViewController *StorageBrowser(NSDictionary *,NSString *,NSString *,NSMutableDictionary *,void(^)(void));
@interface TMCStoragePage : UIViewController <UITableViewDataSource,UITableViewDelegate>
@property UITableView *tableView;
@property NSDictionary *snapshot;
@property NSMutableSet *selected;
@property UIButton *cleanButton;
@property BOOL working;
@property NSMutableDictionary *selectedItems;
@end
@implementation TMCStoragePage
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"存储空间";NSInteger theme=[NSUserDefaults.standardUserDefaults integerForKey:@"StudioTheme"];self.overrideUserInterfaceStyle=theme==1?UIUserInterfaceStyleDark:theme==2?UIUserInterfaceStyleLight:UIUserInterfaceStyleUnspecified;
 self.selectedItems=[NSMutableDictionary new];self.selected=[NSMutableSet new];self.tableView=[[UITableView alloc]initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];self.tableView.delegate=self;self.tableView.dataSource=self;self.tableView.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.tableView];[NSLayoutConstraint activateConstraints:@[[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];self.tableView.contentInset=UIEdgeInsetsMake(0,0,84,0);self.tableView.verticalScrollIndicatorInsets=UIEdgeInsetsMake(0,0,84,0);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=68;
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(scan)];
 self.cleanButton=[UIButton buttonWithType:UIButtonTypeSystem];self.cleanButton.translatesAutoresizingMaskIntoConstraints=NO;UIButtonConfiguration *configuration=[UIButtonConfiguration filledButtonConfiguration];configuration.cornerStyle=UIButtonConfigurationCornerStyleCapsule;configuration.baseBackgroundColor=UIColor.systemRedColor;configuration.contentInsets=NSDirectionalEdgeInsetsMake(14,20,14,20);self.cleanButton.configuration=configuration;self.cleanButton.layer.shadowColor=UIColor.blackColor.CGColor;self.cleanButton.layer.shadowOpacity=.14;self.cleanButton.layer.shadowRadius=12;self.cleanButton.layer.shadowOffset=CGSizeMake(0,4);[self.cleanButton addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:self.cleanButton];[NSLayoutConstraint activateConstraints:@[[self.cleanButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],[self.cleanButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],[self.cleanButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],[self.cleanButton.heightAnchor constraintGreaterThanOrEqualToConstant:50]]];NSDictionary *cached=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"StorageDisplaySummary-v1"];if([cached[@"groups"] isKindOfClass:NSArray.class])self.snapshot=cached;
 if(!self.snapshot){NSMutableArray *groups=[NSMutableArray new];for(NSDictionary *d in Definitions()){NSMutableDictionary *g=[d mutableCopy];g[@"bytes"]=@0;g[@"pending"]=@YES;[groups addObject:g];}self.snapshot=@{@"groups":groups,@"pending":@YES};}
 [self.tableView reloadData];[self scan];
}
- (NSArray *)groups:(BOOL)clear{NSMutableArray *out=[NSMutableArray new];for(NSDictionary *g in self.snapshot[@"groups"])if([g[@"clear"] boolValue]==clear)[out addObject:g];return out;}
- (unsigned long long)selectedBytes{unsigned long long bytes=0;for(NSDictionary *g in self.snapshot[@"groups"])if([self.selected containsObject:g[@"id"]])bytes+=[g[@"bytes"] unsignedLongLongValue];for(NSDictionary *item in self.selectedItems.allValues)bytes+=[item[@"bytes"] unsignedLongLongValue];return bytes;}
- (void)updateButton{[self.cleanButton setTitle:self.working?@"正在统计…":[NSString stringWithFormat:@"清理所选 · %@",Bytes(self.selectedBytes)] forState:UIControlStateNormal];self.cleanButton.enabled=!self.working&&self.selectedBytes>0;self.navigationItem.rightBarButtonItem.enabled=!self.working;}
- (void)scan{
 if(self.working)return;self.working=YES;[self updateButton];if(!self.snapshot){UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];[spinner startAnimating];self.tableView.backgroundView=spinner;}
 NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject,*lib=NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,NSUserDomainMask,YES).firstObject;
 NSString *temporary=NSTemporaryDirectory();
#if TARGET_OS_SIMULATOR
 if([NSProcessInfo.processInfo.arguments containsObject:@"--storage-test"]){NSString *fixture=[NSTemporaryDirectory() stringByAppendingPathComponent:@"StorageUIFixture"];docs=Join(fixture,@"Documents");lib=Join(fixture,@"Library");temporary=Join(fixture,@"tmp");for(NSString *p in @[Join(docs,@"Projects/Demo/main.m"),Join(lib,@"Caches/Demo/cache"),Join(docs,@"Build-11111111-1111-1111-1111-111111111111/test.deb"),Join(docs,@".StudioTrash/Demo/main.m")]){[NSFileManager.defaultManager createDirectoryAtPath:p.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];if(![NSFileManager.defaultManager fileExistsAtPath:p])[[NSMutableData dataWithLength:65536] writeToFile:p atomically:YES];}}
#endif
 static dispatch_queue_t scanQueue;static dispatch_once_t once;dispatch_once(&once,^{scanQueue=dispatch_queue_create("com.xuegao.storage.scan",DISPATCH_QUEUE_SERIAL);});
 __weak typeof(self) weak=self;
 dispatch_async(scanQueue,^{NSDictionary *data=StorageScan(docs,lib,temporary,NSBundle.mainBundle.bundlePath,^(NSDictionary *partial){dispatch_async(dispatch_get_main_queue(),^{typeof(self) page=weak;if(!page)return;page.snapshot=partial;[page.tableView reloadData];});});dispatch_async(dispatch_get_main_queue(),^{typeof(self) self=weak;if(!self)return;NSMutableDictionary *summary=[data mutableCopy];[summary removeObjectForKey:@"entries"];for(NSString *key in @[@"documents",@"library",@"temporary",@"bundle"])[summary removeObjectForKey:key];[NSUserDefaults.standardUserDefaults setObject:summary forKey:@"StorageDisplaySummary-v1"];self.snapshot=data;self.working=NO;[self.selected removeAllObjects];[self.selectedItems removeAllObjects];self.tableView.backgroundView=nil;[self.tableView reloadData];[self updateButton];});});
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return self.snapshot?3:0;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?2:[self groups:s==1].count;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"空间概览",@"选择清理内容",@"保留内容"][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==0?@"含程序及本机数据，占用估算可能与系统统计略有差异。":s==1?@"选择需要清理的内容，重要文件请先导出。":@"源码、Git 历史、会话与认证信息保留。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i{
 UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
 if(i.section==0){unsigned long long total=[self.snapshot[@"deviceTotal"] unsignedLongLongValue],free=[self.snapshot[@"deviceFree"] unsignedLongLongValue];cell.textLabel.text=i.row==0?@"本机存储空间":@"Dylix 占用";cell.imageView.image=[UIImage systemImageNamed:i.row==0?@"internaldrive":@"app.fill"];cell.detailTextLabel.text=i.row==0?[NSString stringWithFormat:@"已用 %@ / 共 %@\n可用 %@",Bytes(total>free?total-free:0),Bytes(total),Bytes(free)]:[NSString stringWithFormat:@"%@ · 含程序与内置工具链",[self.snapshot[@"pending"] boolValue]?@"统计中":Bytes([self.snapshot[@"total"] unsignedLongLongValue])];if(!total&&i.row==0)cell.detailTextLabel.text=@"正在读取本机容量…";cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;}
 NSDictionary *g=[self groups:i.section==1][i.row];NSString *key=g[@"id"];BOOL selectable=i.section==1,checked=[self.selected containsObject:key];BOOL partial=NO;for(NSDictionary *item in self.selectedItems.allValues)if([item[@"category"] isEqual:key])partial=YES;
 UIColor *color=!selectable?UIColor.secondaryLabelColor:[key isEqual:@"trash"]?UIColor.systemRedColor:[@[@"headers",@"ipa",@"attachments"] containsObject:key]?UIColor.systemOrangeColor:[@[@"builds",@"exports"] containsObject:key]?UIColor.systemBlueColor:UIColor.systemGreenColor;
 NSString *badgeText=!selectable?@"保留":[key isEqual:@"trash"]?@"永久删除":[@[@"headers",@"ipa",@"attachments"] containsObject:key]?@"重要文件":[@[@"builds",@"exports"] containsObject:key]?@"建议保留":@"低重要性";
 NSDictionary *names=@{@"cache":@"SDK 与缓存",@"temporary":@"过期临时文件",@"builds":@"构建文件",@"exports":@"头文件 ZIP",@"headers":@"导出头文件",@"ipa":@"IPA 导入副本",@"attachments":@"AI 附件",@"backups":@"修改备份"};
 cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];cell.separatorInset=UIEdgeInsetsMake(0,selectable?82:54,0,0);
 UIImageView *icon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:g[@"symbol"]]];icon.tintColor=color;icon.contentMode=UIViewContentModeScaleAspectFit;
 UILabel *title=[UILabel new];title.text=names[key]?:g[@"name"];title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];title.adjustsFontForContentSizeCategory=YES;title.numberOfLines=1;title.lineBreakMode=NSLineBreakByTruncatingMiddle;
 UILabel *size=[UILabel new];size.text=[g[@"pending"] boolValue]?@"统计中":Bytes([g[@"bytes"] unsignedLongLongValue]);size.textColor=UIColor.secondaryLabelColor;size.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];size.adjustsFontForContentSizeCategory=YES;[size setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];[size setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

 UILabel *badge=[UILabel new];badge.text=[NSString stringWithFormat:@"  %@  ",badgeText];badge.font=[UIFont systemFontOfSize:10 weight:UIFontWeightMedium];badge.textColor=color;badge.backgroundColor=[color colorWithAlphaComponent:.13];badge.layer.cornerRadius=4;badge.clipsToBounds=YES;[badge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
 [title setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];[badge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
 UIView *spacer=[UIView new];UIStackView *heading=[[UIStackView alloc]initWithArrangedSubviews:@[title,badge,spacer]];heading.spacing=6;heading.alignment=UIStackViewAlignmentCenter;
 NSDictionary *summaries=@{@"cache":@"清理后自动生成，首次构建稍慢",@"temporary":@"仅删除超过 24 小时的临时文件",@"builds":@"删除产物和日志，项目源码保留",@"exports":@"删除导出 ZIP，分享时需重新生成",@"headers":@"删除头文件，需原 IPA 重新导出",@"ipa":@"删除本机副本，后续需重新添加",@"attachments":@"删除参考副本，聊天记录保留",@"trash":@"永久删除回收站项目，结束恢复期",@"projects":@"保留项目源码与全部 Git 历史",@"sessions":@"保留消息、图片与已发送文本",@"backups":@"保留撤回备份与操作审查记录",@"application":@"保留程序、编译器与内置资源",@"other":@"保留设置、认证及其他本机数据"};
 UILabel *summary=[UILabel new];summary.text=summaries[key]?:g[@"impact"];summary.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];summary.adjustsFontForContentSizeCategory=YES;summary.textColor=UIColor.secondaryLabelColor;summary.numberOfLines=2;summary.lineBreakMode=NSLineBreakByTruncatingTail;
 UIStackView *text=[[UIStackView alloc]initWithArrangedSubviews:@[heading,summary]];text.axis=UILayoutConstraintAxisVertical;text.spacing=5;
 UIImageView *choice=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:selectable?(checked?@"checkmark.circle.fill":partial?@"minus.circle.fill":@"circle"):@"lock.fill"]];choice.tintColor=selectable?([g[@"bytes"] unsignedLongLongValue]>0?UIColor.systemBlueColor:UIColor.tertiaryLabelColor):UIColor.tertiaryLabelColor;choice.contentMode=UIViewContentModeScaleAspectFit;
 UIButton *toggle=[UIButton buttonWithType:UIButtonTypeSystem];toggle.translatesAutoresizingMaskIntoConstraints=NO;toggle.accessibilityLabel=[g[@"name"] stringByAppendingString:@"，全选或取消"];__weak typeof(self) weak=self;[toggle addAction:[UIAction actionWithHandler:^(UIAction *a){[weak toggleCategory:key];}] forControlEvents:UIControlEventTouchUpInside];if(selectable){[cell.contentView addSubview:toggle];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
 for(UIView *view in @[icon,text,size,choice]){view.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:view];}
 [NSLayoutConstraint activateConstraints:@[[icon.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:selectable?48:16],[icon.widthAnchor constraintEqualToConstant:22],[icon.heightAnchor constraintEqualToConstant:22],[icon.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],[text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],[text.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],[text.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],[text.trailingAnchor constraintEqualToAnchor:size.leadingAnchor constant:-10],[size.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],[size.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:selectable?-8:-40],(selectable?[choice.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14]:[choice.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16]),[choice.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],[choice.widthAnchor constraintEqualToConstant:selectable?22:14],[choice.heightAnchor constraintEqualToAnchor:choice.widthAnchor],[badge.heightAnchor constraintEqualToConstant:18]]];
 if(selectable)[NSLayoutConstraint activateConstraints:@[[toggle.centerXAnchor constraintEqualToAnchor:choice.centerXAnchor],[toggle.centerYAnchor constraintEqualToAnchor:choice.centerYAnchor],[toggle.widthAnchor constraintEqualToConstant:44],[toggle.heightAnchor constraintEqualToConstant:44]]];
 cell.accessibilityLabel=[NSString stringWithFormat:@"%@，%@，%@",g[@"name"],size.text,[badgeText stringByAppendingFormat:@"，%@",summary.text]];cell.accessibilityValue=selectable?(checked?@"已选择":partial?@"部分选择":@"未选择"):@"保留";cell.selectionStyle=selectable&&[g[@"bytes"] unsignedLongLongValue]>0?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;return cell;
}
- (void)toggleCategory:(NSString *)key{if(self.working)return;BOOL had=[self.selected containsObject:key];[self.selected removeObject:key];for(NSString *path in self.selectedItems.allKeys)if([self.selectedItems[path][@"category"] isEqual:key])[self.selectedItems removeObjectForKey:path];if(!had)[self.selected addObject:key];[self.tableView reloadData];[self updateButton];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i{[t deselectRowAtIndexPath:i animated:YES];if(i.section!=1||self.working)return;NSDictionary *g=[self groups:YES][i.row];NSString *key=g[@"id"];if([self.selected containsObject:key]){[self.selected removeObject:key];for(NSDictionary *root in self.snapshot[@"entries"])if([root[@"category"] isEqual:key])self.selectedItems[root[@"path"]]=root;}
 __weak typeof(self) weak=self;[self.navigationController pushViewController:StorageBrowser(self.snapshot,key,nil,self.selectedItems,^{[weak.tableView reloadData];[weak updateButton];}) animated:YES];}

- (void)message:(NSString *)title text:(NSString *)text{UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil];}
- (void)confirm{
 if(self.working||!self.selectedBytes)return;
 NSMutableArray *lines=[NSMutableArray new];for(NSDictionary *item in self.selectedItems.allValues)[lines addObject:[NSString stringWithFormat:@"%@ · %@",[item[@"path"] lastPathComponent],Bytes([item[@"bytes"] unsignedLongLongValue])]];for(NSDictionary *g in [self groups:YES])if([self.selected containsObject:g[@"id"]]||[self.selectedItems.allValues filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item,NSDictionary *bindings){return [item[@"category"] isEqual:g[@"id"]];}]].count)[lines addObject:[NSString stringWithFormat:@"%@（%@）\n%@",g[@"name"],Bytes([g[@"bytes"] unsignedLongLongValue]),g[@"impact"]]];
 UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"清理约 %@？",Bytes(self.selectedBytes)] message:[[lines componentsJoinedByString:@"\n\n"] stringByAppendingString:@"\n\n这些内容将直接删除，请确认已保存需要的文件。"] preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"确认清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){[self clean];}]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)clean{
 if(TFAIHasLiveRuns()||TFAIClassDumpIsActive()||[TMCGitLease hasActiveBuilds]){[self message:@"有任务正在处理" text:@"请等待构建、头文件导出或 AI 任务完成后再清理。"];return;}
 self.working=YES;[self updateButton];self.navigationItem.hidesBackButton=YES;self.navigationController.interactivePopGestureRecognizer.enabled=NO;UIWindow *window=self.view.window;window.userInteractionEnabled=NO;UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];[spinner startAnimating];self.navigationItem.titleView=spinner;NSDictionary *snapshot=self.snapshot;NSSet *selected=[self.selected copy];NSMutableArray *items=[self.selectedItems.allValues mutableCopy];for(NSDictionary *root in snapshot[@"entries"])if([selected containsObject:root[@"category"]])[items addObject:root];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool{
 TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];NSError *error=nil;NSDictionary *result=nil;if(!lease||TFAIHasLiveRuns()||TFAIClassDumpIsActive()||[TMCGitLease hasActiveBuilds])error=SE(@"Git、构建或 AI 任务正在处理，请稍后再试。");else result=TMCStorageCleanItems(snapshot,items,&error);
 dispatch_async(dispatch_get_main_queue(),^{window.userInteractionEnabled=YES;self.navigationItem.titleView=nil;self.navigationItem.hidesBackButton=NO;self.navigationController.interactivePopGestureRecognizer.enabled=YES;self.working=NO;[self scan];[self message:error?@"清理未全部完成":@"清理完成" text:[NSString stringWithFormat:@"已释放约 %@\n%@",Bytes([result[@"removed"] unsignedLongLongValue]),error.localizedDescription?:@"保留内容未作更改。"]];});}});
}
@end

@interface TMCStorageBrowser : UITableViewController
@property NSDictionary *snapshot;
@property NSString *category;
@property NSString *directory;
@property NSArray *items;
@property NSMutableDictionary *selection;
@property(copy) void(^changed)(void);
@end
@implementation TMCStorageBrowser
- (void)viewDidLoad{[super viewDidLoad];self.title=self.directory.lastPathComponent?:@"选择文件与目录";self.tableView.rowHeight=62;self.tableView.estimatedRowHeight=62;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"全选" style:UIBarButtonItemStylePlain target:self action:@selector(selectAll)];[self loadItems];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.tableView reloadData];}
- (void)loadItems{UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];[spinner startAnimating];self.tableView.backgroundView=spinner;self.navigationItem.rightBarButtonItem.enabled=NO;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError *error=nil;NSArray *items=TMCStorageChildren(self.snapshot,self.category,self.directory,&error);dispatch_async(dispatch_get_main_queue(),^{self.items=items?:@[];UILabel *empty=[UILabel new];empty.text=error.localizedDescription?:@"没有可清理文件";empty.textAlignment=NSTextAlignmentCenter;empty.textColor=UIColor.secondaryLabelColor;empty.numberOfLines=0;self.tableView.backgroundView=self.items.count?nil:empty;self.navigationItem.rightBarButtonItem.enabled=self.items.count>0;[self.tableView reloadData];});});}
- (BOOL)chosen:(NSString *)path{for(NSString *selected in self.selection)if([path isEqual:selected]||[path hasPrefix:[selected stringByAppendingString:@"/"]])return YES;return NO;}
- (void)toggleSelection:(NSDictionary *)item{NSString *path=item[@"path"];if([self chosen:path]){ // Split selected ancestors into siblings before removing this child.
 for(NSString *selected in self.selection.allKeys)if([path isEqual:selected]||[path hasPrefix:[selected stringByAppendingString:@"/"]]){NSDictionary *parent=self.selection[selected];[self.selection removeObjectForKey:selected];if(![path isEqual:selected]){NSString *cursor=selected;while(![cursor isEqual:path]){NSArray *children=TMCStorageChildren(self.snapshot,self.category,cursor,nil);NSString *next=nil;for(NSDictionary *child in children){NSString *childPath=child[@"path"];if([path isEqual:childPath]||[path hasPrefix:[childPath stringByAppendingString:@"/"]])next=childPath;else self.selection[childPath]=child;}if(!next)break;cursor=next;}}(void)parent;}
 }else{for(NSString *selected in self.selection.allKeys)if([selected hasPrefix:[path stringByAppendingString:@"/"]])[self.selection removeObjectForKey:selected];self.selection[path]=item;}}
- (void)performSelection:(void(^)(void))operation{UIWindow *window=self.view.window;window.userInteractionEnabled=NO;UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];[spinner startAnimating];self.navigationItem.titleView=spinner;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{operation();dispatch_async(dispatch_get_main_queue(),^{window.userInteractionEnabled=YES;self.navigationItem.titleView=nil;[self.tableView reloadData];if(self.changed)self.changed();});});}
- (void)toggle:(NSDictionary *)item{[self performSelection:^{[self toggleSelection:item];}];}
- (void)selectAll{[self performSelection:^{BOOL all=YES;for(NSDictionary *item in self.items)if(![self chosen:item[@"path"]])all=NO;for(NSDictionary *item in self.items){BOOL chosen=[self chosen:item[@"path"]];if(all?chosen:!chosen)[self toggleSelection:item];}}];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section{return self.items.count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i{NSDictionary *item=self.items[i.row];NSString *path=item[@"path"];UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=[NSString stringWithFormat:@"%@ · %@",path.lastPathComponent,Bytes([item[@"bytes"] unsignedLongLongValue])];cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];cell.textLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;NSString *relative=path;for(NSString *root in @[self.snapshot[@"documents"],self.snapshot[@"library"],self.snapshot[@"temporary"]])if([path hasPrefix:[root stringByAppendingString:@"/"]]){relative=[NSString stringWithFormat:@"%@/%@",root.lastPathComponent,[path substringFromIndex:root.length+1]];break;}cell.detailTextLabel.text=relative;cell.detailTextLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;UIButton *check=[UIButton buttonWithType:UIButtonTypeSystem];[check setImage:[UIImage systemImageNamed:[self chosen:path]?@"checkmark.circle.fill":@"circle"] forState:UIControlStateNormal];check.frame=CGRectMake(0,0,44,44);check.accessibilityLabel=[path.lastPathComponent stringByAppendingString:@"，选择或取消"];[check addAction:[UIAction actionWithHandler:^(UIAction *action){[self toggle:item];}] forControlEvents:UIControlEventTouchUpInside];check.accessibilityValue=[self chosen:path]?@"已选择":@"未选择";cell.accessoryView=check;cell.imageView.image=[UIImage systemImageNamed:[item[@"directory"] boolValue]?@"folder":@"doc"];return cell;}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i{[t deselectRowAtIndexPath:i animated:YES];NSDictionary *item=self.items[i.row];if([item[@"directory"] boolValue])[self.navigationController pushViewController:StorageBrowser(self.snapshot,self.category,item[@"path"],self.selection,self.changed) animated:YES];else[self toggle:item];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)section{return @"点击目录查看内部文件，点击右侧圆圈选择整项。返回存储空间页后确认清理。";}
@end
static UIViewController *StorageBrowser(NSDictionary *snapshot,NSString *category,NSString *directory,NSMutableDictionary *selection,void(^changed)(void)){TMCStorageBrowser *page=[[TMCStorageBrowser alloc]initWithStyle:UITableViewStyleInsetGrouped];page.snapshot=snapshot;page.category=category;page.directory=directory;page.selection=selection;page.changed=changed;return page;}
UIViewController *TMCStorageController(void){return [TMCStoragePage new];}
#endif
