#import "GitDiffView.h"
#import <WebKit/WebKit.h>
#import <git2.h>

static int ReviewHunk(const git_diff_delta *delta,const git_diff_hunk *hunk,void *payload){NSMutableString *patch=(__bridge NSMutableString *)payload;[patch appendString:[[NSString alloc]initWithBytes:hunk->header length:hunk->header_len encoding:NSUTF8StringEncoding]?:@""];return 0;}
static int ReviewLine(const git_diff_delta *delta,const git_diff_hunk *hunk,const git_diff_line *line,void *payload){NSMutableString *patch=(__bridge NSMutableString *)payload;NSString *text=[[NSString alloc]initWithBytes:line->content length:line->content_len encoding:NSUTF8StringEncoding]?:@"";if(line->origin==' '||line->origin=='+'||line->origin=='-')[patch appendFormat:@"%c%@",line->origin,text];else [patch appendString:text];return 0;}
NSString *TFReviewPatch(NSString *before,NSString *after,NSString *path){
 NSString *name=[[path?:@"file" componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];name=[name stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
 NSData *a=[before dataUsingEncoding:NSUTF8StringEncoding]?:NSData.data,*b=[after dataUsingEncoding:NSUTF8StringEncoding]?:NSData.data;NSMutableString *patch=[NSMutableString stringWithFormat:@"diff --git a/%@ b/%@\n--- a/%@\n+++ b/%@\n",name,name,name,name];git_libgit2_init();git_diff_options opts=GIT_DIFF_OPTIONS_INIT;opts.context_lines=3;int result=git_diff_buffers(a.bytes,a.length,name.UTF8String,b.bytes,b.length,name.UTF8String,&opts,NULL,NULL,ReviewHunk,ReviewLine,(__bridge void *)patch);git_libgit2_shutdown();return result<0?@"":patch;
}


// Decode Git's octal UTF-8 path quoting only in patch headers, never in source.
static NSString *DisplayPatchHeader(NSString *line) {
    if (![line hasPrefix:@"diff --git "] && ![line hasPrefix:@"--- "] && ![line hasPrefix:@"+++ "]) return line;
    NSData *input=[line dataUsingEncoding:NSUTF8StringEncoding];
    const unsigned char *bytes=input.bytes; NSMutableData *output=[NSMutableData new];
    for (NSUInteger i=0;i<input.length;i++) {
        unsigned char c=bytes[i];
        if(c==92&&i+3<input.length&&bytes[i+1]>='0'&&bytes[i+1]<='3'&&bytes[i+2]>='0'&&bytes[i+2]<='7'&&bytes[i+3]>='0'&&bytes[i+3]<='7') {
            c=(bytes[i+1]-'0')*64+(bytes[i+2]-'0')*8+(bytes[i+3]-'0'); i+=3;
        }
        [output appendBytes:&c length:1];
    }
    return [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding]?:line;
}
@interface TFGitDiff () <WKNavigationDelegate>
@property WKWebView *web;
@property UIActivityIndicatorView *loading;
@property BOOL loaded;
@end
@implementation TFGitDiff
- (void)viewDidLoad {
    [super viewDidLoad];
    NSInteger theme=[NSUserDefaults.standardUserDefaults integerForKey:@"StudioTheme"];
    self.overrideUserInterfaceStyle=theme==1?UIUserInterfaceStyleDark:theme==2?UIUserInterfaceStyleLight:UIUserInterfaceStyleUnspecified;
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];
    config.websiteDataStore=WKWebsiteDataStore.nonPersistentDataStore;
    self.web=[[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.web.navigationDelegate=self; self.web.translatesAutoresizingMaskIntoConstraints=NO;
    self.web.opaque=NO; self.web.backgroundColor=UIColor.systemBackgroundColor;
    self.web.scrollView.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:self.web];
    [NSLayoutConstraint activateConstraints:@[
        [self.web.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.web.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.web.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];
    self.loading=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loading.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:self.loading];
    [NSLayoutConstraint activateConstraints:@[[self.loading.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[self.loading.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]]];
    [self.loading startAnimating];
    if(self.primary) {
        NSString *symbol=[self.primaryLabel containsString:@"冲突"]?@"arrow.triangle.merge":@"arrow.uturn.backward";
        UIBarButtonItem *action=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:symbol] style:UIBarButtonItemStylePlain target:self action:@selector(apply)];
        action.accessibilityLabel=self.primaryLabel; self.navigationItem.rightBarButtonItem=action;
    }
    NSURL *root=[NSURL fileURLWithPath:NSBundle.mainBundle.resourcePath isDirectory:YES];
    [self.web loadFileURL:[root URLByAppendingPathComponent:@"GitDiff/index.html"] allowingReadAccessToURL:root];
}
- (void)apply { if(self.primary)self.primary(self); }
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {
    NSString *raw=self.content?:@""; NSRange start=[raw rangeOfString:@"diff --git " options:NSAnchoredSearch];
    if(start.location==NSNotFound) { NSRange marker=[raw rangeOfString:@"\ndiff --git "]; if(marker.location!=NSNotFound)start=NSMakeRange(marker.location+1,marker.length-1); }
    NSString *note=start.location!=NSNotFound?[raw substringToIndex:start.location]:raw;
    NSString *patch=start.location!=NSNotFound?[raw substringFromIndex:start.location]:@"";
    NSMutableArray *lines=[NSMutableArray new]; BOOL inHunk=NO;
    for(NSString *line in [patch componentsSeparatedByString:@"\n"]) {
        if([line hasPrefix:@"diff --git "])inHunk=NO;
        if([line hasPrefix:@"@@ "])inHunk=YES;
        [lines addObject:inHunk?line:DisplayPatchHeader(line)];
    }
    NSMutableDictionary *payload=[@{@"patch":[lines componentsJoinedByString:@"\n"],@"note":note,@"title":self.title?:@"差异审阅",@"compact":@(self.compact),@"dark":@(self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark)} mutableCopy];
    if(self.conflict)payload[@"conflict"]=self.conflict;
    NSData *data=[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *json=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [web evaluateJavaScript:[NSString stringWithFormat:@"window.renderDiff(%@)",json?:@"{}"] completionHandler:^(id result,NSError *error){
        [self.loading stopAnimating]; self.loaded=!error;
        if(!error&&self.compact){[web evaluateJavaScript:@"document.documentElement.scrollHeight" completionHandler:^(id height,NSError *e){if(!e&&self.contentHeightChanged)self.contentHeightChanged([height doubleValue]);}];}
#if TARGET_OS_SIMULATOR
        if(!error&&self.compact&&[NSProcessInfo.processInfo.arguments containsObject:@"--ai-approval-visual-test"]){[web evaluateJavaScript:@"({ready:document.body.dataset.ready,compact:document.body.classList.contains(\"compact\"),files:document.querySelectorAll(\".d2h-file-wrapper\").length,syntax:document.querySelectorAll(\".hljs-keyword,.hljs-type,.hljs-attr\").length,lineNumbers:document.querySelectorAll(\".line-num1,.line-num2\").length,changes:document.querySelectorAll(\"td.d2h-ins,td.d2h-del\").length,wordChanges:document.querySelectorAll(\"ins,del\").length})" completionHandler:^(id metrics,NSError *e){if([metrics isKindOfClass:NSDictionary.class]){NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;NSString *name=[NSString stringWithFormat:@"ai-approval-diff-%@.json",[self.title stringByReplacingOccurrencesOfString:@"/" withString:@"_"]];[[NSJSONSerialization dataWithJSONObject:metrics options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[docs stringByAppendingPathComponent:name] atomically:YES];}}];}
#endif
#if TARGET_OS_SIMULATOR
        if(!error&&[NSProcessInfo.processInfo.arguments containsObject:@"--git-diff-test"]) {
            [web evaluateJavaScript:@"({ready:document.body.dataset.ready,files:document.querySelectorAll('.d2h-file-wrapper').length,stats:document.getElementById('stats').innerText,syntax:document.querySelectorAll('.hljs-keyword').length,wordChanges:document.querySelectorAll('ins,del').length,lineNumbers:document.querySelectorAll('.line-num1,.line-num2').length,localPage:location.protocol==='file:'})" completionHandler:^(id result,NSError *testError){
                if([result isKindOfClass:NSDictionary.class]) {
                    NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
                    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[docs stringByAppendingPathComponent:@"git-diff-ui-test.json"] atomically:YES];
                }
            }];
        }
#endif

        if(error){UILabel *label=[UILabel new];label.text=@"差异预览加载失败，请返回后重试。";label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];label.numberOfLines=0;label.frame=CGRectInset(self.view.bounds,24,80);[self.view addSubview:label];}
    }];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(self.loaded)[self.web evaluateJavaScript:self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark?@"document.documentElement.dataset.theme='dark'":@"document.documentElement.dataset.theme='light'" completionHandler:nil];
}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decision {
    // Source text and file names never become external navigation.
    NSURL *url=action.request.URL;
    NSString *root=[NSBundle.mainBundle.resourcePath stringByAppendingString:@"/"];
    decision(url.isFileURL&&[url.path hasPrefix:root]?WKNavigationActionPolicyAllow:WKNavigationActionPolicyCancel);
}
@end
