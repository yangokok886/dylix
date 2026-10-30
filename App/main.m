#import "StorageSpace.h"
#import "AI/Background/TFAIBackground.h"
#import "AI/Background/TFAINotifications.h"
#import "RuntimeDiagnostics.h"
#import "GlassSupport.h"
#import <UIKit/UIKit.h>
#import <ios_system/ios_system.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <pthread.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "DebPackage.h"
#import "OutputNaming.h"
#import "ArchiveImport.h"
#import "SDKResources.h"
#import "Incoming/TFIncoming.h"
#import "GitAutomation.h"
#import "LinkSupport.h"
#import "../Vendor/MBProgressHUD/MBProgressHUD.h"

static void TMCLog(FILE *stream, const char *format, ...) {
 if(!stream)return;va_list args;va_start(args,format);char *buffer=NULL;int count=vasprintf(&buffer,format,args);va_end(args);NSString *message=count>=0?[[NSString alloc] initWithBytes:buffer length:(NSUInteger)count encoding:NSUTF8StringEncoding]:nil;free(buffer);if(!message)message=@"日志编码错误";
 NSDateFormatter *formatter=[NSDateFormatter new];formatter.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];formatter.dateFormat=@"HH:mm:ss.SSS";NSString *stamp=[formatter stringFromDate:NSDate.date];[message enumerateSubstringsInRange:NSMakeRange(0,message.length) options:NSStringEnumerationByLines usingBlock:^(NSString *line,NSRange range,NSRange enclosing,BOOL *stop){fprintf(stream,"[%s] %s\n",stamp.UTF8String,line.UTF8String);}];fflush(stream);
}

// LLVM 14 ArrayRef<const char *> is a trivial pointer + size aggregate on both
// supported ABIs. Call the exported cc1 entry directly to keep driver InitLLVM
// teardown from invalidating LLVM's process-wide pass registry between sources.
typedef struct { const char *const *data; size_t size; } TMCLLVM14Argv;
typedef struct {
    int (*entry)(int, char **);
    int (*cc1)(TMCLLVM14Argv, const char *, void *);
    bool (*macho)(TMCLLVM14Argv, bool, void *, void *);
    void *llvmOut;
    void *llvmErr;
    int argc;
    char **argv;
    FILE *input;
    FILE *log;
    FILE *errors;
    int status;
} ToolInvocation;
static void finishTool(void *opaque) {
    ToolInvocation *call = opaque;
    if (call->status == -999) call->status = ios_getCommandStatus();
    fflush(call->log);
}
static void *invokeTool(void *opaque) {
    ToolInvocation *call = opaque;
    @autoreleasepool {
        ios_switchSession(call);
        ios_setStreams(call->input, call->log, call->errors);
        thread_stdin = call->input; thread_stdout = call->log; thread_stderr = call->errors;
        ios_setenv("SYSROOT", NSBundle.mainBundle.bundlePath.fileSystemRepresentation, 1);
        ios_setenv("APPDIR", NSBundle.mainBundle.bundlePath.fileSystemRepresentation, 1);
        ios_setenv("PERL5LIB", [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Perl"].fileSystemRepresentation, 1);
        pthread_cleanup_push(finishTool, call);
        if (call->cc1) {
            void (*resetOptions)(void) = dlsym(RTLD_DEFAULT, "_ZN4llvm2cl25ResetAllOptionOccurrencesEv");
            void (*removeHandler)(void) = dlsym(RTLD_DEFAULT, "_ZN4llvm26remove_fatal_error_handlerEv");
            if (resetOptions) resetOptions();
            TMCLLVM14Argv arguments = {(const char *const *)(call->argv + 1), (size_t)call->argc - 1};
            call->status = call->cc1(arguments, call->argv[0], (void *)call->cc1);
            if (removeHandler) removeHandler();
        } else if (call->macho) {
            TMCLLVM14Argv arguments = {(const char *const *)call->argv, (size_t)call->argc};
            call->status = call->macho(arguments, false, call->llvmOut, call->llvmErr) ? 0 : 1;
        } else call->status = call->entry(call->argc, call->argv);
        pthread_cleanup_pop(1);
        fflush(call->log);
    }
    return NULL;
}
static BOOL TMCBuildRunning = NO;

static int runToolOutput(NSArray<NSString *> *arguments, FILE *input, FILE *log, FILE *errors) {
#if TARGET_OS_SIMULATOR
    // Test the real per-source output/mapping pipeline with host-generated Logos
    // fixtures. This branch is absent from device IPAs, which use embedded Perl.
    if([arguments.firstObject isEqual:@"perl"]&&[NSProcessInfo.processInfo.arguments containsObject:@"--test-logos-preprocessed"]){
        NSData *fixture=[NSData dataWithContentsOfFile:[arguments.lastObject stringByAppendingString:@".preprocessed"]];
        fprintf(errors,"SIMULATOR TEST: Logos text preprocessed by macOS Perl\n");
        return fixture&&fwrite(fixture.bytes,1,fixture.length,log)==fixture.length?0:74;
    }
#endif
    NSString *name = [arguments.firstObject isEqualToString:@"clang"] ? @"clang" : ([arguments.firstObject isEqualToString:@"perl"] ? @"perl" : @"lld");
    NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.framework/%@", name, name]];
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) { TMCLog(log, "%s\n", dlerror()); return 127; }
    ToolInvocation call = {.entry = dlsym(handle, "main"), .argc = (int)arguments.count, .input = input, .log = log, .errors = errors, .status = -999};
    if ([name isEqualToString:@"clang"]) {
        call.cc1 = dlsym(handle, "_Z8cc1_mainN4llvm8ArrayRefIPKcEES2_Pv");
        if (!call.cc1) { fprintf(errors, "Missing LLVM 14 cc1 entry: %s\n", dlerror()); return 127; }
        fprintf(errors, "clang entry: cc1_main (preserve LLVM global state)\n");
    }
    if ([name isEqualToString:@"lld"]) {
        call.macho = dlsym(handle, "_ZN3lld5macho4linkEN4llvm8ArrayRefIPKcEEbRNS1_11raw_ostreamES7_");
        void *(*outs)(void) = dlsym(RTLD_DEFAULT, "_ZN4llvm4outsEv");
        void *(*errs)(void) = dlsym(RTLD_DEFAULT, "_ZN4llvm4errsEv");
        if (!call.macho || !outs || !errs) { fprintf(errors, "Missing reusable Mach-O linker entry\n"); return 127; }
        call.llvmOut = outs(); call.llvmErr = errs();
        fprintf(errors, "lld entry: macho::link (canExitEarly=false)\n");
    }
    if (!call.entry) { fprintf(errors, "Missing compiler entry: %s\n", dlerror()); return 127; }
    call.argv = calloc(arguments.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < arguments.count; i++) call.argv[i] = strdup(arguments[i].UTF8String);
    pthread_t worker;
    int creation = pthread_create(&worker, NULL, invokeTool, &call);
    if (creation == 0) pthread_join(worker, NULL);
    else call.status = creation;
    for (NSUInteger i = 0; i < arguments.count; i++) free(call.argv[i]);
    free(call.argv);
    return call.status;
}
static int runTool(NSArray<NSString *> *arguments, FILE *input, FILE *log) {
    return runToolOutput(arguments, input, log, log);
}

static NSString *projectPath(NSString *root, NSString *relative) {
    if (![relative isKindOfClass:NSString.class] || relative.isAbsolutePath) return nil;
    NSString *base = root.stringByStandardizingPath;
    NSString *path = [root stringByAppendingPathComponent:relative].stringByStandardizingPath;
    return [path hasPrefix:[base stringByAppendingString:@"/"]] ? path : nil;
}
static NSDictionary *projectConfig(NSString *root) {
    NSData *data = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"MobileCompiler.json"]];
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static NSArray<NSString *> *sourcePaths(NSString *root) {
    NSDictionary *config = projectConfig(root);
    NSMutableArray *paths = [NSMutableArray array];
    NSArray *names = [config[@"sources"] isKindOfClass:NSArray.class] ? config[@"sources"] : [[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        NSString *path = projectPath(root, name);
        if (!path || ![@[@"x", @"xm", @"m", @"mm", @"c", @"cpp"] containsObject:path.pathExtension.lowercaseString]) continue;
        BOOL directory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] && !directory) [paths addObject:path];
    }
    return paths;
}
#import "CompilerController.h"
#import "Studio.h"
#import "GitUI.h"

// App-owned Documents needs no File Provider hand-off. Browse it directly.
@interface TMCLocalFolders : UITableViewController
@property NSString *directory;
@property NSString *boundary;
@property NSArray<NSDictionary *> *entries;
@property(copy) void (^selected)(NSString *);
@end
@implementation TMCLocalFolders
- (void)viewDidLoad{
 [super viewDidLoad];self.title=[self.directory isEqual:self.boundary]?@"Dylix 本机目录":self.directory.lastPathComponent;
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"打开" style:UIBarButtonItemStyleDone target:self action:@selector(choose)];self.navigationItem.rightBarButtonItem.accessibilityLabel=@"打开当前工程文件夹";
 self.navigationItem.rightBarButtonItem.enabled=![self.directory isEqual:self.boundary];
 if([self.directory isEqual:self.boundary])self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
 NSMutableArray *items=[NSMutableArray new];NSError *error=nil;
 NSArray *urls=[NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:self.directory] includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
 for(NSURL *url in urls){NSDictionary *v=[url resourceValuesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey] error:nil];NSString *name=url.lastPathComponent;if([v[NSURLIsSymbolicLinkKey] boolValue]||[name hasPrefix:@"Build-"]||[name hasPrefix:@"Snapshot-"])continue;[items addObject:@{@"name":name,@"directory":v[NSURLIsDirectoryKey]?:@NO}];}
 [items sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){if([a[@"directory"] boolValue]!=[b[@"directory"] boolValue])return [a[@"directory"] boolValue]?NSOrderedAscending:NSOrderedDescending;return [a[@"name"] localizedStandardCompare:b[@"name"]];}];self.entries=items;
 if(error||!items.count){UILabel *empty=[UILabel new];empty.text=error.localizedDescription?:@"此文件夹为空。请先在“文件”App 中复制工程到 Dylix。";empty.numberOfLines=0;empty.textAlignment=NSTextAlignmentCenter;empty.textColor=UIColor.secondaryLabelColor;self.tableView.backgroundView=empty;}
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @"进入工程文件夹，再点右上角“打开” · 本机直接读取";}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.entries.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index{NSDictionary *item=self.entries[index.row];BOOL directory=[item[@"directory"] boolValue];UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=item[@"name"];cell.textLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;cell.imageView.image=[UIImage systemImageNamed:directory?@"folder":@"doc.text"];cell.imageView.tintColor=directory?UIColor.systemOrangeColor:UIColor.secondaryLabelColor;cell.accessoryType=directory?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;cell.selectionStyle=directory?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;cell.detailTextLabel.text=directory?@"点击进入":@"工程文件";return cell;}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index{[tableView deselectRowAtIndexPath:index animated:YES];NSDictionary *item=self.entries[index.row];if(![item[@"directory"] boolValue])return;TMCLocalFolders *next=[TMCLocalFolders new];next.directory=[self.directory stringByAppendingPathComponent:item[@"name"]];next.boundary=self.boundary;next.selected=self.selected;[self.navigationController pushViewController:next animated:YES];}
- (void)choose{if([self.directory isEqual:self.boundary])return;if(self.selected)self.selected(self.directory);}
- (void)cancel{[self dismissViewControllerAnimated:YES completion:nil];}
@end

@interface TMCArchiveProjectList : UITableViewController
@property NSArray<NSDictionary *> *projects;
@property(copy) void (^selected)(NSDictionary *);
@property(copy) void (^cancelled)(void);
@property BOOL completed;
@end
@implementation TMCArchiveProjectList
- (void)viewDidLoad {
    [super viewDidLoad];self.title=[NSString stringWithFormat:@"选择工程（%lu）",(unsigned long)self.projects.count];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @"压缩包中发现多个工程，选择一个导入";}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.projects.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    NSDictionary *project=self.projects[index.row];UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=project[@"name"];cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@ 个源码",project[@"relative"],project[@"sources"]];cell.detailTextLabel.numberOfLines=2;
    cell.imageView.image=[UIImage systemImageNamed:@"folder"];cell.imageView.tintColor=UIColor.systemOrangeColor;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES];if(self.completed)return;self.completed=YES;
    NSDictionary *project=self.projects[index.row];[self dismissViewControllerAnimated:YES completion:^{if(self.selected)self.selected(project);}];
}
- (void)cancel {if(self.completed)return;self.completed=YES;[self dismissViewControllerAnimated:YES completion:^{if(self.cancelled)self.cancelled();}];}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];if(!self.completed&&(!self.navigationController.presentingViewController||self.navigationController.isBeingDismissed)){self.completed=YES;if(self.cancelled)self.cancelled();}}
@end

@implementation CompilerController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"本地编译验证";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.console = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.console.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.console.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.console.editable = NO;
    TMCEnableTextLinks(self.console);
    [self.view addSubview:self.console];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"运行" style:UIBarButtonItemStylePlain target:self action:@selector(runProof)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入源码" style:UIBarButtonItemStylePlain target:self action:@selector(importSource)];
    self.toolbarItems = @[[[UIBarButtonItem alloc] initWithTitle:@"导出结果" style:UIBarButtonItemStylePlain target:self action:@selector(exportResult)]];
    self.navigationController.toolbarHidden = NO;
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *previous = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:documents error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSDate *latest = NSDate.distantPast;
    for (NSString *name in previous) {
        if (![name hasPrefix:@"Build-"]) continue;
        NSString *path = [documents stringByAppendingPathComponent:name];
        NSDate *date = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileModificationDate];
        if (date && [date compare:latest] == NSOrderedDescending) { latest = date; self.lastBuild = path; }
    }
    self.console.text = @"Dylix · 技术验证版\n\n导入多源码工程文件夹，或点击运行构建内置 Objective-C 样本。\n\n目标：arm64 · iOS 15+ · Rootless .deb\n所有构建步骤在 App 进程内执行。";
    NSString *savedSource = [NSUserDefaults.standardUserDefaults stringForKey:@"ImportedSourceRelativePath"];
    if (savedSource) {
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *restored = [documents stringByAppendingPathComponent:savedSource];
        if ([NSFileManager.defaultManager fileExistsAtPath:restored]) {
            self.importedSource = restored;
            self.console.text = [self.console.text stringByAppendingFormat:@"\n\n已恢复导入源码：%@", restored.lastPathComponent];
        }
    }
    NSString *savedProject = [NSUserDefaults.standardUserDefaults stringForKey:@"ImportedProject"];
    if (savedProject) {
        NSString *path = [documents stringByAppendingPathComponent:savedProject];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) self.importedProject = path;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--repeat-builds"]) {
        __weak typeof(self) weakSelf = self;
        __block NSMutableArray *runs = [NSMutableArray new];
        __block NSString *baseline = nil;
        self.buildCompletion = ^(BOOL success) {
            CompilerController *controller = weakSelf;
            if (!baseline) baseline = controller.importedProject;
            [runs addObject:@{@"success":@(success), @"build":controller.lastBuild ?: @""}];
            [[NSJSONSerialization dataWithJSONObject:runs options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[documents stringByAppendingPathComponent:@"repeat-builds.json"] atomically:YES];
            BOOL expected = runs.count != 2 && runs.count != 4;
            if (success != expected || runs.count >= 10) return;
            if (runs.count == 1 || runs.count == 3) {
                NSString *fixture = [documents stringByAppendingPathComponent:@"RepeatFailureFixture"];
                [NSFileManager.defaultManager createDirectoryAtPath:fixture withIntermediateDirectories:YES attributes:nil error:nil];
                NSString *code = runs.count == 1 ? @"invalid syntax here !!!" : @"int repeat_fixture(void) { return 1; }";
                [code writeToFile:[fixture stringByAppendingPathComponent:@"Fixture.c"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
                NSDictionary *config = @{@"name":@"RepeatFailure", @"sources":@[@"Fixture.c"], @"package":@NO, @"frameworks":runs.count == 3 ? @[@"MissingFixtureFramework"] : @[]};
                [[NSJSONSerialization dataWithJSONObject:config options:0 error:nil] writeToFile:[fixture stringByAppendingPathComponent:@"MobileCompiler.json"] atomically:YES];
                controller.importedProject = fixture;
            } else controller.importedProject = baseline;
            [controller runProof];
        };
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test"]) [self runProof];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test-project"]) {
#if TARGET_OS_SIMULATOR
        NSArray *testArguments = NSProcessInfo.processInfo.arguments;
        NSUInteger testPathIndex = [testArguments indexOfObject:@"--test-project-path"];
        if (testPathIndex != NSNotFound && testPathIndex + 1 < testArguments.count) {
            [self importURLs:@[[NSURL fileURLWithPath:testArguments[testPathIndex + 1] isDirectory:YES]]];
            return;
        }
#endif
        NSString *fixture = [NSProcessInfo.processInfo.arguments containsObject:@"--flex"] ? @"FLEXProject" : [NSProcessInfo.processInfo.arguments containsObject:@"--multi"] ? @"SampleMultiObjectiveC" : ([NSProcessInfo.processInfo.arguments containsObject:@"--generated-logos"] ? @"SampleLogosGenerated" : @"SampleObjectiveC");
        [self importURLs:@[[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:fixture]]];
    }

}
- (void)showImportMessage:(NSString *)message {
#if TARGET_OS_SIMULATOR
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--test-project-path"]) {
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [[NSJSONSerialization dataWithJSONObject:@{@"message":message ?: @"", @"imported":@([message hasPrefix:@"已导入"])} options:0 error:nil] writeToFile:[documents stringByAppendingPathComponent:@"TestImportResult.json"] atomically:YES];
    }
#endif
    self.console.text = message;
    if (self.importCompletion && [message hasPrefix:@"已导入"]) return;
    UIViewController *host=[self importHost];
    id<UIViewControllerTransitionCoordinator> transition=host.presentedViewController.transitionCoordinator?:host.transitionCoordinator;
    if(transition&&[transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){dispatch_async(dispatch_get_main_queue(),^{[self showImportMessage:message];});}])return;
    if(host.presentedViewController){[host dismissViewControllerAnimated:YES completion:^{[self showImportMessage:message];}];return;}
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入结果" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [[self importHost] presentViewController:alert animated:YES completion:nil];
}
- (UIViewController *)importHost { return self.presentationHost ?: self; }
- (void)openFilePicker {
    if(self.activePicker)return;
    self.pickingArchive=NO;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.allowsMultipleSelection=YES;
    picker.shouldShowFileExtensions=YES;
    picker.delegate=self;
    picker.title=@"选择源码及配置文件";
    self.activePicker=picker;
    dispatch_async(dispatch_get_main_queue(), ^{[self presentPendingPicker];});
}
- (void)openArchivePicker {
    if(self.activePicker||self.importInProgress)return;
    self.pickingArchive=YES;
    // A generic type also exposes providers' unregistered .7z/.rar types.
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.allowsMultipleSelection=NO;picker.shouldShowFileExtensions=YES;picker.delegate=self;
    picker.title=@"选择压缩包 · ZIP / 7z / RAR / TAR";self.activePicker=picker;
    dispatch_async(dispatch_get_main_queue(),^{[self presentPendingPicker];});
}
- (void)presentPendingPicker {
    UIViewController *host=[self importHost];
    UIDocumentPickerViewController *picker=self.activePicker;
    if(!picker||picker.presentingViewController)return;
    id<UIViewControllerTransitionCoordinator> transition=host.presentedViewController.transitionCoordinator?:host.transitionCoordinator;
    if(transition&&[transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){dispatch_async(dispatch_get_main_queue(),^{[self presentPendingPicker];});}])return;
    if(host.presentedViewController)return;
    [host presentViewController:picker animated:YES completion:^{picker.presentationController.delegate=self;}];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { self.activePicker=nil; }
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if(presentationController.presentedViewController==self.activePicker)self.activePicker=nil;
}
- (void)loadDocumentsProject {
    UIViewController *host=[self importHost];
    id<UIViewControllerTransitionCoordinator> transition=host.presentedViewController.transitionCoordinator?:host.transitionCoordinator;
    if(transition&&[transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){dispatch_async(dispatch_get_main_queue(),^{[self loadDocumentsProject];});}])return;
    if(host.presentedViewController)return;
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    TMCLocalFolders *folders=[TMCLocalFolders new];folders.directory=documents;folders.boundary=documents;
    __weak typeof(self) weakSelf=self;
    folders.selected=^(NSString *path){typeof(self) owner=weakSelf;if(!owner)return;[[owner importHost] dismissViewControllerAnimated:YES completion:^{[owner importURLs:@[[NSURL fileURLWithPath:path isDirectory:YES]]];}];};
    UINavigationController *nav=[[TMCNavigationController alloc] initWithRootViewController:folders];
    [host presentViewController:nav animated:YES completion:nil];
}
- (void)importSource {
    UIViewController *host=[self importHost];
    if(host.presentedViewController)return;
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"打开项目" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"从 ZIP / 压缩包导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self openArchivePicker];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"选择源码及配置文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self openFilePicker];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"从 App 内工程目录载入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){dispatch_async(dispatch_get_main_queue(),^{[self loadDocumentsProject];});}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView=host.view;
    menu.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(host.view.bounds),CGRectGetMidY(host.view.bounds),1,1);
    [host presentViewController:menu animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if(controller!=self.activePicker)return;
    self.activePicker=nil;
    if(self.pickingArchive){self.pickingArchive=NO;if(urls.count)[self importArchiveURL:urls.firstObject];return;}
    // Acquire security scopes immediately; provider work stays on the worker queue.
    [self importURLs:urls];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self documentPicker:controller didPickDocumentsAtURLs:url?@[url]:@[]];
}
- (void)afterImportPresentation:(void (^)(void))completion {
    UIViewController *host=[self importHost];
    id<UIViewControllerTransitionCoordinator> transition=host.presentedViewController.transitionCoordinator?:host.transitionCoordinator;
    if(transition&&[transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){dispatch_async(dispatch_get_main_queue(),^{[self afterImportPresentation:completion];});}])return;
    if(host.presentedViewController){[host dismissViewControllerAnimated:YES completion:^{[self afterImportPresentation:completion];}];return;}
    completion();
}
- (void)cancelArchive {[self.archiveProgress cancel];self.archiveHUD.button.enabled=NO;}
- (void)showArchiveHUD {
    if(self.archiveHUD)return;
    UIView *view=[self importHost].navigationController.view?:[self importHost].view;
    MBProgressHUD *hud=[MBProgressHUD showHUDAddedTo:view animated:YES];self.archiveHUD=hud;
    hud.removeFromSuperViewOnHide=YES;hud.label.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];hud.label.text=@"正在读取压缩包…";
    [hud.button setTitle:@"取消" forState:UIControlStateNormal];[hud.button addTarget:self action:@selector(cancelArchive) forControlEvents:UIControlEventTouchUpInside];
}
- (void)hideArchiveHUD {[self.archiveHUD hideAnimated:YES];self.archiveHUD=nil;}
- (void)cleanupArchive {
    [self hideArchiveHUD];
    if(self.archiveWorkRoot)[NSFileManager.defaultManager removeItemAtPath:self.archiveWorkRoot error:nil];
    self.archiveWorkRoot=nil;self.archiveInputPath=nil;self.archiveProjectName=nil;self.archiveProgress=nil;
}
- (void)importArchiveURL:(NSURL *)url {
    if(self.importInProgress)return;self.importInProgress=YES;
    BOOL scoped=[url startAccessingSecurityScopedResource];
    self.archiveProgress=[NSProgress progressWithTotalUnitCount:1];
    [self afterImportPresentation:^{
      [self showArchiveHUD];
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSFileManager *fm=NSFileManager.defaultManager;
        NSString *work=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"ArchiveImport-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *input=[[work stringByAppendingPathComponent:@"Source"] stringByAppendingPathComponent:url.lastPathComponent.length?url.lastPathComponent:@"Project.archive"];
        NSError *error=nil;__block NSError *copyError=nil;
        if([fm createDirectoryAtPath:input.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]){
            NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:&error byAccessor:^(NSURL *readURL){[fm copyItemAtURL:readURL toURL:[NSURL fileURLWithPath:input] error:&copyError];}];
        }
        if(scoped)[url stopAccessingSecurityScopedResource];error=error?:copyError;
        dispatch_async(dispatch_get_main_queue(),^{
            self.archiveWorkRoot=work;self.archiveInputPath=input;
            if(error||self.archiveProgress.cancelled){self.importInProgress=NO;[self cleanupArchive];if(error)[self showImportMessage:error.localizedDescription];return;}
            [self expandArchiveWithPassword:nil];
        });
      });
    }];
}
- (void)expandArchiveWithPassword:(NSString *)password {
    self.archiveProgress=[NSProgress progressWithTotalUnitCount:1];
    [self showArchiveHUD];self.archiveHUD.button.enabled=YES;
    NSString *expanded=[self.archiveWorkRoot stringByAppendingPathComponent:@"Expanded"];
    NSString *input=self.archiveInputPath;NSProgress *progress=self.archiveProgress;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        [NSFileManager.defaultManager removeItemAtPath:expanded error:nil];
        NSError *error=nil;__block NSTimeInterval updated=0;
        BOOL ok=TMCExtractArchive([NSURL fileURLWithPath:input],[NSURL fileURLWithPath:expanded],password,progress,^(NSUInteger files,unsigned long long bytes){
            NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(now-updated<.15)return;updated=now;
            dispatch_async(dispatch_get_main_queue(),^{if(self.archiveProgress==progress)self.archiveHUD.label.text=[NSString stringWithFormat:@"%lu 个条目 · %@",(unsigned long)files,[NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile]];});
        },&error);
        NSArray *projects=ok?TMCArchiveProjects(expanded,progress,&error):nil;
        dispatch_async(dispatch_get_main_queue(),^{
            if(progress.cancelled){self.importInProgress=NO;[self cleanupArchive];return;}
            if(!projects){
                [self hideArchiveHUD];
                if([error.domain isEqual:@"TweakForgeArchive"]&&error.code==TMCArchivePassword){[self requestArchivePassword:password.length>0];return;}
                self.importInProgress=NO;[self cleanupArchive];[self showImportMessage:error.localizedDescription?:@"压缩包识别失败"];return;
            }
            if(projects.count==1){[self importArchiveProject:projects.firstObject];return;}
            [self hideArchiveHUD];
            TMCArchiveProjectList *list=[[TMCArchiveProjectList alloc] initWithStyle:UITableViewStyleInsetGrouped];list.projects=projects;
            __weak typeof(self) weakSelf=self;
            list.selected=^(NSDictionary *project){[weakSelf importArchiveProject:project];};
            list.cancelled=^{weakSelf.importInProgress=NO;[weakSelf cleanupArchive];};
            [[self importHost] presentViewController:[[TMCNavigationController alloc] initWithRootViewController:list] animated:YES completion:nil];
        });
    });
}
- (void)requestArchivePassword:(BOOL)retry {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:retry?@"请检查压缩包密码":@"压缩包需要密码" message:@"支持的加密格式将在本机使用此密码解压；密码不会保存。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.secureTextEntry=YES;field.placeholder=@"压缩包密码";}];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){self.importInProgress=NO;[self cleanupArchive];}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"解压" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){NSString *password=alert.textFields.firstObject.text?:@"";[self afterImportPresentation:^{[self expandArchiveWithPassword:password];}];}]];
    [[self importHost] presentViewController:alert animated:YES completion:nil];
}
- (void)importArchiveProject:(NSDictionary *)project {
    NSString *name=project[@"name"];
    if([project[@"relative"] isEqual:@"压缩包根目录"]){name=self.archiveInputPath.lastPathComponent.stringByDeletingPathExtension;for(NSString *suffix in @[@"tar",@"tgz",@"tbz2",@"txz"])if([name.pathExtension.lowercaseString isEqual:suffix])name=name.stringByDeletingPathExtension;}
    self.archiveProjectName=name;
    [self showArchiveHUD];self.archiveHUD.label.text=@"正在导入工程…";self.archiveHUD.button.hidden=YES;
    self.importInProgress=NO;
    [self importURLs:@[[NSURL fileURLWithPath:project[@"root"] isDirectory:YES]]];
}
- (void)importURLs:(NSArray<NSURL *> *)urls {
    if(!urls.count){[self showImportMessage:@"没有选中的文件或目录。"];return;}
    if(self.importInProgress)return;
    self.importInProgress=YES;
    NSString *projectName=self.archiveProjectName?:urls.firstObject.lastPathComponent.stringByDeletingPathExtension;
    NSMutableArray<NSURL *> *scoped=[NSMutableArray new];
    for(NSURL *url in urls){BOOL granted=[url startAccessingSecurityScopedResource];if(granted)[scoped addObject:url];}
    self.console.text = @"正在复制工程文件…";
    self.navigationItem.leftBarButtonItem.enabled = NO;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *dest = [documents stringByAppendingPathComponent:[@"Imported-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        __block NSError *copyError = nil;
        for (NSURL *url in urls) {
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            NSError *coordinationError = nil;
            [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:&coordinationError byAccessor:^(NSURL *readURL) {
                BOOL directory = NO;
                [NSFileManager.defaultManager fileExistsAtPath:readURL.path isDirectory:&directory];
                if(directory&&urls.count!=1){copyError=[NSError errorWithDomain:@"TweakForgeImport" code:2 userInfo:@{NSLocalizedDescriptionKey:@"工程文件夹每次仅支持一个；源码文件支持多选。"}];return;}
                if (directory && urls.count == 1) [NSFileManager.defaultManager copyItemAtPath:readURL.path toPath:dest error:&copyError];
                else {
                    if (![NSFileManager.defaultManager createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:&copyError]) return;
                    [NSFileManager.defaultManager copyItemAtPath:readURL.path toPath:[dest stringByAppendingPathComponent:readURL.lastPathComponent] error:&copyError];
                }
            }];
            if (coordinationError) copyError = coordinationError;
            if (copyError) break;
        }
        for(NSURL *url in scoped)[url stopAccessingSecurityScopedResource];
        if(!copyError){for(NSString *entry in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dest error:nil])if([entry hasPrefix:@".studio-"])[NSFileManager.defaultManager removeItemAtPath:[dest stringByAppendingPathComponent:entry] error:&copyError];}
        if(!copyError)TMCPrepareImportedProject(dest,projectName,&copyError);
        NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dest error:nil];
        NSMutableArray *sources = [NSMutableArray array];
        NSMutableArray *plists = [NSMutableArray array];
        for (NSString *file in files) {
            if ([@[@"x", @"xm", @"m", @"mm", @"c", @"cpp"] containsObject:file.pathExtension.lowercaseString]) [sources addObject:file];
            if ([file.pathExtension.lowercaseString isEqualToString:@"plist"]) [plists addObject:file];
        }
        NSArray *configuredSources = sourcePaths(dest);
        NSDictionary *config = projectConfig(dest);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.importInProgress=NO;
            [self cleanupArchive];
            self.navigationItem.leftBarButtonItem.enabled = YES;
            self.navigationItem.rightBarButtonItem.enabled = YES;
            if (copyError) { [NSFileManager.defaultManager removeItemAtPath:dest error:nil];[self showImportMessage:[@"导入出错：" stringByAppendingString:copyError.localizedDescription]]; return; }
            NSUInteger logosCount = 0;
            for (NSString *name in sources) if ([name.pathExtension.lowercaseString isEqualToString:@"xm"]) logosCount++;
            if (!configuredSources.count) { [NSFileManager.defaultManager removeItemAtPath:dest error:nil];[self showImportMessage:@"没有找到可编译的源码，请检查 MobileCompiler.json 中的 sources 配置。"]; return; }
            [sources sortUsingSelector:@selector(compare:)];
            self.importedSource = configuredSources.firstObject;
            self.importedProject = dest;
            [NSUserDefaults.standardUserDefaults setObject:dest.lastPathComponent forKey:@"ImportedProject"];
            [NSUserDefaults.standardUserDefaults setObject:[self.importedSource substringFromIndex:documents.length + 1] forKey:@"ImportedSourceRelativePath"];
            BOOL control = [files containsObject:@"control"];
            NSString *metadata = (control && plists.count == 1) ? @"将使用导入的 control 和过滤 plist。" : @"未同时提供 control 与过滤 plist，运行时将提示补齐；仅源码测试可使用默认测试元数据。";
            [self showImportMessage:[NSString stringWithFormat:@"已导入 %lu 个源码：%@\n%@\n%@", (unsigned long)configuredSources.count, [config[@"name"] isKindOfClass:NSString.class] ? config[@"name"] : [sources componentsJoinedByString:@", "], metadata, self.hasBuilt ? @"已有构建正在执行。" : @"点击运行开始本机构建。"]];
            if(self.importCompletion){self.pendingImportedProject=dest;[self finishPendingImport];}
            if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test-project"]) [self runProof];
        });
    });
}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];[self presentPendingPicker];[self finishPendingImport];}
- (void)finishPendingImport{
    if(!self.pendingImportedProject)return;
    UIViewController *host=[self importHost];
    id<UIViewControllerTransitionCoordinator> transition=host.presentedViewController.transitionCoordinator?:host.transitionCoordinator;
    if(transition&&[transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){dispatch_async(dispatch_get_main_queue(),^{[self finishPendingImport];});}])return;
    if(host.presentedViewController){
        [host dismissViewControllerAnimated:YES completion:^{[self finishPendingImport];}];
        return;
    }
    NSString *path=self.pendingImportedProject;self.pendingImportedProject=nil;
    if(self.importCompletion)self.importCompletion(path);
}
- (void)exportResult {
    NSMutableArray *files = [NSMutableArray array];
    NSMutableArray *exportNames=[@[@"build.log",@"report.json",@"symbols.json",@"provenance.json",@"Tweak.mm",@"control",@"filter.plist"] mutableCopy];
    for(NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.lastBuild error:nil])if([file hasPrefix:@"logos-"]&&[@[@"m",@"mm"] containsObject:file.pathExtension])[exportNames addObject:file];
    id exportReport=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[self.lastBuild stringByAppendingPathComponent:@"report.json"]]?:[NSData data] options:0 error:nil];
    if([exportReport isKindOfClass:NSDictionary.class]&&[exportReport[@"namedArtifacts"] isKindOfClass:NSArray.class])[exportNames addObjectsFromArray:exportReport[@"namedArtifacts"]];else [exportNames addObjectsFromArray:@[@"MobileTweak.deb",@"Smoke.dylib"]];
    for (NSString *name in exportNames) {
        NSString *path = [self.lastBuild stringByAppendingPathComponent:name];
        if (path && [NSFileManager.defaultManager fileExistsAtPath:path]) [files addObject:[NSURL fileURLWithPath:path]];
    }
    if (files.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"暂无可导出文件" message:@"请先点击运行。构建完成后，这里会打开系统分享菜单，可保存结果或日志到“文件”。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
    sheet.popoverPresentationController.barButtonItem = self.toolbarItems.firstObject;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)runProof {
    if (TMCBuildRunning) {
        self.console.text = @"已有构建正在执行，请等待当前任务完成。";
        return;
    }
    TMCBuildRunning = YES;
    self.hasBuilt = YES;
    self.lastPackage = nil;
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    self.console.text = @"执行 IPA 内嵌编译器…\n";
    self.navigationItem.rightBarButtonItem.enabled = NO;
    self.navigationItem.leftBarButtonItem.enabled = NO;
    ((UIBarButtonItem *)self.toolbarItems.firstObject).enabled = NO;
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    self.lastBuild = [documents stringByAppendingPathComponent:[@"Build-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSString *build = self.lastBuild;
    NSError *directoryError=nil;if(![NSFileManager.defaultManager createDirectoryAtPath:build withIntermediateDirectories:YES attributes:nil error:&directoryError]){self.hasBuilt=NO;TMCBuildRunning=NO;UIApplication.sharedApplication.idleTimerDisabled=NO;self.console.text=[@"创建构建目录失败：" stringByAppendingString:directoryError.localizedDescription];if(self.buildCompletion)self.buildCompletion(NO);return;}
    NSDictionary *running=@{@"startedAt":@(NSDate.date.timeIntervalSince1970)};[[NSJSONSerialization dataWithJSONObject:running options:0 error:nil] writeToFile:[build stringByAppendingPathComponent:@".build-in-progress.json"] atomically:YES];
    NSString *globalDebPattern=[NSUserDefaults.standardUserDefaults stringForKey:@"StudioOutputPattern-deb"]?:TMCDefaultOutputPattern(@"deb");
    NSString *globalDylibPattern=[NSUserDefaults.standardUserDefaults stringForKey:@"StudioOutputPattern-dylib"]?:TMCDefaultOutputPattern(@"dylib");
    NSTimeInterval startedAt=NSDate.date.timeIntervalSince1970;
    NSTimeInterval startedUptime=NSProcessInfo.processInfo.systemUptime;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [[NSFileManager defaultManager] createDirectoryAtPath:build withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *source=self.importedSource;
        if(!self.importedProject&&!source){source=[build stringByAppendingPathComponent:@"smoke.m"];[@"#import <Foundation/Foundation.h>\n@interface MobileSmoke : NSObject\n-(NSString*)message;\n@end\n@implementation MobileSmoke\n-(NSString*)message { return @\"Built inside iOS\"; }\n@end\n" writeToFile:source atomically:YES encoding:NSUTF8StringEncoding error:nil];}
        NSString *projectDirectory=self.importedProject?:source.stringByDeletingLastPathComponent;
        NSDictionary *config = TMCEffectiveBuildOptions(projectConfig(projectDirectory),NSUserDefaults.standardUserDefaults);
        NSString *debPattern=config[@"outputPattern-deb"]?:globalDebPattern,*dylibPattern=[config[@"exportDylib"] boolValue]?(config[@"outputPattern-dylib"]?:globalDylibPattern):@"{product}";
        NSMutableArray<NSString *> *projectSources = [sourcePaths(projectDirectory) mutableCopy];
        NSMutableArray *logosResults = [NSMutableArray array];
        NSArray *originalSources = projectSources.copy;
        NSDictionary *provenance=TFBuildProvenance(projectDirectory,originalSources,config,build);
        [[NSJSONSerialization dataWithJSONObject:provenance options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[build stringByAppendingPathComponent:@"provenance.json"] atomically:YES];
        NSString *logPath = [build stringByAppendingPathComponent:@"build.log"];
        FILE *log = fopen(logPath.fileSystemRepresentation, "w+");
        TMCLog(log,"BUILD STARTED — %s\n",NSDate.date.description.UTF8String);
        FILE *input = fopen("/dev/null", "r");
        if(!log||!input){if(log)fclose(log);if(input)fclose(input);NSDictionary *failure=@{@"success":@NO,@"commands":@[],@"packageError":@"创建构建日志失败，请检查可用存储空间"};[[NSJSONSerialization dataWithJSONObject:failure options:0 error:nil] writeToFile:[build stringByAppendingPathComponent:@"report.json"] atomically:YES];dispatch_async(dispatch_get_main_queue(),^{self.hasBuilt=NO;TMCBuildRunning=NO;UIApplication.sharedApplication.idleTimerDisabled=NO;self.console.text=failure[@"packageError"];if(self.buildCompletion)self.buildCompletion(NO);});return;}
        initializeEnvironment();
        setenv("SYSROOT", NSBundle.mainBundle.bundlePath.fileSystemRepresentation, 1);
        NSString *perlLib = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Perl"];
        setenv("APPDIR", NSBundle.mainBundle.bundlePath.fileSystemRepresentation, 1);
        setenv("PERL5LIB", perlLib.UTF8String, 1);
        chdir(build.fileSystemRepresentation);
        joinMainThread = true;
        ios_switchSession((__bridge const void *)self);
        ios_setStreams(input, log, log);
        NSError *registrationError = addCommandList([[NSBundle mainBundle] pathForResource:@"commands" ofType:@"plist"]);
        TMCLog(log, "registration: %s\n", registrationError.description.UTF8String ?: "OK");
        for (NSString *name in @[@"libLLVM", @"clang", @"lld"]) {
            NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.framework/%@", name, name]];
            void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
            TMCLog(log, "%s: %s\n", name.UTF8String, handle ? "loaded" : dlerror());
        }
        TMCLog(log, "commands=%s\n", commandsAsString().UTF8String); fflush(log);
        for (NSUInteger logosIndex=0;logosIndex<originalSources.count;logosIndex++) {
            NSString *original=originalSources[logosIndex];
            if (![@[@"x",@"xm"] containsObject:original.pathExtension.lowercaseString]) continue;
            source = original;
            NSString *extension=[original.pathExtension.lowercaseString isEqual:@"x"]?@"m":@"mm";
            NSString *generated = [build stringByAppendingPathComponent:[NSString stringWithFormat:@"logos-%03lu.%@",(unsigned long)logosIndex,extension]];
            FILE *output = fopen(generated.fileSystemRepresentation, "w");
            NSString *logos = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"logos/bin/logos.pl"];
            TMCLog(log, "Perl runtime: 5.34.0; bundled iOS modules: %s\n", perlLib.UTF8String);
            // Logos writes source to stdout; diagnostics use stderr. Keep a separate output file.
            NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"perl", logos, nil];
            NSString *generator=config[@"logosGenerator"];
            if([@[@"internal",@"MobileSubstrate",@"libhooker"] containsObject:generator])[arguments addObjectsFromArray:@[@"-c",[@"generator=" stringByAppendingString:generator]]];
            [arguments addObject:source];
            int status = output ? runToolOutput(arguments, input, output, log) : 74;
            if(output)fclose(output);
            TMCLog(log, "Logos exit=%d\n", status);
            NSString *originalRelative=[original substringFromIndex:projectDirectory.length+1];
            [logosResults addObject:@{@"source":originalRelative,@"generated":generated.lastPathComponent,@"exit":@(status)}];
            if (status == 0) projectSources[logosIndex] = generated;
            else {
                NSData *failure = [NSJSONSerialization dataWithJSONObject:@{@"execution":@"embedded iOS frameworks", @"logos":logosResults, @"commands":@[], @"success":@NO, @"startedAt":@(startedAt), @"finishedAt":@(NSDate.date.timeIntervalSince1970), @"durationSeconds":@(NSProcessInfo.processInfo.systemUptime-startedUptime)} options:NSJSONWritingPrettyPrinted error:nil];
                [failure writeToFile:[build stringByAppendingPathComponent:@"report.json"] atomically:YES];
                TMCLog(log,"BUILD FAILED — Logos exit=%d; duration=%.2fs\n",status,NSProcessInfo.processInfo.systemUptime-startedUptime);
                fflush(log); dispatch_async(dispatch_get_main_queue(), ^{
                self.hasBuilt = NO; TMCBuildRunning = NO;
                if (self.buildCompletion) self.buildCompletion(NO);
                self.console.text = @"Logos 执行失败，请点击导出结果，保存 build.log 以便排查。";
                UIApplication.sharedApplication.idleTimerDisabled = NO;
                self.navigationItem.leftBarButtonItem.enabled = YES;
                ((UIBarButtonItem *)self.toolbarItems.firstObject).enabled = YES;
            }); fclose(input); fclose(log); return; }
        }
        TMCLog(log,"准备本地 SDK（首次构建或缓存清理后需要解压）\n");
        NSError *sdkError=nil;
        NSDictionary *sdkSettings=TMCSDKBuildSettings(config,NSUserDefaults.standardUserDefaults,&sdkError);
        NSString *sdkVersion=sdkSettings[@"sdkVersion"],*minimum=sdkSettings[@"deploymentTarget"];
        NSString *sdk=sdkSettings?TMCPrepareSelectedSDK(NSBundle.mainBundle,NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject,sdkVersion,&sdkError):nil;
        NSString *cppSDK=sdk;
        if(sdk&&[sdkVersion isEqual:@"26.0"]){for(NSString *source in projectSources)if([@[@"mm",@"cpp"] containsObject:source.pathExtension.lowercaseString]){cppSDK=TMCPrepareSelectedSDK(NSBundle.mainBundle,NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject,@"16.4",&sdkError);if(!cppSDK)sdk=nil;else TMCLog(log,"C++ standard library headers: SDK 16.4 compatibility set for Clang 14 (platform headers/linker stubs remain SDK 26.0)\n");break;}}
        if(!sdk){
            TMCLog(log,"BUILD FAILED — SDK: %s\n",sdkError.localizedDescription.UTF8String);
            NSDictionary *failure=@{@"success":@NO,@"execution":@"embedded iOS frameworks",@"error":sdkError.localizedDescription?:@"SDK preparation failed",@"commands":@[],@"startedAt":@(startedAt),@"finishedAt":@(NSDate.date.timeIntervalSince1970)};
            [[NSJSONSerialization dataWithJSONObject:failure options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[build stringByAppendingPathComponent:@"report.json"] atomically:YES];
            fclose(input);fclose(log);
            dispatch_async(dispatch_get_main_queue(), ^{self.hasBuilt=NO;TMCBuildRunning=NO;UIApplication.sharedApplication.idleTimerDisabled=NO;self.navigationItem.leftBarButtonItem.enabled=YES;self.navigationItem.rightBarButtonItem.enabled=YES;((UIBarButtonItem *)self.toolbarItems.firstObject).enabled=YES;self.console.text=sdkError.localizedDescription;if(self.buildCompletion)self.buildCompletion(NO);});return;
        }
        TMCLog(log,"SDK=%s; deployment target=%s; embedded Clang/LLD 14\n",sdkVersion.UTF8String,minimum.UTF8String);
        NSString *headers = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"ClangInclude"];
        NSString *include = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Include"];
        NSString *vendorFrameworks = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"VendorFrameworks"];
        NSMutableArray *projectPlists = [NSMutableArray array];
        for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:projectDirectory error:nil]) {
            if ([file.pathExtension.lowercaseString isEqualToString:@"plist"]) [projectPlists addObject:file];
        }
        NSString *controlPath = [projectDirectory stringByAppendingPathComponent:@"control"];
        BOOL hasControl = [NSFileManager.defaultManager fileExistsAtPath:controlPath];
        BOOL customMetadata = hasControl || projectPlists.count > 0;
        NSString *tweakName = [config[@"productName"] isKindOfClass:NSString.class] ? config[@"productName"] : [config[@"name"] isKindOfClass:NSString.class] ? config[@"name"] : projectPlists.count == 1 ? [projectPlists.firstObject stringByDeletingPathExtension] : @"MobileTweak";
        NSString *packageControl=[NSString stringWithContentsOfFile:controlPath encoding:NSUTF8StringEncoding error:nil];
        NSArray *packageSchemes=config[@"packageSchemes"];BOOL multipleSchemes=[config[@"package"] boolValue]&&packageSchemes.count>1;NSString *packageScheme=TMCPackageScheme(config,packageControl);NSString *cpu=[config[@"cpuArchitecture"] isEqual:@"arm64e"]?@"arm64e":@"arm64";
        NSDictionary *namingContext=TMCOutputContext(projectDirectory,tweakName,[NSDate dateWithTimeIntervalSince1970:startedAt]);
        NSError *namingError=nil;NSString *dylibName=TMCOutputFilename(dylibPattern,@"dylib",namingContext,&namingError);NSString *debName=[config[@"package"] boolValue]?TMCOutputFilename(debPattern,@"deb",namingContext,&namingError):@"unused.deb";
        if(multipleSchemes&&[config[@"package"] boolValue]){debName=TMCVariantOutputFilename(debPattern,@"deb",namingContext,packageSchemes,packageScheme,&namingError);}
        if(!dylibName||!debName){
            TMCLog(log,"output naming error: %s\n",namingError.localizedDescription.UTF8String);TMCLog(log,"BUILD FAILED — output naming; duration=%.2fs\n",NSProcessInfo.processInfo.systemUptime-startedUptime);fflush(log);fclose(input);fclose(log);
            NSDictionary *failure=@{@"execution":@"embedded iOS frameworks",@"success":@NO,@"commands":@[],@"outputNamingError":namingError.localizedDescription?:@"文件名模板有误",@"startedAt":@(startedAt),@"finishedAt":@(NSDate.date.timeIntervalSince1970),@"durationSeconds":@(NSProcessInfo.processInfo.systemUptime-startedUptime)};
            [[NSJSONSerialization dataWithJSONObject:failure options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[build stringByAppendingPathComponent:@"report.json"] atomically:YES];
            dispatch_async(dispatch_get_main_queue(),^{self.hasBuilt=NO;TMCBuildRunning=NO;UIApplication.sharedApplication.idleTimerDisabled=NO;self.console.text=namingError.localizedDescription;self.navigationItem.rightBarButtonItem.enabled=YES;self.navigationItem.leftBarButtonItem.enabled=YES;((UIBarButtonItem *)self.toolbarItems.firstObject).enabled=YES;if(self.buildCompletion)self.buildCompletion(NO);});return;
        }
        TMCLog(log,"metadata: %s; internal product: %s; output dylib: %s; output deb: %s\n",customMetadata?"project control/plist":"default test metadata (com.example.target)",tweakName.UTF8String,dylibName.UTF8String,debName.UTF8String);
        TMCLog(log,"package scheme=%s; CPU=%s; package enabled=%s\n",packageScheme.UTF8String,cpu.UTF8String,[config[@"package"] isEqual:@NO]?"no":"yes");
        NSMutableArray<NSArray<NSString *> *> *commands = [NSMutableArray array];
        NSMutableArray *objects = [NSMutableArray array];
        NSMutableArray *compileSources = [NSMutableArray array];
        for (NSUInteger index = 0; index < projectSources.count; index++) {
            NSString *inputSource = projectSources[index];
            NSString *ext = inputSource.pathExtension.lowercaseString;
            BOOL cpp = [@[@"mm", @"cpp"] containsObject:ext];
            BOOL objc = [@[@"m", @"mm"] containsObject:ext];
            NSString *language = objc ? (cpp ? @"objective-c++" : @"objective-c") : (cpp ? @"c++" : @"c");
            NSString *object = [build stringByAppendingPathComponent:[NSString stringWithFormat:@"source-%03lu.o", (unsigned long)index]];
            NSMutableArray *arguments = [@[@"clang", @"-cc1", @"-fdiagnostics-parseable-fixits", @"-triple",  [NSString stringWithFormat:@"%@-apple-ios%@",cpu,minimum], @"-emit-obj", @"-target-cpu", [cpu isEqual:@"arm64e"]?@"apple-a12":@"apple-a7", @"-target-feature", @"+neon", @"-target-feature", @"+fp-armv8", @"-target-abi", @"darwinpcs", @"-fgnuc-version=4.2.1", @"-mrelocation-model", @"pic", @"-pic-level", @"2", @"-fblocks", @"-isysroot", sdk, @"-internal-isystem", headers, @"-internal-isystem", [sdk stringByAppendingPathComponent:@"usr/include"], @"-I", include, @"-I", projectDirectory, @"-F", [sdk stringByAppendingPathComponent:@"System/Library/Frameworks"]] mutableCopy];
            // SDK 26 target autodetection differs from embedded Clang 14. Declare
            // our actual iOS device platform explicitly. SubFrameworks holds
            // UIUtilities headers imported by the SDK's UIKit public headers.
            if([sdkVersion isEqual:@"26.0"])[arguments addObjectsFromArray:@[@"-DTARGET_OS_IPHONE=1",@"-DTARGET_OS_IOS=1",@"-DTARGET_OS_MAC=1",@"-DTARGET_OS_OSX=0",@"-DTARGET_OS_MACCATALYST=0",@"-F",[sdk stringByAppendingPathComponent:@"System/Library/SubFrameworks"]]];
            [arguments addObjectsFromArray:@[@"-I", [originalSources[index] stringByDeletingLastPathComponent], @"-I", inputSource.stringByDeletingLastPathComponent, @"-internal-isystem", [sdk stringByAppendingPathComponent:@"usr/include/libxml2"]]];
            for (NSString *relative in config[@"includeDirectories"]) {
                NSString *path = [relative isEqualToString:@"."] ? projectDirectory : projectPath(projectDirectory, relative);
                if (path) [arguments addObjectsFromArray:@[@"-I", path]];
            }
            for (NSString *define in config[@"defines"]) if ([define isKindOfClass:NSString.class]) [arguments addObjectsFromArray:@[@"-D", define]];
            for (NSString *flag in config[@"warningFlags"]) if ([flag isKindOfClass:NSString.class] && ([flag hasPrefix:@"-W"]||[flag isEqual:@"-w"])) [arguments addObject:flag];
            NSString *prefix = projectPath(projectDirectory, config[@"prefixHeader"]);
            if (prefix) [arguments addObjectsFromArray:@[@"-include", prefix]];
            for(NSString *relative in config[@"forcedIncludes"]){NSString *forced=projectPath(projectDirectory,relative);if(forced)[arguments addObjectsFromArray:@[@"-include",forced]];}
            NSString *optimization = TFResolvedOptimization(config);
            [arguments addObjectsFromArray:@[@"-debug-info-kind=standalone",@"-dwarf-version=4",@"-main-file-name",inputSource.lastPathComponent]];
            if ([@[@"-O0", @"-O1", @"-O2", @"-O3", @"-Os", @"-Oz"] containsObject:optimization]) [arguments addObject:optimization];
            if(objc){if(![config[@"objcArc"] isEqual:@NO])[arguments addObject:@"-fobjc-arc"];[arguments addObjectsFromArray:@[[@"-fobjc-runtime=ios-" stringByAppendingString:minimum],@"-fobjc-exceptions",@"-fexceptions"]];}
            NSArray *cStandards=@[@"c89",@"gnu89",@"c99",@"gnu99",@"c11",@"gnu11",@"c17",@"gnu17"];
            if(!cpp&&[cStandards containsObject:config[@"cStandard"]])[arguments addObject:[@"-std=" stringByAppendingString:config[@"cStandard"]]];
            if (cpp) {
                NSArray *standards=@[@"c++98",@"gnu++98",@"c++11",@"gnu++11",@"c++14",@"gnu++14",@"c++17",@"gnu++17",@"c++20",@"gnu++20"];
                NSString *standard=[standards containsObject:config[@"cxxStandard"]]?config[@"cxxStandard"]:@"c++17";
                [arguments addObjectsFromArray:@[[@"-std=" stringByAppendingString:standard], @"-fcxx-exceptions", @"-fexceptions"]];
                [arguments insertObjects:@[@"-internal-isystem", [cppSDK stringByAppendingPathComponent:@"usr/include/c++/v1"]] atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(2, 2)]];
            }
            [arguments addObjectsFromArray:@[@"-x", language, inputSource, @"-o", object]];
            [commands addObject:arguments];
            [objects addObject:object];
            [compileSources addObject:[originalSources[index] substringFromIndex:projectDirectory.length+1]];
        }
        NSMutableArray *link = [@[@"ld64.lld", @"-dylib", @"-arch", cpu, @"-platform_version", @"ios", minimum, sdkVersion, @"-syslibroot", sdk, @"-lSystem", @"-lobjc", @"-lc++", @"-framework", @"Foundation", @"-framework", @"UIKit", @"-F", vendorFrameworks, @"-rpath", [packageScheme isEqual:@"rootless"]?@"/var/jb/Library/Frameworks":[packageScheme isEqual:@"roothide"]?@"@loader_path/.jbroot/Library/Frameworks":@"/Library/Frameworks", @"-undefined", @"dynamic_lookup", @"-install_name", [NSString stringWithFormat:[packageScheme isEqual:@"roothide"]?@"@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/%@.dylib":@"@rpath/%@.dylib", tweakName]] mutableCopy];
        for (NSString *framework in config[@"frameworks"]) [link addObjectsFromArray:@[@"-framework", framework]];
        for (NSString *library in config[@"libraries"]) [link addObject:[@"-l" stringByAppendingString:library]];
        [link addObjectsFromArray:objects];
        [link addObjectsFromArray:@[@"-o", [build stringByAppendingPathComponent:dylibName]]];
        [commands addObject:link];
        TMCLog(log, "source count=%lu; compile all objects, then link once\n", (unsigned long)projectSources.count);
        NSMutableArray *results = [NSMutableArray array];
        BOOL compileFailed = NO;
        for (NSArray<NSString *> *arguments in commands) {
            if ([arguments.firstObject isEqualToString:@"ld64.lld"] && compileFailed) break;
            NSUInteger progress = results.count;
            NSString *label = progress < compileSources.count ? [NSString stringWithFormat:@"编译 %lu/%lu：%@", (unsigned long)progress + 1, (unsigned long)compileSources.count, compileSources[progress]] : @"正在链接所有对象…";
            dispatch_async(dispatch_get_main_queue(), ^{ self.console.text = label; });
            NSString *command = [arguments componentsJoinedByString:@" "];
            TMCLog(log, "\n$ %s\n", command.UTF8String); fflush(log);
            int status = runTool(arguments, input, log);
            TMCLog(log, "\nexit=%d\n", status); fflush(log);
            NSUInteger step = results.count;
            [results addObject:@{@"command": command, @"exit": @(status), @"stage":step < compileSources.count ? @"compile" : @"link", @"source":step < compileSources.count ? compileSources[step] : @"all objects"}];
            if (status != 0) {
                compileFailed = YES;
                if (![config[@"collectErrors"] isEqual:@YES]) break;
            }
        }
        // LLVM 14 LLD accepts -arch arm64e but emits ARM64_ALL. Reject it before packaging.
        if(!compileFailed&&[cpu isEqual:@"arm64e"]){NSData *linked=[NSData dataWithContentsOfFile:[build stringByAppendingPathComponent:dylibName]];struct mach_header_64 mh={0};if(linked.length>=sizeof(mh))[linked getBytes:&mh length:sizeof(mh)];if((mh.cpusubtype&0xffffff)!=2){compileFailed=YES;TMCLog(log,"error: 当前内嵌 LLVM 14 链接器将 arm64e 输出为 arm64，已停止打包。请在项目设置选择 arm64；iphoneos-arm64e 隐根包可使用 arm64 动态库。真正 arm64e ABI 需要更新链接器。\n");[NSFileManager.defaultManager removeItemAtPath:[build stringByAppendingPathComponent:dylibName] error:nil];}}
        BOOL toolSuccess = !compileFailed && projectSources.count > 0 && results.count == commands.count && [results.lastObject[@"exit"] intValue] == 0;
        NSMutableDictionary *report = [@{@"execution": @"embedded iOS frameworks", @"commands": results, @"logos":logosResults, @"sourceCount":@(projectSources.count), @"success":@NO, @"projectName":tweakName,@"packageScheme":packageScheme,@"cpuArchitecture":cpu} mutableCopy];
        NSMutableArray *artifacts = [NSMutableArray arrayWithObject:dylibName];
        for (NSString *object in objects) [artifacts addObject:object.lastPathComponent];
        for (NSString *name in artifacts) {
            NSData *data = [NSData dataWithContentsOfFile:[build stringByAppendingPathComponent:name]];
            if (data.length >= sizeof(struct mach_header_64)) {
                struct mach_header_64 header; [data getBytes:&header length:sizeof(header)];
                report[name] = @{@"bytes": @(data.length), @"magic": @(header.magic), @"cputype": @(header.cputype), @"cpusubtype":@(header.cpusubtype), @"filetype": @(header.filetype)};
            }
        }
        BOOL shouldPackage=[config[@"package"] boolValue];
        NSMutableArray *namedArtifacts=[NSMutableArray new],*packages=[NSMutableArray new],*variantReports=[NSMutableArray new];
        if(toolSuccess&&!shouldPackage){report[@"success"]=@YES;report[@"packageSkipped"]=@"Dynamic library build requested";[namedArtifacts addObject:dylibName];}
        if(toolSuccess&&shouldPackage){BOOL allPassed=YES;
          for(NSString *scheme in packageSchemes){
            NSDictionary *context=TMCNamingContextForScheme(namingContext,scheme);
            NSError *error=nil;NSString *variantDylib=TMCVariantOutputFilename(dylibPattern,@"dylib",context,packageSchemes,scheme,&error),*variantDeb=TMCVariantOutputFilename(debPattern,@"deb",context,packageSchemes,scheme,&error);
            if(![scheme isEqual:packageScheme]){NSString *cache=[build stringByAppendingPathComponent:@".package-link-cache"];[NSFileManager.defaultManager createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil];variantDylib=[@".package-link-cache" stringByAppendingPathComponent:[scheme stringByAppendingPathExtension:@"dylib"]];}else variantDylib=dylibName;
            if(!variantDylib||!variantDeb){allPassed=NO;report[@"outputNamingError"]=error.localizedDescription?:@"文件名无效";break;}
            TMCLog(log,"\n打包目标：%s\n",scheme.UTF8String);
            if(![scheme isEqual:packageScheme]){NSMutableArray *variantLink=[link mutableCopy];NSUInteger pathIndex=[variantLink indexOfObject:@"-rpath"],installIndex=[variantLink indexOfObject:@"-install_name"],outputIndex=[variantLink indexOfObject:@"-o"];
             variantLink[pathIndex+1]=[scheme isEqual:@"rootless"]?@"/var/jb/Library/Frameworks":[scheme isEqual:@"roothide"]?@"@loader_path/.jbroot/Library/Frameworks":@"/Library/Frameworks";
             variantLink[installIndex+1]=[NSString stringWithFormat:[scheme isEqual:@"roothide"]?@"@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/%@.dylib":@"@rpath/%@.dylib",tweakName];variantLink[outputIndex+1]=[build stringByAppendingPathComponent:variantDylib];
             TMCLog(log,"$ %s\n",[variantLink componentsJoinedByString:@" "].UTF8String);int status=runTool(variantLink,input,log);TMCLog(log,"exit=%d\n",status);[results addObject:@{@"command":[variantLink componentsJoinedByString:@" "],@"exit":@(status),@"stage":[@"link-" stringByAppendingString:scheme],@"source":@"all objects"}];if(status){allPassed=NO;report[@"packageError"]=[@"链接失败：" stringByAppendingString:scheme];break;}}
            NSData *dylib=[NSData dataWithContentsOfFile:[build stringByAppendingPathComponent:variantDylib]];if(dylib&&[scheme isEqual:packageScheme])[namedArtifacts addObject:variantDylib];NSData *deb=nil;
            if(!customMetadata)deb=TMCDebPackageForProject(dylib,tweakName,@"com.example.target",scheme,projectDirectory,config,&error);
            else if(hasControl&&projectPlists.count==1){NSString *control=[NSString stringWithContentsOfFile:controlPath encoding:NSUTF8StringEncoding error:&error];NSData *filter=[NSData dataWithContentsOfFile:[projectDirectory stringByAppendingPathComponent:projectPlists.firstObject] options:0 error:&error];if(control&&filter){NSString *adjusted=TMCControlForScheme(control,scheme);deb=TMCDebPackageWithResources(dylib,tweakName,filter,adjusted,projectDirectory,scheme,config,&error);[adjusted writeToFile:[build stringByAppendingPathComponent:multipleSchemes?[@"control-" stringByAppendingString:scheme]:@"control"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[filter writeToFile:[build stringByAppendingPathComponent:@"filter.plist"] atomically:YES];}}
            else error=[NSError errorWithDomain:@"Compiler" code:5 userInfo:@{NSLocalizedDescriptionKey:@"请在项目设置填写目标 Bundle ID，并保存 control 和过滤 plist 后构建。"}];
            NSString *path=[build stringByAppendingPathComponent:variantDeb];BOOL success=deb&&[deb writeToFile:path options:NSDataWritingAtomic error:&error];[variantReports addObject:@{@"scheme":scheme,@"success":@(success),@"dylib":variantDylib,@"deb":variantDeb}];
            if(success){self.lastPackage=path;NSDictionary *entry=@{@"name":variantDeb,@"bytes":@(deb.length),@"scheme":scheme};[packages addObject:entry];[namedArtifacts addObject:variantDeb];TMCLog(log,"Debian package generated: %s (%lu bytes)\n",path.UTF8String,(unsigned long)deb.length);}
            else{allPassed=NO;report[@"packageError"]=error.localizedDescription?:@"打包失败";TMCLog(log,"package error: %s\n",[report[@"packageError"] UTF8String]);break;}
          }
          report[@"success"]=@(allPassed&&packages.count==packageSchemes.count&&packages.count>0);
        }
        if(packages.count)report[@"package"]=packages.firstObject;report[@"packages"]=packages;report[@"variants"]=variantReports;report[@"packageSchemes"]=packageSchemes;
        report[@"outputNaming"]=@{@"debPattern":debPattern,@"dylibPattern":dylibPattern,@"context":namingContext,@"dylib":dylibName,@"deb":debName};
        report[@"provenance"]=provenance;
        report[@"runtimeVerified"]=@NO;report[@"sdkSettings"]=sdkSettings;
        NSMutableArray *symbolImages=[NSMutableArray new];
        NSMutableOrderedSet *imagePaths=[NSMutableOrderedSet orderedSetWithObject:dylibName];
        for(NSDictionary *variant in variantReports)if(variant[@"dylib"])[imagePaths addObject:variant[@"dylib"]];
        for(NSString *imagePath in imagePaths){NSMutableDictionary *index=[TFBinaryIndex([NSData dataWithContentsOfFile:[build stringByAppendingPathComponent:imagePath]]) mutableCopy];if([index[@"uuid"] length]){index[@"file"]=imagePath;[symbolImages addObject:index];}}
        report[@"binaryImages"]=symbolImages;
        NSData *symbolData=[NSJSONSerialization dataWithJSONObject:@{@"schema":@1,@"images":symbolImages,@"provenance":report[@"provenance"]} options:NSJSONWritingPrettyPrinted error:nil];
        [symbolData writeToFile:[build stringByAppendingPathComponent:@"symbols.json"] atomically:YES];
        TMCLog(log,"运行验证：尚未在宿主中验证；构建通过不代表运行无误。\n");
        BOOL exportDylib=[config[@"exportDylib"] boolValue];report[@"exportDylib"]=@(exportDylib);
        if(!exportDylib&&shouldPackage&&[report[@"success"] boolValue]){for(NSString *name in [namedArtifacts copy])if([name.pathExtension isEqual:@"dylib"]){[NSFileManager.defaultManager removeItemAtPath:[build stringByAppendingPathComponent:name] error:nil];[namedArtifacts removeObject:name];}TMCLog(log,"仅导出 DEB：动态库已包含在安装包中。\n");}
        if(!exportDylib&&!shouldPackage){report[@"success"]=@NO;report[@"packageError"]=@"请在构建设置至少勾选 dylib 或 deb。";for(NSString *name in [namedArtifacts copy]){[NSFileManager.defaultManager removeItemAtPath:[build stringByAppendingPathComponent:name] error:nil];}[namedArtifacts removeAllObjects];}
        report[@"namedArtifacts"]=namedArtifacts;
        report[@"startedAt"]=@(startedAt);
        report[@"finishedAt"]=@(NSDate.date.timeIntervalSince1970);
        report[@"durationSeconds"]=@(NSProcessInfo.processInfo.systemUptime-startedUptime);
        TMCLog(log,"%s · %lu 个源码 · 耗时 %.2f 秒\n",[report[@"success"] boolValue]?"构建成功":"构建失败",(unsigned long)projectSources.count,[report[@"durationSeconds"] doubleValue]);
        for(NSString *artifact in namedArtifacts){NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:[build stringByAppendingPathComponent:artifact] error:nil];TMCLog(log,"生成文件：%s · %s\n",artifact.UTF8String,[NSByteCountFormatter stringFromByteCount:a.fileSize countStyle:NSByteCountFormatterCountStyleFile].UTF8String);}
        TMCLog(log,"签名状态：未签名，请导出后使用签名工具处理。\n");
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        [json writeToFile:[build stringByAppendingPathComponent:@"report.json"] atomically:YES];
        fflush(log);
        NSString *text = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil] ?: @"No log";
        fclose(input); fclose(log);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIApplication.sharedApplication.idleTimerDisabled = NO;
            self.console.text = [NSString stringWithFormat:@"%@ · %lu 个源码\n日志与产物已保存，可导出完整文件。", [report[@"success"] boolValue] ? @"构建成功" : @"构建失败", (unsigned long)projectSources.count];
            self.navigationItem.rightBarButtonItem.enabled = YES;
            self.navigationItem.leftBarButtonItem.enabled = YES;
            ((UIBarButtonItem *)self.toolbarItems.firstObject).enabled = YES;
            self.hasBuilt = NO; TMCBuildRunning = NO;
            if (self.buildCompletion) self.buildCompletion([report[@"success"] boolValue]);
        });
    });
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@end
@implementation AppDelegate
- (void)openAIFromNotification:(NSNotification *)note{TMCOpenAIConversation(self.window.rootViewController,note.userInfo[@"sessionID"],note.userInfo[@"projectID"]);}
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {if(url.isFileURL){TFIncomingReceive(self.window.rootViewController,url);return YES;}if(([url.scheme isEqual:@"tweakforge"]||[url.scheme isEqual:@"dylix"])&&[url.host isEqual:@"ai"]){TMCOpenAIConversation(self.window.rootViewController,nil,nil);return YES;}if(([url.scheme isEqual:@"tweakforge"]||[url.scheme isEqual:@"dylix"])&&[url.host isEqual:@"incoming"]){TFIncomingDrain(self.window.rootViewController);return YES;}return NO;}
- (void)applicationDidBecomeActive:(UIApplication *)application {TFIncomingDrain(self.window.rootViewController);}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    TFAIBackgroundRegister();TFAINotificationsRegister();[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(openAIFromNotification:) name:@"TFAIOpenConversation" object:nil];
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"StudioTheme":@1, @"StudioFont":@14, @"StudioSDKVersion":@"16.4", @"StudioDeploymentTarget":@"15.0"}];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.tintColor=[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait){return trait.userInterfaceStyle==UIUserInterfaceStyleDark?[UIColor colorWithRed:.93 green:.77 blue:.52 alpha:1]:[UIColor colorWithRed:.45 green:.30 blue:.10 alpha:1];}];
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    for(NSString *name in @[@"import.log",@"picker-test.json"])[NSFileManager.defaultManager removeItemAtPath:[documents stringByAppendingPathComponent:name] error:nil];
    // Only unreported builds from earlier processes are marked interrupted.
    for(NSString *entry in [NSFileManager.defaultManager contentsOfDirectoryAtPath:documents error:nil])if([entry hasPrefix:@"Build-"]){NSString *path=[documents stringByAppendingPathComponent:entry],*marker=[path stringByAppendingPathComponent:@".build-in-progress.json"],*report=[path stringByAppendingPathComponent:@"report.json"];if([NSFileManager.defaultManager fileExistsAtPath:marker]&&![NSFileManager.defaultManager fileExistsAtPath:report]){NSDictionary *interrupted=@{@"success":@NO,@"commands":@[],@"interrupted":@YES,@"packageError":@"上次构建被系统或应用退出中断，请重新构建。原始日志已保留。"};[[NSJSONSerialization dataWithJSONObject:interrupted options:0 error:nil] writeToFile:report atomically:YES];}}
    BOOL testing = [NSProcessInfo.processInfo.arguments containsObject:@"--self-test"] || [NSProcessInfo.processInfo.arguments containsObject:@"--self-test-project"];
    self.window.rootViewController = testing ? [[TMCNavigationController alloc] initWithRootViewController:[CompilerController new]] : TMCStudioRoot();
#if TARGET_OS_SIMULATOR
    extern UIViewController *TFAIShare114Regression(void);
    extern UIViewController *TFAIWorkspace133Regression(void);
    if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-workspace133-test"])self.window.rootViewController=[[TMCNavigationController alloc]initWithRootViewController:TFAIWorkspace133Regression()];
    extern UIViewController *TFAIRender122Regression(void);
    if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-render122-test"])
        self.window.rootViewController=[[TMCNavigationController alloc]initWithRootViewController:TFAIRender122Regression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-share114-test"])
        self.window.rootViewController=TFAIShare114Regression();
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-audio110-test"])
        self.window.rootViewController=TFAIAudio110Regression();
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-recovery110-test"])
        self.window.rootViewController=TFAIRecovery110Regression();
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-attachments108-test"])
        self.window.rootViewController=TFAIAttachments108Regression();
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-v2-test"])
        self.window.rootViewController=TFAIV2Regression();
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-controls-visual-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TFAIControlsVisualRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-probe-visual-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TFAIProbeVisualRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-chat93-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TFAIChat93Regression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-visual-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TFAIVisualRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-approval-visual-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TFAIApprovalVisualRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--ai-integration-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TFAIIntegrationRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--maintenance-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCMaintenanceRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--storage-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCStorageController()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--settings-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCStudioSettingsRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--git-automation-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCGitAutomationRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--file-actions-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCStudioFileActionsRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--git-ui-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCGitRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--about-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCStudioAboutRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--repair-sheet-test"]||[NSProcessInfo.processInfo.arguments containsObject:@"--repair-confirm-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCStudioRepairRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--project-settings-sheet-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCStudioProjectSettingsRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--diagnostic-jump-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCStudioDiagnosticJumpRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--sdk118-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCStudioSDKRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--build-preferences-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCStudioBuildPreferencesRegression()];
    else if([NSProcessInfo.processInfo.arguments containsObject:@"--editor-layout-test"])
        self.window.rootViewController=[[TMCNavigationController alloc] initWithRootViewController:TMCStudioEditorRegression()];
#endif
    [self.window makeKeyAndVisible];
    NSURL *incoming=options[UIApplicationLaunchOptionsURLKey];if(incoming)dispatch_async(dispatch_get_main_queue(),^{TFIncomingReceive(self.window.rootViewController,incoming);});
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); }
}
