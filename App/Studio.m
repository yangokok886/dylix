#import "StorageSpace.h"
#import "SDKResources.h"
#import "AI/ClassDump/TFAIClassDump.h"
#import "AI/Attachments/TFAIArtifactInspection.h"
#import "ProjectTrash.h"
#import "RuntimeDiagnostics.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Studio.h"
#import "AI/AIContracts.h"
#import "AI/AIV2Contracts.h"
#import "AI/UI/AIUI.h"
#import "CompilerController.h"
#import "OutputNaming.h"
#import "CompatibilityRepair.h"
#import "GitUI.h"
#import "LinkSupport.h"
#import "HelpArticle.h"
#import "GitPreferences.h"
#import "GitAutomation.h"
#import "GitService.h"
#import "ProjectSafety.h"
#import "GlassSupport.h"
#import "../Vendor/MBProgressHUD/MBProgressHUD.h"
#import <objc/message.h>
#import <sys/utsname.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <objc/runtime.h>
#import "Incoming/TFIncoming.h"

extern void TFAIFlushOpenSession(NSString *,NSString *);
static void OpenAISession(UINavigationController *,NSDictionary *,id);
static void AssociateAISession(UINavigationController *,NSDictionary *,NSDictionary *);
static UIColor *Gold(void) { return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t){return t.userInterfaceStyle==UIUserInterfaceStyleDark?[UIColor colorWithRed:.93 green:.77 blue:.52 alpha:1]:[UIColor colorWithRed:.43 green:.31 blue:.13 alpha:1];}]; }
static NSString *Docs(void) { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject; }
static NSString *Projects(void) { NSString *p=[Docs() stringByAppendingPathComponent:@"Projects"]; [NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil]; return p; }
static NSDictionary *Config(NSString *p) { id v=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[p stringByAppendingPathComponent:@"MobileCompiler.json"]] ?: [NSData data] options:0 error:nil]; return [v isKindOfClass:NSDictionary.class]?v:@{}; }
static BOOL NameOK(NSString *n);
static NSString *Child(NSString *root, NSString *relative);
static NSString *ValidateProjectOptions(NSString *root, BOOL checkSources) {
    NSString *manifest=[root stringByAppendingPathComponent:@"MobileCompiler.json"];
    if (![NSFileManager.defaultManager fileExistsAtPath:manifest]) return nil;
    NSError *error=nil; id c=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:manifest] ?: [NSData data] options:0 error:&error];
    if (![c isKindOfClass:NSDictionary.class]) return error.localizedDescription ?: @"MobileCompiler.json 应为 JSON 对象";
    for (NSString *key in @[@"packageSchemes",@"sources",@"includeDirectories",@"defines",@"warningFlags",@"frameworks",@"libraries",@"forcedIncludes"]) {
        id value=c[key]; if (!value) continue;
        if (![value isKindOfClass:NSArray.class]) return [key stringByAppendingString:@" 应为数组"];
        for (id item in value) if (![item isKindOfClass:NSString.class]) return [key stringByAppendingString:@" 只能包含字符串"];
    }
    for (NSString *key in @[@"name",@"productName",@"prefixHeader",@"optimization",@"logosGenerator",@"sdkVersion",@"deploymentTarget",@"cxxStandard",@"cStandard",@"outputPattern-deb",@"outputPattern-dylib"]) if(c[key] && ![c[key] isKindOfClass:NSString.class]) return [key stringByAppendingString:@" 应为字符串"];
    if(c[@"packageSchemes"]&&![c[@"packageSchemes"] count])return @"packageSchemes 至少选择一项";
    for(NSString *scheme in c[@"packageSchemes"])if(![@[@"rootless",@"rootful",@"roothide"] containsObject:scheme])return @"包类型无效";
    if(c[@"name"] && !NameOK(c[@"name"])) return @"项目名称不应包含路径字符";
    for (NSString *key in @[@"package",@"exportDylib",@"collectErrors",@"objcArc"]) if(c[key] && ![c[key] isKindOfClass:NSNumber.class]) return [key stringByAppendingString:@" 应为布尔值"];
    if(checkSources)for (NSString *f in c[@"sources"]) {
        NSString *path=Child(root,f); BOOL dir=NO;
        if (!path || ![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&dir] || dir) return [@"源码路径不存在或超出工程：" stringByAppendingString:f];
        if (![@[@"x",@"m",@"mm",@"xm",@"c",@"cpp"] containsObject:f.pathExtension.lowercaseString]) return [@"尚未支持的源码类型：" stringByAppendingString:f];
    }
    return nil;
}
static NSString *ValidateProject(NSString *root){return ValidateProjectOptions(root,YES);}
static BOOL JSONWrite(NSDictionary *d, NSString *path, NSError **error) { NSData *data=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:error]; return data && [data writeToFile:path options:NSDataWritingAtomic error:error]; }
static BOOL NameOK(NSString *n) { return n.length && n.length<100 && ![n containsString:@"/"] && ![n containsString:@"\\"] && ![n isEqual:@"."] && ![n isEqual:@".."] && [n rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound; }
static NSString *Child(NSString *root, NSString *relative) { if (relative.isAbsolutePath) return nil; NSString *base=root.stringByResolvingSymlinksInPath; NSString *p=[root stringByAppendingPathComponent:relative].stringByResolvingSymlinksInPath; return [p hasPrefix:[base stringByAppendingString:@"/"]]?p:nil; }
static NSString *ControlName(NSString *root){NSString *text=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"control"] encoding:NSUTF8StringEncoding error:nil];for(NSString *line in [text componentsSeparatedByString:@"\n"]){if([line hasPrefix:@"Name:"]){NSString *name=[[line substringFromIndex:5] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(name.length)return name;}}return nil;}
static NSString *ProjectName(NSString *p) { NSString *control=ControlName(p);if(control)return control;id n=Config(p)[@"name"]; return [n isKindOfClass:NSString.class]?n:[p.lastPathComponent hasPrefix:@"Imported-"]?@"导入工程":p.lastPathComponent; }
static void Message(UIViewController *vc, NSString *title, NSString *text) { UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]]; [vc presentViewController:a animated:YES completion:nil]; }
@interface TMCBlankKeyboardDismiss : NSObject <UIGestureRecognizerDelegate>
@end
@implementation TMCBlankKeyboardDismiss
+ (instancetype)shared{static TMCBlankKeyboardDismiss *value;static dispatch_once_t once;dispatch_once(&once,^{value=[TMCBlankKeyboardDismiss new];});return value;}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch{UIResponder *responder=gesture.view;while(responder){if([responder isKindOfClass:NSClassFromString(@"StudioEditor")])return NO;responder=responder.nextResponder;}for(UIView *v=touch.view;v;v=v.superview){if([v isKindOfClass:UITextView.class]){UITextView *text=(id)v;if(!text.isFirstResponder)return NO;CGRect used=[text.layoutManager usedRectForTextContainer:text.textContainer];CGPoint point=[touch locationInView:text];return point.y>CGRectGetMaxY(used)+text.textContainerInset.top+18;}if([v isKindOfClass:UIControl.class])return NO;}return YES;}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b{return YES;}
- (void)tap:(UITapGestureRecognizer *)gesture{[gesture.view endEditing:YES];}
@end
static void ApplyTheme(UIViewController *vc) { if(![NSStringFromClass(vc.class) isEqual:@"StudioEditor"]){BOOL installed=NO;for(UIGestureRecognizer *gesture in vc.view.gestureRecognizers)if([gesture.name isEqual:@"TMCBlankKeyboardDismiss"])installed=YES;if(!installed){TMCBlankKeyboardDismiss *handler=[TMCBlankKeyboardDismiss shared];UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:handler action:@selector(tap:)];tap.name=@"TMCBlankKeyboardDismiss";tap.delegate=handler;tap.cancelsTouchesInView=NO;[vc.view addGestureRecognizer:tap];}}NSInteger t=[NSUserDefaults.standardUserDefaults integerForKey:@"StudioTheme"]; UIUserInterfaceStyle style=t==1?UIUserInterfaceStyleDark:t==2?UIUserInterfaceStyleLight:UIUserInterfaceStyleUnspecified;vc.view.window.overrideUserInterfaceStyle=style;if(vc.overrideUserInterfaceStyle!=style)vc.overrideUserInterfaceStyle=style;if(vc.navigationController.overrideUserInterfaceStyle!=style)vc.navigationController.overrideUserInterfaceStyle=style; }
static UILabel *Label(NSString *t, CGFloat size, BOOL bold) { UILabel *l=[UILabel new]; l.text=t; l.font=[UIFont systemFontOfSize:size weight:bold?UIFontWeightSemibold:UIFontWeightRegular]; l.numberOfLines=0; return l; }
static UIButton *Button(NSString *t, NSString *symbol, id target, SEL action, BOOL primary) { UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; UIButtonConfiguration *c=TMCButtonConfiguration(primary); c.title=t; c.image=[UIImage systemImageNamed:symbol]; c.imagePadding=10; c.cornerStyle=UIButtonConfigurationCornerStyleLarge; c.contentInsets=NSDirectionalEdgeInsetsMake(17,18,17,18); c.baseBackgroundColor=primary?Gold():UIColor.secondarySystemBackgroundColor; c.baseForegroundColor=primary?[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t){return t.userInterfaceStyle==UIUserInterfaceStyleDark?UIColor.blackColor:UIColor.whiteColor;}]:UIColor.labelColor; b.configuration=c; [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside]; return b; }
static UIStackView *Stack(UIView *parent) { UIStackView *s=[UIStackView new]; s.axis=UILayoutConstraintAxisVertical;s.spacing=16;s.translatesAutoresizingMaskIntoConstraints=NO;[parent addSubview:s]; return s; }
static UIVisualEffectView *Glass(void) {UIVisualEffect *effect=TMCGlassEffect(NO);UIVisualEffectView *v=[[UIVisualEffectView alloc] initWithEffect:effect];v.layer.cornerRadius=22;v.clipsToBounds=YES;if(!effect)v.backgroundColor=UIColor.secondarySystemBackgroundColor;return v;}
static void RecordRecent(NSString *p) { NSMutableArray *a=[[NSUserDefaults.standardUserDefaults arrayForKey:@"StudioRecent"] mutableCopy]?:[NSMutableArray new];[a removeObject:p.lastPathComponent];[a insertObject:p.lastPathComponent atIndex:0];if(a.count>20)[a removeObjectsInRange:NSMakeRange(20,a.count-20)];[NSUserDefaults.standardUserDefaults setObject:a forKey:@"StudioRecent"]; }

static void MarkSaved(NSString *root) { [[TMCGitAutomation shared] saved:root]; JSONWrite(@{@"lastSaved":@(NSDate.date.timeIntervalSince1970)},[root stringByAppendingPathComponent:@".studio-state.json"],nil); }
static NSDate *LastSaved(NSString *root,NSUInteger *count) {
 NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".studio-state.json"]];NSDictionary *state=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;id stamp=[state isKindOfClass:NSDictionary.class]?state[@"lastSaved"]:nil;
 NSDate *latest=[stamp isKindOfClass:NSNumber.class]?[NSDate dateWithTimeIntervalSince1970:[stamp doubleValue]]:nil;NSDirectoryEnumerator *e=[NSFileManager.defaultManager enumeratorAtPath:root];for(NSString *name in e){if([name.lastPathComponent hasPrefix:@"."]){[e skipDescendants];continue;}NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:[root stringByAppendingPathComponent:name] error:nil];if([a[NSFileType] isEqual:NSFileTypeSymbolicLink]){[e skipDescendants];continue;}if([a[NSFileType] isEqual:NSFileTypeDirectory])continue;if(count)(*count)++;NSDate *date=a[NSFileModificationDate];if(date&&(!latest||[date compare:latest]==NSOrderedDescending))latest=date;}return latest;
}
// Clang columns count UTF-8 bytes; UITextView positions count UTF-16 units.
static NSUInteger DiagnosticOffset(NSString *text,NSUInteger line,NSUInteger column) {
 NSUInteger row=1,at=0;while(at<text.length&&row<line)if([text characterAtIndex:at++]=='\n')row++;
 NSUInteger remaining=column>0?column-1:0;while(at<text.length&&remaining&&[text characterAtIndex:at]!='\n'){unichar c=[text characterAtIndex:at];NSUInteger width=1,bytes=c<0x80?1:c<0x800?2:3;if(CFStringIsSurrogateHighCharacter(c)&&at+1<text.length&&CFStringIsSurrogateLowCharacter([text characterAtIndex:at+1])){width=2;bytes=4;}if(remaining<bytes)break;remaining-=bytes;at+=width;}return at;
}
static NSString *SavedTimeLabel(NSDate *date,NSDate *now) {
 if(!date)return @"暂无记录";NSTimeInterval age=[now timeIntervalSinceDate:date];
 if(age<0){NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"MM-dd HH:mm";return [f stringFromDate:date];}
 if(age<60)return @"刚刚";
 if(age<3600)return [NSString stringWithFormat:@"%ld分钟前",(long)floor(age/60)];
 if(age<86400)return [NSString stringWithFormat:@"%ld小时前",(long)floor(age/3600)];
 NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=[NSCalendar.currentCalendar isDate:date equalToDate:now toUnitGranularity:NSCalendarUnitYear]?@"MM-dd HH:mm":@"yyyy-MM-dd HH:mm";return [f stringFromDate:date];
}
static void SyntaxTokens(NSString *text,NSString *language,BOOL (^current)(void),void (^completion)(NSArray *)) {
 static dispatch_queue_t queue;static dispatch_once_t once;dispatch_once(&once,^{queue=dispatch_queue_create("studio.syntax",DISPATCH_QUEUE_SERIAL);});
 dispatch_async(queue,^{@autoreleasepool{if(!current())return;static NSCache *cache; if(!cache){cache=[NSCache new];cache.totalCostLimit=8*1024*1024;}NSArray *key=@[language,text];NSArray *cached=[cache objectForKey:key];if(cached){dispatch_async(dispatch_get_main_queue(),^{completion(cached);});return;}static JSContext *context;if(!context){context=[JSContext new];NSString *dir=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Editor"];[context evaluateScript:[NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"highlight-11.11.1.min.js"] encoding:NSUTF8StringEncoding error:nil]?:@""];[context evaluateScript:[NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"tokenize.js"] encoding:NSUTF8StringEncoding error:nil]?:@""];}
 context.exception=nil;JSValue *result=[context[@"studioTokens"] callWithArguments:@[text,language]];NSArray *tokens=context.exception?nil:result.toArray;if(tokens)[cache setObject:tokens forKey:key cost:text.length*2+tokens.count*64];dispatch_async(dispatch_get_main_queue(),^{completion(tokens?:@[]);});}});
}

static void RenderBuildLog(UITextView *view, NSString *value, BOOL tail) {
 if(!view||[view.text isEqualToString:value])return;
 NSMutableAttributedString *text=[[NSMutableAttributedString alloc] initWithString:value?:@"" attributes:@{NSFontAttributeName:[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular],NSForegroundColorAttributeName:UIColor.labelColor}];
 [value enumerateSubstringsInRange:NSMakeRange(0,value.length) options:NSStringEnumerationByLines usingBlock:^(NSString *line,NSRange range,NSRange enclosing,BOOL *stop){UIColor *color=nil;if([line containsString:@"BUILD SUCCEEDED"]||[line containsString:@"构建成功"]||[line containsString:@"生成文件："])color=UIColor.systemGreenColor;else if([line containsString:@"BUILD FAILED"]||[line containsString:@"构建失败"]||[line containsString:@"error:"])color=UIColor.systemRedColor;else if([line containsString:@"warning:"])color=UIColor.systemOrangeColor;else if([line hasPrefix:@"["])color=UIColor.secondaryLabelColor;if(color)[text addAttribute:NSForegroundColorAttributeName value:color range:range];if([line containsString:@"构建成功"]||[line containsString:@"构建失败"]||[line containsString:@"生成文件："]||[line containsString:@"签名状态："])[text addAttribute:NSFontAttributeName value:[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightSemibold] range:range];}];
 BOOL nearBottom=view.contentSize.height-view.contentOffset.y-view.bounds.size.height<80;TMCEnableTextLinks(view);CGPoint offset=view.contentOffset;view.attributedText=text;if(tail&&nearBottom&&text.length)[view scrollRangeToVisible:NSMakeRange(text.length-1,1)];else [view setContentOffset:offset animated:NO];
}

// Animate only the log panel. The source editor keeps its bounds, scale and
// TextKit geometry throughout presentation and dismissal.
@interface TMCLogPresentation : UIPresentationController
@property UIView *shade;
@property BOOL expanded;
@property CGFloat panStartY;
@end
@implementation TMCLogPresentation
- (CGRect)frameOfPresentedViewInContainerView{CGRect bounds=self.containerView.bounds;CGFloat top=self.expanded?self.containerView.safeAreaInsets.top+12:bounds.size.height*.42;CGFloat width=MIN(bounds.size.width,760);return CGRectMake((bounds.size.width-width)/2,top,width,bounds.size.height-top);}
- (void)presentationTransitionWillBegin{self.shade=[[UIView alloc] initWithFrame:self.containerView.bounds];self.shade.backgroundColor=[UIColor colorWithWhite:0 alpha:.22];self.shade.alpha=0;self.shade.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self.shade addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)]];[self.containerView insertSubview:self.shade atIndex:0];[self.presentedViewController.transitionCoordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context){self.shade.alpha=1;} completion:nil];
 self.presentedView.layer.cornerRadius=22;self.presentedView.layer.maskedCorners=kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner;self.presentedView.clipsToBounds=YES;
 UINavigationController *nav=(UINavigationController *)self.presentedViewController;[nav.navigationBar addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
}
- (void)containerViewWillLayoutSubviews{self.presentedView.frame=self.frameOfPresentedViewInContainerView;self.shade.frame=self.containerView.bounds;}
- (void)dismissalTransitionWillBegin{[self.presentedViewController.transitionCoordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context){self.shade.alpha=0;} completion:nil];}
- (void)dismissalTransitionDidEnd:(BOOL)completed{if(completed)[self.shade removeFromSuperview];}
- (void)close{[self.presentedViewController dismissViewControllerAnimated:YES completion:nil];}
- (void)pan:(UIPanGestureRecognizer *)gesture{CGFloat delta=[gesture translationInView:self.containerView].y;if(gesture.state==UIGestureRecognizerStateBegan)self.panStartY=self.presentedView.frame.origin.y;if(gesture.state==UIGestureRecognizerStateChanged){CGRect f=self.presentedView.frame;f.origin.y=MAX(self.containerView.safeAreaInsets.top+12,self.panStartY+delta);f.size.height=self.containerView.bounds.size.height-f.origin.y;self.presentedView.frame=f;}if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled){if(delta>120){[self close];return;}if(delta < -50)self.expanded=YES;else if(delta>50)self.expanded=NO;[UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled()?0:.22 animations:^{self.presentedView.frame=self.frameOfPresentedViewInContainerView;}];}}
@end
@interface TMCLogAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@property BOOL presenting;
@end
@implementation TMCLogAnimator
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context{return UIAccessibilityIsReduceMotionEnabled()?0:.25;}
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context{UIViewController *controller=[context viewControllerForKey:self.presenting?UITransitionContextToViewControllerKey:UITransitionContextFromViewControllerKey];UIView *view=controller.view;CGRect frame=[context finalFrameForViewController:controller];if(self.presenting){view.frame=frame;[context.containerView addSubview:view];view.transform=CGAffineTransformMakeTranslation(0,context.containerView.bounds.size.height-frame.origin.y);} [UIView animateWithDuration:[self transitionDuration:context] delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{view.transform=self.presenting?CGAffineTransformIdentity:CGAffineTransformMakeTranslation(0,context.containerView.bounds.size.height-view.frame.origin.y);} completion:^(BOOL finished){[context completeTransition:!context.transitionWasCancelled];}];}
@end
@interface TMCLogTransition : NSObject <UIViewControllerTransitioningDelegate>
@end
@implementation TMCLogTransition
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source{return [[TMCLogPresentation alloc] initWithPresentedViewController:presented presentingViewController:presenting];}
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source{TMCLogAnimator *a=[TMCLogAnimator new];a.presenting=YES;return a;}
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed{TMCLogAnimator *a=[TMCLogAnimator new];return a;}
@end

@interface StudioText : UIViewController <UITextViewDelegate>
@property UITextView *text;
@property NSString *content;
@property BOOL logMode;
@property UISegmentedControl *filter;
@property UIButton *bottom;
- (void)updateLog:(NSString *)value;
@end
@implementation StudioText
- (void)viewDidLoad {
 [super viewDidLoad];ApplyTheme(self);self.view.backgroundColor=UIColor.systemBackgroundColor;
 self.text=[UITextView new];self.text.editable=NO;self.text.selectable=YES;self.text.delegate=self;TMCEnableTextLinks(self.text);self.text.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];self.text.text=self.content;self.text.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.text];
 UILongPressGestureRecognizer *copy=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(copyLog:)];[self.text addGestureRecognizer:copy];
 NSLayoutYAxisAnchor *top=self.view.safeAreaLayoutGuide.topAnchor;
 if(self.logMode){self.filter=[[UISegmentedControl alloc] initWithItems:@[@"全部",@"错误",@"警告"]];self.filter.selectedSegmentIndex=0;self.filter.translatesAutoresizingMaskIntoConstraints=NO;[self.filter addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];[self.view addSubview:self.filter];[NSLayoutConstraint activateConstraints:@[[self.filter.topAnchor constraintEqualToAnchor:top constant:8],[self.filter.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],[self.filter.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],[self.filter.heightAnchor constraintGreaterThanOrEqualToConstant:36]]];top=self.filter.bottomAnchor;
 self.bottom=Button(@"回到底部",@"arrow.down",self,@selector(toBottom),NO);self.bottom.hidden=YES;self.bottom.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.bottom];[NSLayoutConstraint activateConstraints:@[[self.bottom.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],[self.bottom.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],[self.bottom.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];}
 [NSLayoutConstraint activateConstraints:@[[self.text.topAnchor constraintEqualToAnchor:top constant:6],[self.text.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.text.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.text.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];[self.view bringSubviewToFront:self.bottom?:self.text];
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
}
- (void)updateLog:(NSString *)value{self.content=value?:@"";NSString *display=self.content;NSInteger mode=self.filter.selectedSegmentIndex;if(mode>0){NSMutableArray *lines=[NSMutableArray new];NSInteger context=0;for(NSString *line in [display componentsSeparatedByString:@"\n"]){BOOL match=mode==1?([line containsString:@"error:"]||[line containsString:@"构建失败"]||[line containsString:@"BUILD FAILED"]||[line containsString:@"package error"]):[line containsString:@"warning:"];if(match)context=3;if(context>0){[lines addObject:line];context--;}}display=lines.count?[lines componentsJoinedByString:@"\n"]:@"当前没有匹配的诊断";}RenderBuildLog(self.text,display,YES);[self scrollViewDidScroll:self.text];}
- (void)filterChanged{self.text.text=@"";[self updateLog:self.content];}
- (void)toBottom{if(self.text.text.length)[self.text scrollRangeToVisible:NSMakeRange(self.text.text.length-1,1)];self.bottom.hidden=YES;}
- (void)scrollViewDidScroll:(UIScrollView *)scroll{self.bottom.hidden=scroll.contentSize.height-scroll.contentOffset.y-scroll.bounds.size.height<80;}
- (void)copyLog:(UILongPressGestureRecognizer *)gesture{if(gesture.state!=UIGestureRecognizerStateBegan)return;UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"日志" message:nil preferredStyle:UIAlertControllerStyleActionSheet];[sheet addAction:[UIAlertAction actionWithTitle:@"复制全部日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){UIPasteboard.generalPasteboard.string=self.text.text?:@"";}]];[sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];sheet.popoverPresentationController.sourceView=self.text;sheet.popoverPresentationController.sourceRect=CGRectMake(self.text.bounds.size.width/2,self.text.bounds.size.height/2,1,1);[self presentViewController:sheet animated:YES completion:nil];}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@interface StudioValueEditor : UIViewController
@property NSString *value;
@property NSString *helpText;
@property UITextView *input;
@property(copy) void (^completion)(NSString *);
@end
@implementation StudioValueEditor
- (void)viewDidLoad{[super viewDidLoad];ApplyTheme(self);self.view.backgroundColor=UIColor.systemBackgroundColor;self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];UILabel *help=Label(self.helpText?:@"编辑后点完成，校验通过即自动保存。",12,NO);help.numberOfLines=0;help.textColor=UIColor.secondaryLabelColor;self.input=[UITextView new];self.input.text=self.value;self.input.font=[UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];self.input.autocapitalizationType=UITextAutocapitalizationTypeNone;self.input.autocorrectionType=UITextAutocorrectionTypeNo;self.input.smartQuotesType=UITextSmartQuotesTypeNo;self.input.accessibilityLabel=self.title;self.input.backgroundColor=UIColor.secondarySystemBackgroundColor;self.input.layer.cornerRadius=12;self.input.layer.borderWidth=1;self.input.layer.borderColor=UIColor.separatorColor.CGColor;self.input.textContainerInset=UIEdgeInsetsMake(14,12,14,12);for(UIView *v in @[help,self.input]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:v];}[NSLayoutConstraint activateConstraints:@[[help.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],[help.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],[help.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],[self.input.topAnchor constraintEqualToAnchor:help.bottomAnchor constant:12],[self.input.leadingAnchor constraintEqualToAnchor:help.leadingAnchor],[self.input.trailingAnchor constraintEqualToAnchor:help.trailingAnchor],[self.input.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-12]]];}
- (void)cancel{[self dismissViewControllerAnimated:YES completion:nil];}
- (void)done{NSString *value=self.input.text?:@"";void (^completion)(NSString *)=self.completion;[self dismissViewControllerAnimated:YES completion:^{if(completion)completion(value);}];}
@end


// Shared global defaults / per-project overrides. Legacy explicit project values remain overrides.
@interface StudioBuildPreferences : UITableViewController
@property NSString *root;
@property BOOL exportDylib;
@property BOOL exportDeb;
@property BOOL inheritOutput;
@property BOOL inheritSchemes;
@property NSArray<UISwitch *> *schemeSwitches;
@property NSArray<UITextField *> *patterns;
@property NSArray<UILabel *> *previews;
@property NSDictionary *original;
@property NSDate *previewDate;
@property NSMutableDictionary<NSIndexPath *, UITableViewCell *> *settingCells;
@property NSDictionary *acceptedState;
@end
@implementation StudioBuildPreferences
- (void)viewDidLoad{[super viewDidLoad];self.settingCells=[NSMutableDictionary new];ApplyTheme(self);self.title=self.root?@"项目构建设置":@"默认构建设置";self.previewDate=NSDate.date;self.original=self.root?Config(self.root):@{};NSDictionary *effective=TMCEffectiveBuildOptions(self.original,NSUserDefaults.standardUserDefaults);self.exportDeb=[effective[@"package"] boolValue];self.exportDylib=[effective[@"exportDylib"] boolValue];self.inheritOutput=self.root&&!self.original[@"package"]&&!self.original[@"exportDylib"];self.inheritSchemes=self.root&&!self.original[@"packageSchemes"]&&!self.original[@"packageScheme"];
 NSMutableArray *toggles=[NSMutableArray new];for(NSString *scheme in @[@"rootless",@"rootful",@"roothide"]){UISwitch *toggle=[UISwitch new];toggle.accessibilityLabel=[@"构建包类型 " stringByAppendingString:scheme];toggle.on=self.exportDeb&&[effective[@"packageSchemes"] containsObject:scheme];toggle.enabled=self.exportDeb;[toggle addTarget:self action:@selector(schemeChanged) forControlEvents:UIControlEventValueChanged];[toggles addObject:toggle];}self.schemeSwitches=toggles;
 NSMutableArray *fields=[NSMutableArray new],*previews=[NSMutableArray new];for(NSString *ext in @[@"deb",@"dylib"]){UITextField *field=[UITextField new];NSString *key=[@"outputPattern-" stringByAppendingString:ext];field.accessibilityLabel=[ext stringByAppendingString:@" 产物昵称或文件名模板"];field.text=self.root?self.original[key]:effective[key];if([ext isEqual:@"deb"]&&[field.text isEqual:@"{name}_{version}_{architecture}"])field.text=TMCDefaultOutputPattern(ext);field.placeholder=self.root?[@"跟随全局：" stringByAppendingString:TMCEffectiveBuildOptions(@{},NSUserDefaults.standardUserDefaults)[key]]:TMCDefaultOutputPattern(ext);field.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];field.autocapitalizationType=UITextAutocapitalizationTypeNone;field.autocorrectionType=UITextAutocorrectionTypeNo;field.clearButtonMode=UITextFieldViewModeWhileEditing;[field addTarget:self action:@selector(updatePreviews) forControlEvents:UIControlEventEditingChanged];[fields addObject:field];UILabel *preview=Label(@"",11,NO);preview.numberOfLines=0;[previews addObject:preview];}self.patterns=fields;self.previews=previews;[self updatePreviews];self.acceptedState=[self preferenceState];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table{return 4;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return section==1?(self.root?3:2):section==2?(self.root?4:3):section==3?2:2;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section{return @[@"SDK 与兼容系统",@"构建产物",@"DEB 类型 · 可多选",@"自定义产物昵称 / 文件名模板"][section];}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section{if(section==0)return @"SDK 决定可使用的接口；最低系统版本决定产物运行要求。选择后自动保存。新 API 请用 @available 判断。最低支持 iOS 15.0；SDK 26 的 C++ 使用 Clang 14 兼容标准库头文件。";return section==1?@"dylib 是可单独导出的动态库；deb 是包含动态库的安装包。至少选择一项。":section==2?@"开启 deb 后启用包类型，首次开启默认无根。可同时构建多种包。":section==3?(self.root?@"留空跟随全局。预览使用本项目元数据和本次打开设置的时间。支持 {name}、{product}、{version}、{platform}（iphoneos）、{packageArch}（arm / arm64 / arm64e）、{scheme}（rootless / rootful / roothide）、{arch}（CPU）、{date}、{time}、{package}、{author}。{architecture} 保留兼容旧模板。自动添加扩展名；DEB 重名时追加编号；独立 dylib 仅导出一个（首个所选包类型）。":@"预览使用示例项目“我的插件 / MyTweak / 1.2.3”。支持 {name}、{product}、{version}、{platform}（iphoneos）、{packageArch}（arm / arm64 / arm64e）、{scheme}（rootless / rootful / roothide）、{arch}（CPU）、{date}、{time}、{package}、{author}。{architecture} 保留兼容旧模板。自动添加扩展名；DEB 重名时追加编号；独立 dylib 仅导出一个（首个所选包类型）。"):nil;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index{UITableViewCell *cached=self.settingCells[index];if(cached)return cached;UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];self.settingCells[index]=cell;cell.textLabel.font=[UIFont systemFontOfSize:13];cell.detailTextLabel.numberOfLines=0;
 if(index.section==0){NSString *key=index.row?@"deploymentTarget":@"sdkVersion";NSDictionary *config=self.root?Config(self.root):@{};NSError *error=nil;NSDictionary *effective=TMCSDKBuildSettings(config,NSUserDefaults.standardUserDefaults,&error);NSString *value=effective[key]?:@"配置有误";BOOL inherit=self.root&&!config[key];cell.textLabel.text=[NSString stringWithFormat:@"%@：%@%@",index.row?@"最低系统":@"编译 SDK",inherit?@"跟随全局 · ":@"",value];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
 if(index.section==1){if(self.root&&index.row==0){cell.textLabel.text=@"输出跟随全局";cell.accessoryType=self.inheritOutput?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;}else{NSUInteger row=index.row-(self.root?1:0);cell.textLabel.text=row?@"Debian 包 (.deb)":@"动态库 (.dylib)";UISwitch *toggle=[UISwitch new];toggle.on=row?self.exportDeb:self.exportDylib;toggle.tag=row;toggle.accessibilityLabel=cell.textLabel.text;[toggle addTarget:self action:@selector(outputChanged:) forControlEvents:UIControlEventValueChanged];[self installSwitch:toggle inCell:cell];cell.selectionStyle=UITableViewCellSelectionStyleNone;}}
 if(index.section==2){if(self.root&&index.row==0){cell.textLabel.text=@"包类型跟随全局";cell.accessoryType=self.inheritSchemes?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;cell.userInteractionEnabled=self.exportDeb;cell.textLabel.enabled=self.exportDeb;}else{NSUInteger row=index.row-(self.root?1:0);cell.textLabel.text=@[@"无根 · iphoneos-arm64",@"有根 · iphoneos-arm",@"隐根 · iphoneos-arm64e"][row];cell.textLabel.enabled=self.exportDeb;[self installSwitch:self.schemeSwitches[row] inCell:cell];}}
 if(index.section==3){
 UILabel *label=Label(index.row?@"动态库 (.dylib)":@"Debian 包 (.deb)",13,YES);
 UIControl *box=[UIControl new];box.tag=index.row;[box addTarget:self action:@selector(editPattern:) forControlEvents:UIControlEventTouchUpInside];box.isAccessibilityElement=YES;box.accessibilityLabel=label.text;box.accessibilityValue=self.patterns[index.row].text;box.accessibilityHint=@"轻点打开半窗编辑";box.accessibilityTraits=UIAccessibilityTraitButton;box.backgroundColor=UIColor.tertiarySystemFillColor;box.layer.cornerRadius=11;box.layer.borderWidth=1;box.layer.borderColor=UIColor.separatorColor.CGColor;
 UILabel *summary=Label(self.patterns[index.row].text.length?self.patterns[index.row].text:self.patterns[index.row].placeholder,14,NO);summary.font=[UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];summary.numberOfLines=2;summary.lineBreakMode=NSLineBreakByTruncatingTail;summary.textColor=self.patterns[index.row].text.length?UIColor.labelColor:UIColor.secondaryLabelColor;summary.translatesAutoresizingMaskIntoConstraints=NO;[box addSubview:summary];
 UIImageView *pencil=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"pencil"]];pencil.tintColor=Gold();pencil.contentMode=UIViewContentModeScaleAspectFit;pencil.translatesAutoresizingMaskIntoConstraints=NO;[box addSubview:pencil];
 [NSLayoutConstraint activateConstraints:@[[box.heightAnchor constraintGreaterThanOrEqualToConstant:50],[summary.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:12],[summary.topAnchor constraintEqualToAnchor:box.topAnchor constant:12],[summary.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-12],[summary.trailingAnchor constraintEqualToAnchor:pencil.leadingAnchor constant:-10],[pencil.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12],[pencil.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],[pencil.widthAnchor constraintEqualToConstant:18],[pencil.heightAnchor constraintEqualToConstant:18]]];
 UILabel *hint=Label(@"点击输入框编辑文件名模板",11,NO);hint.textColor=UIColor.secondaryLabelColor;
 UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[label,box,self.previews[index.row],hint]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=9;stack.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],[stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14],[stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14]]];
 cell.selectionStyle=UITableViewCellSelectionStyleNone;cell.isAccessibilityElement=NO;
 }

 return cell;}
// Keep controls in stable content views: reparenting accessory switches during a
// section reload can make UIKit repeatedly invalidate its accessory layout.
- (void)installSwitch:(UISwitch *)toggle inCell:(UITableViewCell *)cell{
 toggle.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:toggle];
 [NSLayoutConstraint activateConstraints:@[[toggle.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],[toggle.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],[toggle.topAnchor constraintGreaterThanOrEqualToAnchor:cell.contentView.topAnchor constant:6],[toggle.bottomAnchor constraintLessThanOrEqualToAnchor:cell.contentView.bottomAnchor constant:-6]]];
}
- (void)refreshChoices{
 for(UISwitch *toggle in self.schemeSwitches)toggle.enabled=self.exportDeb;
 for(NSIndexPath *path in self.settingCells){UITableViewCell *cell=self.settingCells[path];if(path.section<1||path.section>2)continue;
  if(self.root&&path.row==0){cell.accessoryType=(path.section==1?self.inheritOutput:self.inheritSchemes)?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;if(path.section==2)cell.userInteractionEnabled=self.exportDeb;}
  else if(path.section==1){for(UIView *view in cell.contentView.subviews)if([view isKindOfClass:UISwitch.class])((UISwitch *)view).on=((UISwitch *)view).tag?self.exportDeb:self.exportDylib;}
  if(path.section==2)cell.textLabel.enabled=self.exportDeb;
 }
 [self updatePreviews];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index{[table deselectRowAtIndexPath:index animated:YES];if(index.section==0){[self editSDKSetting:index.row];return;}if(index.section==3)return;if(index.section==1){if(self.root&&index.row==0){NSDictionary *global=TMCEffectiveBuildOptions(@{},NSUserDefaults.standardUserDefaults);self.exportDeb=[global[@"package"] boolValue];self.exportDylib=[global[@"exportDylib"] boolValue];self.inheritOutput=YES;NSArray *schemes=global[@"packageSchemes"];for(NSUInteger i=0;i<3;i++)self.schemeSwitches[i].on=self.exportDeb&&[schemes containsObject:@[@"rootless",@"rootful",@"roothide"][i]];}else{NSUInteger row=index.row-(self.root?1:0);self.inheritOutput=NO;if(row){self.exportDeb=!self.exportDeb;self.inheritSchemes=NO;for(NSUInteger i=0;i<3;i++)self.schemeSwitches[i].on=self.exportDeb&&i==0;}else self.exportDylib=!self.exportDylib;}[self refreshChoices];}
 if(self.root&&index.section==2&&index.row==0&&self.exportDeb){self.inheritSchemes=YES;NSArray *defaults=TMCEffectiveBuildOptions(@{},NSUserDefaults.standardUserDefaults)[@"packageSchemes"];for(NSUInteger i=0;i<3;i++)self.schemeSwitches[i].on=[defaults containsObject:@[@"rootless",@"rootful",@"roothide"][i]];[self refreshChoices];}[self saveOrRestore];}
- (BOOL)saveSDKValue:(NSString *)value key:(NSString *)key {
 TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){Message(self,@"Git 正在处理",@"请稍后修改构建设置。");return NO;}
 NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;NSMutableDictionary *config=[(self.root?Config(self.root):@{}) mutableCopy];if(value)config[key]=value;else[config removeObjectForKey:key];
 // Validate prospective global defaults without mutating preferences on failure.
 NSMutableDictionary *candidate=[config mutableCopy];if(!self.root){for(NSString *other in @[@"sdkVersion",@"deploymentTarget"]){if([other isEqual:key])continue;NSString *defaultKey=[other isEqual:@"sdkVersion"]?@"StudioSDKVersion":@"StudioDeploymentTarget";candidate[other]=[defaults objectForKey:defaultKey]?:([other isEqual:@"sdkVersion"]?@"16.4":@"15.0");}}
 NSError *error=nil;if(!TMCSDKBuildSettings(candidate,defaults,&error)){Message(self,@"构建配置有误",error.localizedDescription);return NO;}
 if(self.root){if(!JSONWrite(config,[self.root stringByAppendingPathComponent:@"MobileCompiler.json"],&error)){Message(self,@"保存失败",error.localizedDescription);return NO;}MarkSaved(self.root);}else [defaults setObject:value forKey:[key isEqual:@"sdkVersion"]?@"StudioSDKVersion":@"StudioDeploymentTarget"];
 self.original=self.root?Config(self.root):@{};for(NSUInteger row=0;row<2;row++)[self.settingCells removeObjectForKey:[NSIndexPath indexPathForRow:row inSection:0]];[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];return YES;
}
- (void)editSDKSetting:(NSUInteger)row {
 NSString *key=row?@"deploymentTarget":@"sdkVersion";UIAlertController *sheet=[UIAlertController alertControllerWithTitle:row?@"最低系统版本":@"编译 SDK" message:row?@"仅改变插件产物的最低运行版本，不修改手机系统。":@"16.4 保持现有兼容；26.0 提供液态玻璃等新 API 声明。" preferredStyle:UIAlertControllerStyleActionSheet];
 if(self.root)[sheet addAction:[UIAlertAction actionWithTitle:@"跟随全局" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self saveSDKValue:nil key:key];}]];
 NSArray *values=row?@[@"15.0",@"16.0",@"16.4",@"17.0",@"18.0",@"26.0"]:@[@"16.4",@"26.0"];
 NSString *selectedSDK=TMCSDKBuildSettings(self.root?Config(self.root):@{},NSUserDefaults.standardUserDefaults,nil)[@"sdkVersion"]?:@"16.4";
 for(NSString *value in values)if(!row||[value compare:selectedSDK options:NSNumericSearch]!=NSOrderedDescending)[sheet addAction:[UIAlertAction actionWithTitle:[@"iOS " stringByAppendingString:value] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self saveSDKValue:value key:key];}]];
 if(row)[sheet addAction:[UIAlertAction actionWithTitle:@"自定义版本…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){UIAlertController *input=[UIAlertController alertControllerWithTitle:@"最低系统版本" message:@"如 15.0、16.4、18.6 或 26.0；不得高于所选 SDK。" preferredStyle:UIAlertControllerStyleAlert];[input addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"15.0";f.keyboardType=UIKeyboardTypeDecimalPad;}];[input addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[input addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self saveSDKValue:[input.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] key:key];}]];[self presentViewController:input animated:YES completion:nil];}]];
 [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];sheet.popoverPresentationController.sourceView=self.tableView;sheet.popoverPresentationController.sourceRect=[self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];[self presentViewController:sheet animated:YES completion:nil];
}
- (void)editPattern:(UIControl *)sender{NSIndexPath *index=[NSIndexPath indexPathForRow:sender.tag inSection:3];StudioValueEditor *editor=[StudioValueEditor new];editor.title=index.row?@"动态库文件名":@"DEB 文件名";editor.value=self.patterns[index.row].text;editor.helpText=self.root?@"留空跟随全局。支持 {name}、{version}、{platform}、{packageArch}、{scheme} 等模板参数；点完成后自动保存。":@"留空恢复默认模板。支持 {name}、{version}、{platform}、{packageArch}、{scheme} 等参数。点完成后自动保存并更新预览。";__weak typeof(self) weak=self;editor.completion=^(NSString *value){weak.patterns[index.row].text=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];[weak.settingCells removeObjectForKey:index];[weak updatePreviews];[weak saveOrRestore];[weak.tableView reloadRowsAtIndexPaths:@[index] withRowAnimation:UITableViewRowAnimationNone];};UINavigationController *nav=[[TMCNavigationController alloc] initWithRootViewController:editor];nav.modalPresentationStyle=UIModalPresentationPageSheet;nav.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.mediumDetent,UISheetPresentationControllerDetent.largeDetent];nav.sheetPresentationController.prefersGrabberVisible=YES;[self presentViewController:nav animated:YES completion:nil];}
- (void)outputChanged:(UISwitch *)toggle{NSDictionary *previous=[self preferenceState];self.inheritOutput=NO;if(toggle.tag){self.exportDeb=toggle.on;self.inheritSchemes=NO;for(NSUInteger i=0;i<3;i++)self.schemeSwitches[i].on=self.exportDeb&&i==0;}else self.exportDylib=toggle.on;[self refreshChoices];if(![self persistSettings])[self restoreState:previous];else self.acceptedState=[self preferenceState];}
- (void)schemeChanged{self.inheritSchemes=NO;[self refreshChoices];[self saveOrRestore];}
- (void)updatePreviews{NSMutableDictionary *sample=[TMCOutputContext(self.root?:Docs(),self.root?(Config(self.root)[@"productName"]?:@"MyTweak"):@"MyTweak",self.previewDate) mutableCopy];if(!self.root){[sample addEntriesFromDictionary:@{@"name":@"我的插件",@"product":@"MyTweak",@"version":@"1.2.3",@"arch":@"arm64",@"package":@"com.example.mytweak",@"author":@"Developer"}];}NSMutableArray *schemes=[NSMutableArray new];for(NSUInteger i=0;i<3;i++)if(self.schemeSwitches[i].on)[schemes addObject:@[@"rootless",@"rootful",@"roothide"][i]];if(!schemes.count)[schemes addObject:@"rootless"];NSDictionary *global=TMCEffectiveBuildOptions(@{},NSUserDefaults.standardUserDefaults);for(NSUInteger i=0;i<2;i++){NSString *ext=i?@"dylib":@"deb",*text=self.patterns[i].text;NSString *pattern=text.length?text:global[[@"outputPattern-" stringByAppendingString:ext]];NSMutableArray *names=[NSMutableArray new];NSError *error=nil;for(NSString *scheme in schemes){NSString *name=i?TMCOutputFilename(pattern,ext,TMCNamingContextForScheme(sample,schemes.firstObject),&error):TMCVariantOutputFilename(pattern,ext,sample,self.exportDeb?schemes:@[@"rootless"],self.exportDeb?scheme:@"rootless",&error);if(!name)break;[names addObject:name];if(i||!self.exportDeb)break;}BOOL enabled=i?self.exportDylib:self.exportDeb;self.previews[i].text=error&&enabled?error.localizedDescription:enabled?[@"预览：\n" stringByAppendingString:[names componentsJoinedByString:@"\n"]]:@"当前未开启此产物";self.previews[i].textColor=error&&enabled?UIColor.systemRedColor:enabled?Gold():UIColor.secondaryLabelColor;}for(NSIndexPath *path in self.settingCells)if(path.section==3){UITableViewCell *cell=self.settingCells[path];NSString *value=self.patterns[path.row].text.length?self.patterns[path.row].text:self.patterns[path.row].placeholder;for(UIView *view in cell.contentView.subviews)if([view isKindOfClass:UIStackView.class])for(UIView *entry in ((UIStackView *)view).arrangedSubviews)if([entry isKindOfClass:UIControl.class])entry.accessibilityValue=value;}
 if(self.tableView.window)[UIView performWithoutAnimation:^{[self.tableView beginUpdates];[self.tableView endUpdates];}];}
- (BOOL)persistSettings{if(self.root){NSString *invalid=ValidateProject(self.root);if(invalid){Message(self,@"请先修正工程配置",invalid);return NO;}}TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){Message(self,@"Git 正在处理",@"请稍后保存构建设置。");return NO;}if(!self.exportDylib&&!self.exportDeb){Message(self,@"选择构建产物",@"请至少开启 dylib 或 deb。");return NO;}NSMutableArray *schemes=[NSMutableArray new];for(NSUInteger i=0;i<3;i++)if(self.schemeSwitches[i].on)[schemes addObject:@[@"rootless",@"rootful",@"roothide"][i]];if(self.exportDeb&&!schemes.count){Message(self,@"选择包类型",@"请至少选择一种包类型。");return NO;}if(!schemes.count)[schemes addObject:@"rootless"];NSDictionary *sample=TMCOutputContext(self.root?:Docs(),@"MyTweak",NSDate.date);for(NSUInteger i=0;i<2;i++){NSString *text=self.patterns[i].text;if(text.length){NSError *error=nil;if(!TMCOutputFilename(text,i?@"dylib":@"deb",sample,&error)){Message(self,@"文件名格式有误",error.localizedDescription);return NO;}}}
 NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;if(self.root){NSMutableDictionary *config=[Config(self.root) mutableCopy];if(self.inheritOutput){[config removeObjectForKey:@"package"];[config removeObjectForKey:@"exportDylib"];}else{config[@"package"]=@(self.exportDeb);config[@"exportDylib"]=@(self.exportDylib);}[config removeObjectForKey:@"packageScheme"];if(self.inheritSchemes)[config removeObjectForKey:@"packageSchemes"];else config[@"packageSchemes"]=schemes;
 for(NSUInteger i=0;i<2;i++){NSString *key=i?@"outputPattern-dylib":@"outputPattern-deb";if(self.patterns[i].text.length)config[key]=self.patterns[i].text;else[config removeObjectForKey:key];}NSError *error=nil;if(!JSONWrite(config,[self.root stringByAppendingPathComponent:@"MobileCompiler.json"],&error)){Message(self,@"保存失败",error.localizedDescription);return NO;}MarkSaved(self.root);
 }else{[defaults setBool:self.exportDeb forKey:@"StudioPackageEnabled"];[defaults setBool:self.exportDylib forKey:@"StudioExportDylib"];[defaults setObject:schemes forKey:@"StudioPackageSchemes"];for(NSUInteger i=0;i<2;i++){NSString *ext=i?@"dylib":@"deb";NSString *key=[@"StudioOutputPattern-" stringByAppendingString:ext];if(self.patterns[i].text.length)[defaults setObject:self.patterns[i].text forKey:key];else[defaults removeObjectForKey:key];}}
 return YES;}
- (void)commit{[self persistSettings];}
- (NSDictionary *)preferenceState{NSMutableArray *schemes=[NSMutableArray new];for(UISwitch *v in self.schemeSwitches)[schemes addObject:@(v.on)];return @{@"deb":@(self.exportDeb),@"dylib":@(self.exportDylib),@"output":@(self.inheritOutput),@"inherit":@(self.inheritSchemes),@"schemes":schemes,@"patterns":@[self.patterns[0].text?:@"",self.patterns[1].text?:@""]};}
- (void)restoreState:(NSDictionary *)state{if(!state)return;self.exportDeb=[state[@"deb"] boolValue];self.exportDylib=[state[@"dylib"] boolValue];self.inheritOutput=[state[@"output"] boolValue];self.inheritSchemes=[state[@"inherit"] boolValue];for(NSUInteger i=0;i<3;i++)self.schemeSwitches[i].on=[state[@"schemes"][i] boolValue];for(NSUInteger i=0;i<2;i++){self.patterns[i].text=state[@"patterns"][i];[self.settingCells removeObjectForKey:[NSIndexPath indexPathForRow:i inSection:3]];}[self refreshChoices];[self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:3],[NSIndexPath indexPathForRow:1 inSection:3]] withRowAnimation:UITableViewRowAnimationNone];}
- (void)saveOrRestore{if([self persistSettings])self.acceptedState=[self preferenceState];else [self restoreState:self.acceptedState];}

@end

static NSString *RuleCatalogText(void){NSMutableString *text=[NSMutableString stringWithString:@"本机离线规则库 · LLVM 14\n可修复项先预览确认；其余为方案或建议。\n\n"];for(NSDictionary *rule in TMCCompatibilityRules()){NSString *category=rule[@"handling"][@"category"];[text appendFormat:@"%@ · %@\n%@ · %@\n%@\n适用：%@\n来源：%@\n\n",rule[@"id"],rule[@"name"],[category isEqual:@"repairable"]?@"可修复":[category isEqual:@"choice"]?@"需要选择方案":@"仅诊断建议",[rule[@"validation"][@"status"] isEqual:@"verified"]?@"已验证":@"待验证",rule[@"explanation"],rule[@"applicableVersions"][@"compiler"],[rule[@"sources"] componentsJoinedByString:@"\n"]];}return text;}
static NSArray *ThirdPartyComponents(void){NSString *path=[NSBundle.mainBundle pathForResource:@"components" ofType:@"json" inDirectory:@"ThirdPartyNotices"];NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;id json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;return [json isKindOfClass:NSArray.class]?json:@[];}
@interface StudioAbout : UITableViewController
@end
@implementation StudioAbout
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path{TMCEnableLinksInView(cell);}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];TMCEnableLinksInView(self.view);}
- (void)viewDidLoad{[super viewDidLoad];ApplyTheme(self);self.title=@"关于 Dylix";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=60;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 4;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?3:s==1?3:s==2?2:ThirdPartyComponents().count;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"Dylix",@"功能与使用",@"诊断与适配",@"开源组件与许可证"][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==3?@"各组件版权归原作者所有。点击查看来源及完整许可证。SDK 与系统框架适用 Apple 条款；此处未将其标为开源组件。":nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i{UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];c.detailTextLabel.font=[UIFont systemFontOfSize:12];c.detailTextLabel.numberOfLines=0;
 if(i.section==0){c.textLabel.text=@[@"版本",@"作者",@"本机工具链"][i.row];NSDictionary *info=NSBundle.mainBundle.infoDictionary;c.detailTextLabel.text=i.row==0?[NSString stringWithFormat:@"%@（%@）",info[@"CFBundleShortVersionString"],info[@"CFBundleVersion"]]:i.row==1?@"Xuegao":@"Clang / LLD 14 · Perl 5.34.0 · SDK 16.4 / 26.0";c.selectionStyle=UITableViewCellSelectionStyleNone;}
 else if(i.section==1){c.textLabel.text=@[@"软件功能说明",@"编译与使用说明",@"隐私与本地存储"][i.row];c.detailTextLabel.text=@[@"工程、编辑器、构建与产物",@"支持范围、签名及运行环境",@"离线规则、项目与诊断记录"][i.row];}
 else if(i.section==2){c.textLabel.text=i.row==0?@"编译诊断与兼容适配规则库":@"适配前后诊断记录";c.detailTextLabel.text=i.row==0?@"规则条件、验证状态及来源":@"按项目查看修复前后记录";}
 else {NSDictionary *component=ThirdPartyComponents()[i.row];c.textLabel.text=component[@"name"];c.detailTextLabel.text=component[@"license"];}
 if(i.section)c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (void)showText:(NSString *)text title:(NSString *)title{[self.navigationController pushViewController:TMCHelpTextArticle(title,text) animated:YES];}
- (void)historyForProject:(NSString *)root{NSString *folder=[root stringByAppendingPathComponent:@".studio-repair-history"];NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] sortedArrayUsingSelector:@selector(compare:)];NSMutableString *text=[NSMutableString new];for(NSString *name in names)if([name.pathExtension isEqual:@"json"]){NSString *record=[NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:nil];[text appendFormat:@"%@\n%@\n\n",name,record?:@""];}[self showText:text.length?text:@"本项目暂无适配记录。" title:[NSString stringWithFormat:@"%@ · 适配记录",ProjectName(root)]];}
- (void)chooseHistory{NSMutableArray *projects=[NSMutableArray new];for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:Projects() error:nil]){NSString *root=[Projects() stringByAppendingPathComponent:name];if([[NSFileManager.defaultManager contentsOfDirectoryAtPath:[root stringByAppendingPathComponent:@".studio-repair-history"] error:nil] count])[projects addObject:root];}if(!projects.count){Message(self,@"暂无适配记录",@"项目应用修复后会保存原诊断；重新构建完成后追加新诊断。");return;}UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"选择项目" message:nil preferredStyle:UIAlertControllerStyleActionSheet];for(NSString *root in projects)[alert addAction:[UIAlertAction actionWithTitle:ProjectName(root) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self historyForProject:root];}]];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];alert.popoverPresentationController.sourceView=self.view;alert.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,self.view.bounds.size.height/2,1,1);[self presentViewController:alert animated:YES completion:nil];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i{[t deselectRowAtIndexPath:i animated:YES];if(!i.section)return;
 if(i.section==1){NSArray *texts=@[@"Dylix 是在 iPhone 本机工作的插件开发工具。\n\n• 创建、打开与压缩包导入项目，管理最近与本机项目。\n• 文件编辑、语法着色、行号、查找替换、错误位置跳转。\n• Makefile 常用静态配置识别、Objective-C / C / C++ / Objective-C++、多 Logos 源文件构建。\n• 导出 dylib 与 DEB，按项目覆盖全局构建设置，自定义产物名称。\n• 实时构建日志、结果导出、离线诊断与兼容修复。\n• Git 本地暂存、提交、差异、历史、分支合并、版本恢复与撤回。\n• HTTPS 克隆、获取、拉取、推送；冲突逐文件处理；认证令牌存钥匙串。",@"工具链在应用内执行本地编译。支持有根、无根和隐根包布局；包布局与 CPU 架构是两个不同设置。\n\n当前以 arm64 为主要编译目标。复杂 Makefile、真实外部依赖及新语言特性需逐项核对；不包含 Xcode / MonkeyDev 导入器。\n\n产物的签名、安装和宿主加载需要相应工具与运行环境。",@"规则匹配与兼容修复离线运行，不连接 AI 或云端。AI 助手连接你配置的模型服务；明确选择的上下文和工具读取结果会发送给该服务，源码修改须经本机审批。\n\n项目、日志、备份及适配历史保存在本机应用目录。分享仅在你主动操作时导出。\n\nGit 本地操作离线执行；克隆、获取、拉取、推送按你指定的远程仓库联网。用户名和访问令牌保存在设备钥匙串，不写入源码或仓库地址。Git 远程传输当前支持 HTTPS，不包含 SSH、Git LFS 下载和子模块递归克隆。删除项目时，其项目内备份及适配历史也随之删除。"];
 [self showText:texts[i.row] title:@[@"软件功能说明",@"编译与使用说明",@"隐私与本地存储"][i.row]];
 }else if(i.section==2){if(i.row==0)[self showText:RuleCatalogText() title:@"编译诊断与兼容适配规则库"];else[self chooseHistory];}
 else {NSDictionary *component=ThirdPartyComponents()[i.row];NSString *path=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:[@"ThirdPartyNotices" stringByAppendingPathComponent:component[@"file"]]];NSString *license=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];[self showText:[NSString stringWithFormat:@"%@\n许可：%@\n来源：%@\n\n%@",component[@"name"],component[@"license"],component[@"source"],license?:@"许可文本读取失败，请查看组件来源。"] title:component[@"name"]];}}
@end

static NSArray<NSString *> *OptimizationLevels(void){return @[@"debug",@"release-size",@"release-speed",@"-O0",@"-O1",@"-O2",@"-O3",@"-Os",@"-Oz"];}
static NSString *GlobalOptimization(void){NSString *value=[NSUserDefaults.standardUserDefaults stringForKey:@"StudioOptimization"];return [OptimizationLevels() containsObject:value]?value:@"release-speed";}
@interface StudioOptimizationPicker : UITableViewController
@property NSString *selected;
@property BOOL project;
@property(copy) void (^completion)(NSString *value);
@end
@implementation StudioOptimizationPicker
- (void)viewDidLoad{[super viewDidLoad];ApplyTheme(self);self.title=@"构建方案与优化";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=90;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table{return self.project?2:1;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return self.project&&section==0?1:OptimizationLevels().count;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section{return self.project&&section==0?@"配置来源":@"编译优化";}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section{
 if(self.project&&section==0)return @"跟随全局时，构建使用软件设置中的优化级别。";
 return [NSString stringWithFormat:@"%@\n\n本机 Theos 的正式构建默认 -Os，DEBUG 构建默认 -O0，项目可以覆盖。优化不会修复回调签名或内存错误；发布前应在目标设备测试。",self.project?@"选择后返回项目设置，再点击保存生效。":@"选择后立即保存为全局默认值；项目单独指定的级别保持不变。"];
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path{
 UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
 if(self.project&&path.section==0){cell.textLabel.text=@"跟随全局";cell.detailTextLabel.text=[@"当前生效：" stringByAppendingString:GlobalOptimization()];cell.accessoryType=!self.selected.length?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;return cell;}
 NSArray *names=@[@"调试方案 · -O0",@"发布方案 · -Os",@"发布方案 · -O2",@"调试优先",@"适度优化",@"运行效率优先",@"更激进的优化",@"体积与效率平衡",@"体积优先"];
 NSArray *details=@[@"调试方案：关闭优化并保留 DWARF 与符号索引，便于排错。构建通过仍需真机验证。",@"发布体积方案：-Os，同时保留离线符号档案。发布前在实际宿主中验证。",@"默认发布效率方案：-O2，同时保留离线符号档案。优化可能改变变量与调用顺序。",@"不做常规优化，便于定位错误和调试。编译通常更快，运行速度和体积通常不及优化版本。适合开发排错。",@"进行基础优化，在编译时间、运行效率和调试体验间折中。适合日常功能测试。",@"进行更充分的优化，常用于正式发布。变量和源码执行顺序可能变化，调试更困难。",@"在 -O2 基础上增加更激进的优化，可能增大代码体积，也未必更快。仅在实测有收益时选择。",@"在优化运行效率的同时控制代码体积。适合插件发布，也是本机 Theos 正式构建的默认选择。",@"更积极地缩小代码体积，可能牺牲部分运行效率。适合对安装包大小敏感且经过实测的项目。"];
 NSString *value=OptimizationLevels()[path.row];cell.textLabel.text=[NSString stringWithFormat:@"%@ · %@",value,names[path.row]];cell.detailTextLabel.text=details[path.row];cell.accessoryType=[self.selected isEqual:value]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path{NSString *value=self.project&&path.section==0?@"":OptimizationLevels()[path.row];if(self.completion)self.completion(value);[self.navigationController popViewControllerAnimated:YES];}
@end

@interface StudioCrashTools : UITableViewController <UIDocumentPickerDelegate>
@end
@implementation StudioCrashTools
- (void)viewDidLoad{[super viewDidLoad];ApplyTheme(self);self.title=@"离线崩溃分析";}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return 1;}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section{return @"选择 .ips 分析故障线程；也可先导入对应的 symbols.json，再导入报告。只按相同 UUID 匹配，全部在本机处理。历史构建和不同项目均可分析。";}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path{UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];cell.textLabel.text=@"导入 .ips / 符号档案";cell.imageView.image=[UIImage systemImageNamed:@"waveform.path.ecg"];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path{[table deselectRowAtIndexPath:path animated:YES];[self importCrash];}
- (void)importCrash{UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{NSURL *url=urls.firstObject;if(!url)return;[url startAccessingSecurityScopedResource];NSNumber *size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];if(!size||size.unsignedLongLongValue>20*1024*1024){[url stopAccessingSecurityScopedResource];Message(self,@"报告大小有误",@"请选择 20 MB 以内的 .ips 报告或 symbols.json 符号档案。");return;}NSData *data=[NSData dataWithContentsOfURL:url];[url stopAccessingSecurityScopedResource];dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;NSString *result=nil;if([value isKindOfClass:NSDictionary.class]&&[value[@"schema"] isEqual:@1]&&[value[@"images"] isKindOfClass:NSArray.class]){NSString *dir=[Docs() stringByAppendingPathComponent:[@"Build-ImportedSymbols-" stringByAppendingString:NSUUID.UUID.UUIDString]];NSError *error=nil;BOOL ok=[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]&&[data writeToFile:[dir stringByAppendingPathComponent:@"symbols.json"] options:NSDataWritingAtomic error:&error];result=ok?@"符号档案已导入。再次导入 .ips 可按 UUID 匹配。符号档案仅用于查找，不执行任何内容。":error.localizedDescription;}else result=TFCrashAnalysis(data,Docs());dispatch_async(dispatch_get_main_queue(),^{StudioText *v=[StudioText new];v.title=@"崩溃分析";v.content=result;[self.navigationController pushViewController:v animated:YES];});});}
@end

@interface StudioSettings : UITableViewController
@end
@implementation StudioSettings
- (void)viewDidLoad { [super viewDidLoad];self.title=@"设置";ApplyTheme(self); }
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 7; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [@[@1,@1,@2,@3,@3,@4,@2][s] integerValue]; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return @[@"源代码管理",@"AI",@"工具",@"外观与编辑器",@"构建与产物",@"工具链与本机",@"关于"][s]; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i { if(i.section==6&&i.row>0){UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];cell.textLabel.text=@"项目开源地址";cell.textLabel.font=[UIFont systemFontOfSize:14];cell.imageView.image=[UIImage systemImageNamed:@"chevron.left.forwardslash.chevron.right"];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;}i=[NSIndexPath indexPathForRow:i.section==6?1:i.row inSection:(NSInteger[]){0,4,5,1,2,3,4}[i.section]];UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];NSUserDefaults *u=NSUserDefaults.standardUserDefaults; NSArray *titles=@[@[@"Git"],@[@"界面外观",@"代码字号",@"自动保存"],@[@"优化级别",@"目标架构",@"默认构建设置"],@[@"Clang / LLD",@"SDK / Perl",@"设备 / 系统",@"存储空间"],@[@"AI 开发助手",@"关于 Dylix"],@[@"IPA 头文件导出",@"离线崩溃分析"]]; c.textLabel.text=titles[i.section][i.row];NSArray *symbols=@[@[@"point.3.connected.trianglepath.dotted"],@[@"circle.lefthalf.filled",@"textformat.size",@"square.and.arrow.down"],@[@"speedometer",@"cpu",@"slider.horizontal.3"],@[@"hammer",@"shippingbox",@"iphone",@"internaldrive"],@[@"sparkles",@"info.circle"],@[@"doc.text.magnifyingglass",@"waveform.path.ecg"]];c.imageView.image=[UIImage systemImageNamed:symbols[i.section][i.row]];c.imageView.preferredSymbolConfiguration=[UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightRegular];c.textLabel.font=[UIFont systemFontOfSize:14];c.detailTextLabel.font=[UIFont systemFontOfSize:11];
 if(i.section==1) {c.detailTextLabel.text=i.row==0?@[@"跟随系统",@"石墨深色",@"纸感浅色"][[u integerForKey:@"StudioTheme"]]:i.row==1?[NSString stringWithFormat:@"%ld pt",(long)([u integerForKey:@"StudioFont"]?:14)]:@"始终开启";if(i.row<2)c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
 if(i.section==2){c.detailTextLabel.text=i.row==0?GlobalOptimization():i.row==1?@"arm64":i.row==2?@"SDK / 最低系统 / 产物":@"导入 .ips / 符号档案";if(i.row==0||i.row==2)c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
 if(i.section==5){c.detailTextLabel.text=i.row?@"导入 .ips / 符号档案":@"本机离线解析 / ZIP 分享";c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
 if(i.section==3&&i.row==3)c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
 if(i.section==3){struct utsname n;uname(&n);NSDictionary *fs=[NSFileManager.defaultManager attributesOfFileSystemForPath:Docs() error:nil];c.detailTextLabel.text=i.row==0?@"14 / 14":i.row==1?@"16.4、26.0 / 5.34.0":i.row==2?[NSString stringWithFormat:@"%s / %@",n.machine,UIDevice.currentDevice.systemVersion]:[NSByteCountFormatter stringFromByteCount:[fs[NSFileSystemFreeSize] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];}
 if(i.section==0){c.detailTextLabel.text=@"身份 · 服务账号 · 自动存档";c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}if(i.section==4){c.detailTextLabel.text=i.row==0?@"模型连接 · 一键测试":[NSString stringWithFormat:@"%@",NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}return c; }
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i { [t deselectRowAtIndexPath:i animated:YES];if(i.section==6&&i.row>0){[UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/yangokok886/dylix"] options:@{} completionHandler:^(BOOL success){if(!success)dispatch_async(dispatch_get_main_queue(),^{Message(self,@"打开失败",@"请检查网络或浏览器设置后重试。");});}];return;}NSIndexPath *visibleIndex=i;i=[NSIndexPath indexPathForRow:i.section==6?1:i.row inSection:(NSInteger[]){0,4,5,1,2,3,4}[i.section]];if(i.section==3&&i.row==3){[self.navigationController pushViewController:TMCStorageController() animated:YES];return;}if(i.section==0){[self.navigationController pushViewController:TMCGitSettingsController(nil) animated:YES];return;}if(i.section==2&&i.row==0){StudioOptimizationPicker *picker=[[StudioOptimizationPicker alloc] initWithStyle:UITableViewStyleInsetGrouped];picker.selected=GlobalOptimization();__weak typeof(self) weak=self;picker.completion=^(NSString *value){[NSUserDefaults.standardUserDefaults setObject:value forKey:@"StudioOptimization"];[weak.tableView reloadData];};[self.navigationController pushViewController:picker animated:YES];return;}if(i.section==5){UIViewController *tool=i.row?[[StudioCrashTools alloc] initWithStyle:UITableViewStyleInsetGrouped]:TFAIClassDumpController();[self.navigationController pushViewController:tool animated:YES];return;}if(i.section==2&&i.row==2){[self.navigationController pushViewController:[[StudioBuildPreferences alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];return;} if(i.section==4){if(i.row==1){[self.navigationController pushViewController:[[StudioAbout alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];return;}[self.navigationController pushViewController:TFAISettingsController(nil) animated:YES];return;}

 NSArray *choices=nil;NSString *key=nil;if(i.section==1&&i.row==0){choices=@[@"跟随系统",@"石墨深色",@"纸感浅色"];key=@"StudioTheme";}if(i.section==1&&i.row==1){choices=@[@"12",@"14",@"16",@"18",@"20"];key=@"StudioFont";}if(!choices)return;
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"选择偏好" message:nil preferredStyle:UIAlertControllerStyleActionSheet];for(NSUInteger n=0;n<choices.count;n++){NSString *value=choices[n];[a addAction:[UIAlertAction actionWithTitle:value style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){NSUserDefaults *u=NSUserDefaults.standardUserDefaults;if([key isEqual:@"StudioTheme"])[u setInteger:n forKey:key];else if([key isEqual:@"StudioFont"])[u setInteger:value.integerValue forKey:key];else [u setObject:value forKey:key];ApplyTheme(self);[self.tableView reloadData];}]];}[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=[t cellForRowAtIndexPath:visibleIndex];a.popoverPresentationController.sourceRect=[t cellForRowAtIndexPath:visibleIndex].bounds;[self presentViewController:a animated:YES completion:nil]; }

@end

@class StudioEditor;
static UIColor *FileColor(NSString *path) {
 NSString *ext=path.pathExtension.lowercaseString;
 if([@[@"m",@"mm"] containsObject:ext])return UIColor.systemBlueColor;
 if([@[@"h",@"hpp"] containsObject:ext])return UIColor.systemTealColor;
 if([@[@"xm",@"x"] containsObject:ext])return UIColor.systemPurpleColor;
 if([@[@"c",@"cpp",@"cc"] containsObject:ext])return UIColor.systemIndigoColor;
 if([@[@"json",@"plist",@"xml"] containsObject:ext])return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t){return t.userInterfaceStyle==UIUserInterfaceStyleDark?UIColor.systemOrangeColor:[UIColor colorWithRed:.62 green:.30 blue:.04 alpha:1];}];
 if([path.lastPathComponent isEqual:@"control"]||[path.lastPathComponent isEqual:@"Makefile"])return UIColor.systemGreenColor;
 return UIColor.labelColor;
}
static NSString *FileSymbol(NSString *path) {
 NSString *ext=path.pathExtension.lowercaseString;
 if([@[@"m",@"mm",@"c",@"cpp",@"xm",@"h",@"hpp"] containsObject:ext])return @"chevron.left.forwardslash.chevron.right";
 if([@[@"json",@"plist",@"xml"] containsObject:ext])return @"slider.horizontal.3";
 return @"doc.text";
}
static NSString *BuildDate(NSDate *date){if(!date)return @"暂无记录";NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"yyyy-MM-dd HH:mm:ss";return [f stringFromDate:date];}
@interface StudioBuildResults : UITableViewController
@property NSString *directory;
@property NSString *projectName;
@property NSArray<NSDictionary *> *files;
@property NSArray<NSArray<NSString *> *> *summary;
@end
@implementation StudioBuildResults
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];TMCEnableLinksInView(self.view);}
- (void)viewDidLoad{[super viewDidLoad];ApplyTheme(self);self.title=@"构建结果";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=78;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"] style:UIBarButtonItemStylePlain target:self action:@selector(shareAll)];[self reloadResults];}
- (void)reloadResults{
 NSMutableArray *files=[NSMutableArray new];NSFileManager *fm=NSFileManager.defaultManager;
 if(self.directory){NSDirectoryEnumerator *enumerator=[fm enumeratorAtPath:self.directory];for(NSString *name in enumerator){if([name.lastPathComponent hasPrefix:@"."]){[enumerator skipDescendants];continue;}if([name.pathExtension.lowercaseString isEqual:@"o"])continue;NSString *path=Child(self.directory,name);NSDictionary *a=path?[fm attributesOfItemAtPath:path error:nil]:nil;if(![a[NSFileType] isEqual:NSFileTypeRegular]){if([a[NSFileType] isEqual:NSFileTypeSymbolicLink])[enumerator skipDescendants];continue;}[files addObject:@{@"name":name,@"bytes":a[NSFileSize]?:@0,@"date":a[NSFileModificationDate]?:NSDate.distantPast}];}}
 [files sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSArray *types=@[@"dylib",@"deb"];NSUInteger left=[types indexOfObject:[a[@"name"] pathExtension].lowercaseString],right=[types indexOfObject:[b[@"name"] pathExtension].lowercaseString];if(left!=right)return left<right?NSOrderedAscending:NSOrderedDescending;return [a[@"name"] localizedStandardCompare:b[@"name"]];}];self.files=files;
 NSData *data=self.directory?[NSData dataWithContentsOfFile:[self.directory stringByAppendingPathComponent:@"report.json"]]:nil;id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;NSDictionary *report=[value isKindOfClass:NSDictionary.class]?value:nil;
 NSMutableArray *rows=[NSMutableArray arrayWithObjects:@[@"项目",self.projectName?:@"—"],@[@"状态",report?([report[@"success"] boolValue]?@"构建通过 · 运行待验证":@"构建失败，请查看日志和报告"):(files.count?@"构建报告缺失":@"暂无构建结果")],nil];
 NSDictionary *provenance=[report[@"provenance"] isKindOfClass:NSDictionary.class]?report[@"provenance"]:@{};if(provenance.count){[rows addObject:@[@"方案 / 优化",[NSString stringWithFormat:@"%@ · %@",provenance[@"profile"],provenance[@"optimization"]]]];[rows addObject:@[@"编译器 / SDK",[NSString stringWithFormat:@"%@ · %@",provenance[@"compiler"],provenance[@"sdk"]]]];}
 for(NSString *key in @[@"startedAt",@"finishedAt"]){id stamp=report[key];if([stamp isKindOfClass:NSNumber.class])[rows addObject:@[[key isEqual:@"startedAt"]?@"开始时间":@"完成时间",BuildDate([NSDate dateWithTimeIntervalSince1970:[stamp doubleValue]])]];}
 if([report[@"durationSeconds"] isKindOfClass:NSNumber.class])[rows addObject:@[@"构建耗时",[NSString stringWithFormat:@"%.2f 秒",[report[@"durationSeconds"] doubleValue]]]];
 else if(report){NSDictionary *a=[fm attributesOfItemAtPath:[self.directory stringByAppendingPathComponent:@"report.json"] error:nil];[rows addObject:@[@"报告修改时间",BuildDate(a[NSFileModificationDate])]];}
 unsigned long long bytes=0;for(NSDictionary *file in files)bytes+=[file[@"bytes"] unsignedLongLongValue];[rows addObject:@[@"文件合计",[NSString stringWithFormat:@"%lu 个 · %@",(unsigned long)files.count,[NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile]]]];self.summary=rows;self.navigationItem.rightBarButtonItem.enabled=files.count>0;[self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?self.summary.count:self.files.count;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return section==0?@"本次构建":@"产物与构建记录";}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{return section==1?(self.files.count?@"显示产物、日志、报告及修改时间。文本可打开阅读，长按文件可分享；清理构建缓存会同时移除这些结果。":@"完成构建后，这里会列出产物、日志和报告。"):nil;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
 UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightMedium];cell.detailTextLabel.font=[UIFont systemFontOfSize:12];cell.detailTextLabel.numberOfLines=0;
 if(indexPath.section==0){cell.textLabel.text=self.summary[indexPath.row][0];cell.detailTextLabel.text=self.summary[indexPath.row][1];cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;}
 NSDictionary *file=self.files[indexPath.row];NSString *name=file[@"name"];cell.textLabel.text=name;cell.textLabel.numberOfLines=2;cell.imageView.image=[UIImage systemImageNamed:[@[@"dylib",@"deb",@"o"] containsObject:name.pathExtension]?@"shippingbox":FileSymbol(name)];cell.imageView.tintColor=FileColor(name);NSString *type=name.pathExtension.length?name.pathExtension.uppercaseString:@"配置";cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@\n修改于 %@",type,[NSByteCountFormatter stringFromByteCount:[file[@"bytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile],BuildDate(file[@"date"])];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)shareFiles:(NSArray<NSDictionary *> *)files anchor:(NSIndexPath *)indexPath{
 NSMutableArray *urls=[NSMutableArray new];for(NSDictionary *file in files){NSString *path=Child(self.directory,file[@"name"]);if(path&&[NSFileManager.defaultManager fileExistsAtPath:path])[urls addObject:[NSURL fileURLWithPath:path]];}if(!urls.count){Message(self,@"文件已移除",@"请重新构建后查看结果。");return;}UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];if(indexPath){UITableViewCell *cell=[self.tableView cellForRowAtIndexPath:indexPath];sheet.popoverPresentationController.sourceView=cell;sheet.popoverPresentationController.sourceRect=cell.bounds;}else sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:sheet animated:YES completion:nil];
}
- (void)shareAll{[self shareFiles:self.files anchor:nil];}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
 [tableView deselectRowAtIndexPath:indexPath animated:YES];if(indexPath.section==0)return;NSDictionary *file=self.files[indexPath.row];NSString *name=file[@"name"],*path=Child(self.directory,name);NSSet *types=[NSSet setWithArray:@[@"log",@"json",@"m",@"mm",@"xm",@"h",@"c",@"cpp",@"plist",@"txt"]];BOOL text=[types containsObject:name.pathExtension.lowercaseString]||[name.lastPathComponent isEqual:@"control"];if(text&&[file[@"bytes"] unsignedLongLongValue]<=2*1024*1024){NSError *error=nil;NSString *content=path?[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error]:nil;if(content){StudioText *preview=[StudioText new];preview.title=name;preview.content=content;[self presentViewController:[[TMCNavigationController alloc] initWithRootViewController:preview] animated:YES completion:nil];return;}if(error){Message(self,@"读取文件出错",error.localizedDescription);return;}}[self shareFiles:@[file] anchor:indexPath];
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point{if(indexPath.section==0)return nil;NSDictionary *file=self.files[indexPath.row];return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested){return [UIMenu menuWithTitle:file[@"name"] children:@[[UIAction actionWithTitle:@"分享文件" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *action){[self shareFiles:@[file] anchor:indexPath];}]]];}];}
@end

// File changes and explicit manifest references are committed together, with rollback on failure.
static BOOL ChangeProjectFile(NSString *root,NSString *old,NSString *replacement,NSError **error){TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){if(error)*error=[NSError errorWithDomain:@"TweakForge.Git" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Git 正在处理，请稍后修改文件"}];return NO;}
 NSFileManager *fm=NSFileManager.defaultManager;NSString *source=Child(root,old),*dest=replacement?Child(root,replacement):[NSTemporaryDirectory() stringByAppendingPathComponent:[@"DeletedFile-" stringByAppendingString:NSUUID.UUID.UUIDString]];
 NSString *reason=nil;NSDictionary *attributes=source?[fm attributesOfItemAtPath:source error:error]:nil;
 if(![attributes[NSFileType] isEqual:NSFileTypeRegular])reason=@"文件已变化，请重新打开文件列表。";
 else if(!dest)reason=@"目标路径超出项目目录。";
 else if(replacement&&[fm fileExistsAtPath:dest])reason=@"同名文件已存在，请使用其他名称。";
 else if(replacement&&[@[@"MobileCompiler.json",@"control"] containsObject:old])reason=@"此配置使用固定文件名，请保留名称并编辑内容。";
 if(reason){if(error)*error=[NSError errorWithDomain:@"TweakForge.Files" code:1 userInfo:@{NSLocalizedDescriptionKey:reason}];return NO;}
 NSString *manifest=[root stringByAppendingPathComponent:@"MobileCompiler.json"];NSData *data=[NSData dataWithContentsOfFile:manifest];NSMutableDictionary *config=nil;BOOL changed=NO;
 if(data&&![old isEqual:@"MobileCompiler.json"]){id value=[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];if(![value isKindOfClass:NSDictionary.class]){if(error&&!*error)*error=[NSError errorWithDomain:@"TweakForge.Files" code:2 userInfo:@{NSLocalizedDescriptionKey:@"请先修正 MobileCompiler.json 的 JSON 格式。"}];return NO;}config=value;
  for(NSString *key in @[@"sources",@"forcedIncludes"]){if(![config[key] isKindOfClass:NSArray.class])continue;NSMutableArray *paths=[NSMutableArray new];for(id path in config[key]){if([path isEqual:old]){changed=YES;if(replacement)[paths addObject:replacement];}else[paths addObject:path];}config[key]=paths;}
  if([config[@"prefixHeader"] isEqual:old]){changed=YES;if(replacement)config[@"prefixHeader"]=replacement;else[config removeObjectForKey:@"prefixHeader"];}
 }
 if(![fm moveItemAtPath:source toPath:dest error:error])return NO;
 if(changed&&!JSONWrite(config,manifest,error)){[fm moveItemAtPath:dest toPath:source error:nil];return NO;}
 if(!replacement)[fm removeItemAtPath:dest error:nil];MarkSaved(root);return YES;
}

@interface StudioFiles : UITableViewController <UISearchResultsUpdating,UISearchControllerDelegate>
@property NSString *root; @property(copy) void (^selection)(NSString *); @property(copy) void (^changed)(NSString *,NSString *); @property BOOL readOnly; @property UILabel *fileTitle; @property NSLayoutConstraint *titleWidth; @property NSArray *files; @property NSArray *visibleFiles; @property NSDictionary *modificationDates; @property UISegmentedControl *sortControl; @property UISearchController *fileSearch; @property NSString *pendingFile;
@end
@implementation StudioFiles
- (void)viewDidLoad {
 [super viewDidLoad];ApplyTheme(self);self.files=@[];self.visibleFiles=@[];self.fileTitle=Label(@"",17,YES);self.fileTitle.numberOfLines=1;self.fileTitle.lineBreakMode=NSLineBreakByTruncatingTail;self.fileTitle.adjustsFontSizeToFitWidth=NO;self.titleWidth=[self.fileTitle.widthAnchor constraintLessThanOrEqualToConstant:220];self.titleWidth.active=YES;self.navigationItem.titleView=self.fileTitle;[self updateFileTitle];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSMutableArray *files=[NSMutableArray new];NSMutableDictionary *dates=[NSMutableDictionary new];NSDirectoryEnumerator *enumerator=[NSFileManager.defaultManager enumeratorAtPath:self.root];
 for(NSString *path in enumerator){if([path.lastPathComponent hasPrefix:@"."]){[enumerator skipDescendants];continue;}NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:[self.root stringByAppendingPathComponent:path] error:nil];if([attributes[NSFileType] isEqual:NSFileTypeSymbolicLink]){[enumerator skipDescendants];continue;}if([attributes[NSFileType] isEqual:NSFileTypeDirectory])continue;if(Child(self.root,path)){[files addObject:path];dates[path]=attributes[NSFileModificationDate]?:NSDate.distantPast;}}
dispatch_async(dispatch_get_main_queue(),^{self.modificationDates=dates;self.files=files;[self sortChanged];[self updateFileTitle];});});
 [self updateFileTitle];self.sortControl=[[UISegmentedControl alloc] initWithItems:@[@"最近修改",@"名称 A–Z"]];self.sortControl.selectedSegmentIndex=0;[self.sortControl addTarget:self action:@selector(sortChanged) forControlEvents:UIControlEventValueChanged];UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,320,50)];self.sortControl.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:self.sortControl];[NSLayoutConstraint activateConstraints:@[[self.sortControl.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],[self.sortControl.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],[self.sortControl.topAnchor constraintEqualToAnchor:header.topAnchor constant:6],[self.sortControl.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-6]]];self.tableView.tableHeaderView=header;
 self.fileSearch=[[UISearchController alloc] initWithSearchResultsController:nil];self.fileSearch.searchResultsUpdater=self;self.fileSearch.delegate=self;self.fileSearch.obscuresBackgroundDuringPresentation=NO;self.fileSearch.searchBar.placeholder=@"搜索文件名或路径";self.fileSearch.searchBar.autocapitalizationType=UITextAutocapitalizationTypeNone;self.fileSearch.searchBar.autocorrectionType=UITextAutocorrectionTypeNo;self.navigationItem.searchController=self.fileSearch;self.navigationItem.hidesSearchBarWhenScrolling=NO;self.definesPresentationContext=YES;self.tableView.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;
}
- (void)sortFilesByModification{self.files=[self.files sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){NSComparisonResult result=[self.modificationDates[b] compare:self.modificationDates[a]];return result==NSOrderedSame?[a localizedStandardCompare:b]:result;}];}
- (void)sortChanged{if(self.sortControl.selectedSegmentIndex==0)[self sortFilesByModification];else self.files=[self.files sortedArrayUsingSelector:@selector(localizedStandardCompare:)];[self updateSearchResultsForSearchController:self.fileSearch];}
- (void)updateSearchResultsForSearchController:(UISearchController *)search {NSString *query=[search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];self.visibleFiles=query.length?[self.files filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *name,NSDictionary *bindings){return [name rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound;}]]:self.files;[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.visibleFiles.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSString *path=self.visibleFiles[indexPath.row];cell.textLabel.text=path.lastPathComponent;cell.textLabel.numberOfLines=1;cell.textLabel.lineBreakMode=NSLineBreakByTruncatingTail;cell.detailTextLabel.lineBreakMode=NSLineBreakByTruncatingTail;cell.accessibilityLabel=path;cell.textLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightMedium];cell.textLabel.textColor=FileColor(path);NSDate *modified=self.modificationDates[path];NSString *time=modified?SavedTimeLabel(modified,NSDate.date):@"未知";NSString *type=path.pathExtension.length?path.pathExtension.uppercaseString:@"配置";NSString *folder=path.stringByDeletingLastPathComponent;cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · 修改于 %@ · %@",type,time,folder.length?folder:@"项目根目录"];cell.detailTextLabel.font=[UIFont systemFontOfSize:10];cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;cell.imageView.image=[UIImage systemImageNamed:FileSymbol(path)];cell.imageView.tintColor=FileColor(path);return cell;}
- (void)finishSelection:(NSString *)path{[self.navigationController popViewControllerAnimated:YES];if(self.selection)self.selection(path);}
- (void)didDismissSearchController:(UISearchController *)search{if(self.pendingFile){NSString *path=self.pendingFile;self.pendingFile=nil;[self finishSelection:path];}}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{NSString *path=self.visibleFiles[indexPath.row];if(self.fileSearch.active){self.pendingFile=path;self.fileSearch.active=NO;}else[self finishSelection:path];}
- (void)updateFileTitle{self.title=[NSString stringWithFormat:@"%@（%lu）",ProjectName(self.root),(unsigned long)self.files.count];self.fileTitle.text=self.title;self.fileTitle.accessibilityLabel=self.title;}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];self.titleWidth.constant=MAX(80,MIN(280,self.view.bounds.size.width-150));}
- (void)fileChanged:(NSString *)old replacement:(NSString *)replacement{
 NSMutableArray *files=[self.files mutableCopy];NSUInteger index=[files indexOfObject:old];if(index!=NSNotFound){if(replacement)files[index]=replacement;else[files removeObjectAtIndex:index];}self.files=files;
 NSMutableDictionary *dates=[self.modificationDates mutableCopy];NSDate *date=dates[old];[dates removeObjectForKey:old];if(replacement)dates[replacement]=date?:NSDate.date;self.modificationDates=dates;
 if(self.changed)self.changed(old,replacement);[self updateFileTitle];[self sortChanged];
}
- (void)shareFile:(NSString *)path{
 NSString *file=Child(self.root,path);if(!file||![NSFileManager.defaultManager fileExistsAtPath:file]){Message(self,@"文件已移除",@"请重新打开文件列表。");return;}
 UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:file]] applicationActivities:nil];sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);[self presentViewController:sheet animated:YES completion:nil];
}
- (void)renameFile:(NSString *)path{
 if(self.readOnly)return;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"重命名文件" message:@"明确的编译配置路径及已打开标签会同步更新。源码 include 引用和 Makefile 内的文件名请自行检查。" preferredStyle:UIAlertControllerStyleAlert];
 [a addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=path.lastPathComponent;field.accessibilityLabel=@"文件名称";field.autocapitalizationType=UITextAutocapitalizationTypeNone;field.autocorrectionType=UITextAutocorrectionTypeNo;}];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(id action){NSString *name=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!NameOK(name)){Message(self,@"名称有误",@"请填写单个文件名，不包含路径字符。");return;}NSString *next=[path.stringByDeletingLastPathComponent stringByAppendingPathComponent:name];if([next isEqual:path])return;NSError *error=nil;if(!ChangeProjectFile(self.root,path,next,&error)){Message(self,@"重命名未完成",error.localizedDescription);return;}[self fileChanged:path replacement:next];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)deleteFile:(NSString *)path{
 if(self.readOnly)return;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认删除文件？" message:[NSString stringWithFormat:@"将从当前项目删除“%@”，并移除明确的编译配置引用。此操作不可撤回。",path] preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(id action){NSError *error=nil;if(!ChangeProjectFile(self.root,path,nil,&error)){Message(self,@"删除未完成",error.localizedDescription);return;}[self fileChanged:path replacement:nil];}]];[self presentViewController:a animated:YES completion:nil];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)index{
 if(index.row>=self.visibleFiles.count)return nil;NSString *path=self.visibleFiles[index.row];__weak typeof(self) weak=self;
 UIContextualAction *share=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"分享" handler:^(id action,UIView *view,void(^done)(BOOL)){done(YES);[weak shareFile:path];}];share.image=[UIImage systemImageNamed:@"square.and.arrow.up"];share.backgroundColor=UIColor.systemGreenColor;
 UIContextualAction *rename=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"重命名" handler:^(id action,UIView *view,void(^done)(BOOL)){done(YES);[weak renameFile:path];}];rename.image=[UIImage systemImageNamed:@"pencil"];rename.backgroundColor=UIColor.systemYellowColor;
 UIContextualAction *remove=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(id action,UIView *view,void(^done)(BOOL)){done(YES);[weak deleteFile:path];}];remove.image=[UIImage systemImageNamed:@"trash"];
 UISwipeActionsConfiguration *actions=[UISwipeActionsConfiguration configurationWithActions:self.readOnly?@[share]:@[remove,rename,share]];actions.performsFirstActionWithFullSwipe=NO;return actions;
}
@end

@interface StudioRepairPreview : UIViewController
@property NSString *root;
@property NSArray *diagnostics;
@property NSString *logText;
@property NSArray *findings;
@property NSMutableSet *selected;
@property NSMutableArray *editChoices;
@property UIStackView *content;
@property NSArray *plan;
@property(copy) void (^completion)(void);
@end
@implementation StudioRepairPreview
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];TMCEnableLinksInView(self.view);}
- (UIView *)diffBlock:(NSString *)source added:(BOOL)added {
 UIColor *color=added?[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits){return traits.userInterfaceStyle==UIUserInterfaceStyleDark?[UIColor colorWithRed:.40 green:.88 blue:.57 alpha:1]:[UIColor colorWithRed:.10 green:.42 blue:.23 alpha:1];}]:[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits){return traits.userInterfaceStyle==UIUserInterfaceStyleDark?[UIColor colorWithRed:1 green:.53 blue:.54 alpha:1]:[UIColor colorWithRed:.68 green:.16 blue:.20 alpha:1];}];
 UILabel *caption=Label(added?@"＋ 修改后":@"− 修改前",12,YES);caption.textColor=color;
 UILabel *code=Label(source.length?source:(added?@"（无新增内容）":@"（此处新增，无原内容）"),13,NO);code.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];code.numberOfLines=0;code.textColor=color;code.lineBreakMode=NSLineBreakByCharWrapping;code.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",added?@"修改后":@"修改前",code.text];
 UIStackView *block=[[UIStackView alloc] initWithArrangedSubviews:@[caption,code]];block.axis=UILayoutConstraintAxisVertical;block.spacing=8;block.layoutMargins=UIEdgeInsetsMake(12,12,12,12);block.layoutMarginsRelativeArrangement=YES;block.backgroundColor=[color colorWithAlphaComponent:.09];block.layer.cornerRadius=10;block.layer.borderWidth=1;block.layer.borderColor=[color colorWithAlphaComponent:.18].CGColor;return block;
}
- (void)viewDidLoad {
 [super viewDidLoad];ApplyTheme(self);self.title=@"适配修改预览";self.view.backgroundColor=UIColor.systemBackgroundColor;
 self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"应用修复" style:UIBarButtonItemStyleDone target:self action:@selector(apply)];
 UIScrollView *scroll=[UIScrollView new];scroll.alwaysBounceVertical=YES;scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];
 self.content=[UIStackView new];self.content.axis=UILayoutConstraintAxisVertical;self.content.spacing=16;self.content.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:self.content];
 self.selected=[NSMutableSet new];self.editChoices=[NSMutableArray new];for(NSDictionary *entry in self.plan)for(NSDictionary *edit in entry[@"edits"])[self.selected addObject:edit[@"id"]];
 [self renderChanges];
 [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[self.content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],[self.content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],[self.content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[self.content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],[self.content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];
}
- (void)toggleChange:(UIButton *)sender{NSDictionary *edit=self.editChoices[sender.tag];NSString *identifier=edit[@"id"];if([self.selected containsObject:identifier])[self.selected removeObject:identifier];else[self.selected addObject:identifier];[sender setImage:[UIImage systemImageNamed:[self.selected containsObject:identifier]?@"checkmark.circle.fill":@"circle"] forState:UIControlStateNormal];self.navigationItem.rightBarButtonItem.enabled=self.selected.count>0;}
- (void)renderChanges {
 UIStackView *content=self.content;
 UILabel *summary=Label([NSString stringWithFormat:@"可修复 · %lu 个文件",(unsigned long)self.plan.count],15,YES);[content addArrangedSubview:summary];
 UILabel *help=Label(@"逐项勾选后应用。红色为原内容，绿色为修改后内容。修改前保存备份；修复后请重新构建验证。",12,NO);help.numberOfLines=0;help.textColor=UIColor.secondaryLabelColor;[content addArrangedSubview:help];
 for(NSDictionary *entry in self.plan){
  UIStackView *file=[UIStackView new];file.axis=UILayoutConstraintAxisVertical;file.spacing=12;file.layoutMargins=UIEdgeInsetsMake(14,12,14,12);file.layoutMarginsRelativeArrangement=YES;file.backgroundColor=UIColor.secondarySystemBackgroundColor;file.layer.cornerRadius=14;
  BOOL config=[entry[@"file"] isEqual:@"MobileCompiler.json"];UILabel *name=Label([NSString stringWithFormat:@"%@ · %@",config?@"项目配置修改":@"源码修改",entry[@"file"]],14,YES);name.numberOfLines=0;name.lineBreakMode=NSLineBreakByCharWrapping;[file addArrangedSubview:name];
  for(NSDictionary *edit in entry[@"edits"]){
   UIButton *choose=[UIButton buttonWithType:UIButtonTypeSystem];choose.tag=self.editChoices.count;[self.editChoices addObject:edit];[choose setImage:[UIImage systemImageNamed:@"checkmark.circle.fill"] forState:UIControlStateNormal];[choose setTitle:[NSString stringWithFormat:@"  %@ · 行 %@ · %@",edit[@"ruleID"],edit[@"line"],edit[@"ruleName"]] forState:UIControlStateNormal];choose.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];choose.titleLabel.numberOfLines=0;choose.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;choose.accessibilityLabel=choose.titleLabel.text;[choose.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;[choose addTarget:self action:@selector(toggleChange:) forControlEvents:UIControlEventTouchUpInside];[file addArrangedSubview:choose];
   UILabel *reason=Label(edit[@"reason"],12,NO);reason.numberOfLines=0;reason.textColor=UIColor.secondaryLabelColor;[file addArrangedSubview:reason];
   [file addArrangedSubview:[self diffBlock:edit[@"displayBefore"]?:edit[@"before"] added:NO]];[file addArrangedSubview:[self diffBlock:edit[@"displayAfter"]?:edit[@"after"] added:YES]];
   UILabel *source=Label([NSString stringWithFormat:@"规则来源：\n%@",[edit[@"sources"] componentsJoinedByString:@"\n"]],11,NO);source.numberOfLines=0;source.textColor=UIColor.secondaryLabelColor;source.lineBreakMode=NSLineBreakByCharWrapping;[file addArrangedSubview:source];
  }[content addArrangedSubview:file];
 }
 for(NSDictionary *finding in self.findings){BOOL choice=[finding[@"handling"][@"category"] isEqual:@"choice"];UILabel *advice=Label([NSString stringWithFormat:@"%@ · %@ %@\n%@ · 行 %@\n%@\n验证：%@\n来源：%@",choice?@"需要选择方案":@"仅诊断建议",finding[@"id"],finding[@"name"],finding[@"file"],finding[@"line"],finding[@"explanation"],[finding[@"validation"][@"status"] isEqual:@"verified"]?@"已验证":@"待验证（不自动修改）",[finding[@"sources"] componentsJoinedByString:@"\n"]],12,NO);advice.numberOfLines=0;advice.textColor=UIColor.secondaryLabelColor;advice.lineBreakMode=NSLineBreakByCharWrapping;[content addArrangedSubview:advice];}
 self.navigationItem.rightBarButtonItem.enabled=self.selected.count>0;
}

- (void)cancel{[self dismissViewControllerAnimated:YES completion:nil];}
- (void)apply{NSArray *plan=TMCSelectedCompatibilityPlan(self.plan,self.selected);NSUInteger count=0;for(NSDictionary *entry in plan)count+=[entry[@"edits"] count];if(!count)return;UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"确认应用修复？" message:[NSString stringWithFormat:@"将应用已勾选的 %lu 处修改，涉及 %lu 个文件。应用前保存备份，完成后请重新构建验证。",(unsigned long)count,(unsigned long)plan.count] preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"应用修复" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self applyConfirmed];}]];[self presentViewController:alert animated:YES completion:nil];}
- (void)applyConfirmed{NSArray *selected=TMCSelectedCompatibilityPlan(self.plan,self.selected);void (^apply)(void)=^{TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){Message(self,@"Git 正在处理",@"请稍后重新预览修复。");self.navigationItem.rightBarButtonItem.enabled=YES;return;}NSError *error=nil;if(!TMCRecordRepairContext(self.root,self.diagnostics,self.logText,&error)||!TMCApplyCompatibilityPlan(self.root,selected,&error)){Message(self,@"修复未应用",error.localizedDescription);self.navigationItem.rightBarButtonItem.enabled=YES;return;}MarkSaved(self.root);[self dismissViewControllerAnimated:YES completion:self.completion];};if([[TMCGitPreferences effective:self.root][@"protect"] boolValue]&&[NSFileManager.defaultManager fileExistsAtPath:[self.root stringByAppendingPathComponent:@".git"]]){self.navigationItem.rightBarButtonItem.enabled=NO;dispatch_async(TMCGitService.queue,^{dispatch_sync(dispatch_get_main_queue(),^{TMCGitLease *transaction __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!transaction){self.navigationItem.rightBarButtonItem.enabled=YES;Message(self,@"Git 正在处理",@"请稍后重试。");return;}TMCGitService *git=[[TMCGitService alloc] initWithRoot:self.root];NSError *error=nil;NSString *checkpoint=[git checkpoint:@"Before compatibility repair" error:&error];if(!checkpoint){self.navigationItem.rightBarButtonItem.enabled=YES;Message(self,@"修复前检查点未创建",error.localizedDescription);return;}apply();});});}else apply();}
@end

@interface StudioDiagnostics : UITableViewController <UIDocumentPickerDelegate>
@property NSString *root;
@property(copy) void (^repairCompletion)(void);
@property NSArray *items;
@property NSString *logText;
@property UIBarButtonItem *scanButton;
@property(copy) void (^selection)(NSDictionary *);
@end
@implementation StudioDiagnostics
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path{TMCEnableLinksInView(cell);}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];TMCEnableLinksInView(self.view);}
- (void)viewDidLoad{[super viewDidLoad];ApplyTheme(self);self.title=@"构建诊断";UIBarButtonItem *log=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.text.magnifyingglass"] style:UIBarButtonItemStylePlain target:self action:@selector(fullLog)];log.accessibilityLabel=@"完整日志";UIBarButtonItem *repair=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"wand.and.stars"] style:UIBarButtonItemStylePlain target:self action:@selector(repair)];repair.accessibilityLabel=@"自动修复适配";repair.enabled=self.root.length>0;self.navigationItem.rightBarButtonItems=@[log,repair];UIBarButtonItem *undo=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.uturn.backward"] style:UIBarButtonItemStylePlain target:self action:@selector(undoRepair)];undo.accessibilityLabel=@"撤回上次修复";undo.enabled=self.root.length&&[NSFileManager.defaultManager fileExistsAtPath:[self.root stringByAppendingPathComponent:@".studio-repair-backup.json"]];self.scanButton=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.shield"] style:UIBarButtonItemStylePlain target:self action:@selector(scanRisks)];self.scanButton.accessibilityLabel=@"手动扫描运行风险";self.scanButton.enabled=self.root.length>0;self.toolbarItems=@[undo,[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],self.scanButton];if(!self.items.count){UILabel *empty=Label(@"暂无构建诊断\n可点击底部盾牌图标手动扫描运行风险",14,NO);empty.textAlignment=NSTextAlignmentCenter;empty.textColor=UIColor.secondaryLabelColor;self.tableView.backgroundView=empty;}}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.navigationController setToolbarHidden:NO animated:animated];}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point{NSDictionary *diagnostic=self.items[indexPath.row];NSString *text=[NSString stringWithFormat:@"%@:%@:%@\n%@",diagnostic[@"file"]?:diagnostic[@"path"],diagnostic[@"line"],diagnostic[@"column"],diagnostic[@"message"]];return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested){return [UIMenu menuWithChildren:@[[UIAction actionWithTitle:@"复制错误信息" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction *action){UIPasteboard.generalPasteboard.string=text;}]]];}];}
- (void)scanRisks{self.scanButton.enabled=NO;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSArray *risks=TFRuntimeRisks(self.root);dispatch_async(dispatch_get_main_queue(),^{self.scanButton.enabled=YES;NSMutableArray *base=[NSMutableArray new];for(NSDictionary *d in self.items)if(!d[@"automaticFix"])[base addObject:d];self.items=base;[self.tableView reloadData];if(!risks.count){Message(self,@"扫描完成",@"未发现当前三类启发式风险；此结果不代表运行验证通过。检查范围：KVC block、objc_msgSend 强制转换、动态类查找。注释与字符串已忽略；宏和复杂表达式可能漏报或误报。仅提供建议，不自动修改。");return;}NSMutableArray *merged=[NSMutableArray new];for(NSDictionary *item in self.items)if(!item[@"automaticFix"])[merged addObject:item];[merged addObjectsFromArray:risks];self.items=merged;self.tableView.backgroundView=nil;[self.tableView reloadData];Message(self,@"运行风险扫描",@"发现项仅为人工核对建议，可能误报；点击可定位源码。不会自动修改回调签名或业务逻辑。");});});}
- (void)repair{NSArray *plan=TMCCompatibilityPlan(self.root,self.items);NSArray *findings=TMCCompatibilityFindings(self.root,self.items);if(!plan.count&&!findings.count){Message(self,@"暂无已识别的适配",@"当前诊断未匹配已验证修复或建议。源码变化后请重新构建；完整日志仍可查看。");return;}StudioRepairPreview *preview=[StudioRepairPreview new];preview.root=self.root;preview.plan=plan;preview.findings=findings;preview.diagnostics=self.items;preview.logText=self.logText;__weak typeof(self) weak=self;preview.completion=^{if(weak.repairCompletion)weak.repairCompletion();weak.toolbarItems.firstObject.enabled=YES;Message(weak,@"适配已应用",@"修复前诊断已存档，请返回重新构建。构建完成后可在适配记录查看前后诊断。");};UINavigationController *nav=[[TMCNavigationController alloc] initWithRootViewController:preview];nav.modalPresentationStyle=UIModalPresentationPageSheet;nav.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.mediumDetent,UISheetPresentationControllerDetent.largeDetent];nav.sheetPresentationController.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierLarge;nav.sheetPresentationController.prefersGrabberVisible=YES;[self presentViewController:nav animated:YES completion:nil];}
- (void)undoRepair{UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"确认撤回上次修复？" message:@"将恢复上次修复涉及的文件。若文件已有后续修改，将停止撤回以保留你的修改。撤回后请重新构建。" preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"撤回修复" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[self undoRepairConfirmed];}]];[self presentViewController:alert animated:YES completion:nil];}
- (void)undoRepairConfirmed{TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){Message(self,@"Git 正在处理",@"请稍后撤回修复。");return;}NSError *error=nil;if(!TMCUndoCompatibilityRepair(self.root,&error)){Message(self,@"撤回未完成",error.localizedDescription);return;}MarkSaved(self.root);if(self.repairCompletion)self.repairCompletion();self.toolbarItems.firstObject.enabled=NO;Message(self,@"已撤回上次修复",@"源码已恢复，请重新构建。");}
- (void)fullLog{StudioText *v=[StudioText new];v.title=@"完整构建日志";v.content=self.logText?:@"暂无日志";[self presentViewController:[[TMCNavigationController alloc] initWithRootViewController:v] animated:YES completion:nil];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section{return self.items.count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)index{NSDictionary *d=self.items[index.row];UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.text=d[@"message"];c.textLabel.font=[UIFont systemFontOfSize:12];c.textLabel.numberOfLines=3;c.detailTextLabel.text=[d[@"line"] integerValue]>0?[NSString stringWithFormat:@"%@ · %@:%@:%@",d[@"severity"],[(d[@"file"]?:d[@"path"]) lastPathComponent],d[@"line"],d[@"column"]]:[NSString stringWithFormat:@"%@ · 查看完整日志",d[@"path"]?:@"构建阶段"];c.detailTextLabel.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];c.imageView.image=[UIImage systemImageNamed:[d[@"severity"] containsString:@"error"]?@"xmark.octagon.fill":@"exclamationmark.triangle.fill"];c.imageView.tintColor=[d[@"severity"] containsString:@"error"]?UIColor.systemRedColor:UIColor.systemOrangeColor;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i{NSDictionary *d=self.items[i.row];[self.navigationController popViewControllerAnimated:YES];void (^jump)(void)=^{if(self.selection)self.selection(d);};id<UIViewControllerTransitionCoordinator> transition=self.navigationController.transitionCoordinator;if(transition)[transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){if(!context.isCancelled)jump();}];else dispatch_async(dispatch_get_main_queue(),jump);}
@end

@interface StudioProjectSettings : UITableViewController
@property NSString *root;
@property NSMutableArray<UITextField *> *fields;
@property UISwitch *packageSwitch;
@property NSString *filterName;
@property NSArray *acceptedValues;
@property NSDictionary *originalFilter;
@property BOOL ambiguousFilter;
@property(copy) void (^completion)(void);
@end
@implementation StudioProjectSettings
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path{TMCEnableLinksInView(cell);}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];TMCEnableLinksInView(self.view);}
- (void)viewDidLoad{[super viewDidLoad];ApplyTheme(self);self.title=@"项目设置";NSDictionary *config=Config(self.root);NSString *invalid=ValidateProjectOptions(self.root,NO);if(invalid){config=@{};self.navigationItem.rightBarButtonItem.enabled=NO;dispatch_async(dispatch_get_main_queue(),^{Message(self,@"请先修正工程配置",invalid);});}NSString *control=[NSString stringWithContentsOfFile:[self.root stringByAppendingPathComponent:@"control"] encoding:NSUTF8StringEncoding error:nil]?:@"";NSMutableDictionary *meta=[NSMutableDictionary new];for(NSString *line in [control componentsSeparatedByString:@"\n"]){NSRange colon=[line rangeOfString:@":"];if(colon.location!=NSNotFound)meta[[line substringToIndex:colon.location]]=[[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];}for(NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.root error:nil])if([f.pathExtension isEqual:@"plist"]){if(self.filterName){self.filterName=nil;self.ambiguousFilter=YES;break;}self.filterName=f;}
 if(self.filterName){id filter=[NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfFile:[self.root stringByAppendingPathComponent:self.filterName]] options:0 format:nil error:nil];if([filter isKindOfClass:NSDictionary.class])self.originalFilter=filter;}
 id filterBody=self.originalFilter[@"Filter"];id bundles=[filterBody isKindOfClass:NSDictionary.class]?filterBody[@"Bundles"]:nil;NSString *target=[bundles isKindOfClass:NSArray.class]?[bundles componentsJoinedByString:@", "]:@"";
 NSArray *values=@[ProjectName(self.root),config[@"productName"]?:@"MobileTweak",meta[@"Package"]?:@"com.example.mobiletweak",meta[@"Version"]?:@"1.0.0",meta[@"Author"]?:@"Developer",meta[@"Description"]?:@"Built on iPhone",target,[OptimizationLevels() containsObject:config[@"optimization"]]?config[@"optimization"]:@"",[config[@"frameworks"] componentsJoinedByString:@", "]?:@"Foundation, UIKit",[config[@"libraries"] componentsJoinedByString:@", "]?:@"",[config[@"includeDirectories"] componentsJoinedByString:@", "]?:@"",[config[@"defines"] componentsJoinedByString:@", "]?:@"",config[@"prefixHeader"]?:@""];
 self.fields=[NSMutableArray new];for(NSString *value in values){UITextField *field=[UITextField new];field.text=value;field.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];field.autocorrectionType=UITextAutocorrectionTypeNo;field.autocapitalizationType=UITextAutocapitalizationTypeNone;field.clearButtonMode=UITextFieldViewModeWhileEditing;[self.fields addObject:field];}self.acceptedValues=[self.fields valueForKey:@"text"];self.packageSwitch=[UISwitch new];self.packageSwitch.on=config[@"package"]?[config[@"package"] boolValue]:YES;

}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 3;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?2:s==1?6:6;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"工程与产物",@"Debian 包与过滤目标",@"编译选项"][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==0?@"工程显示名支持中文；产物名使用英文、数字、点、下划线、加号或短横线。":s==1?@"多个目标 Bundle ID 用英文逗号分隔；其他过滤键保持原值。构建开关、包类型及昵称可进入本项目构建设置；未覆盖的选项跟随全局。":@"列表使用英文逗号分隔。SDK、最低系统版本及包类型在本项目构建设置中选择。高级配置仍可编辑 MobileCompiler.json。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i{UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];if(i.section==1&&i.row==5){cell.textLabel.text=@"构建包类型与产物昵称";cell.textLabel.font=[UIFont systemFontOfSize:13];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;}NSInteger index=i.section==0?i.row:i.section==1?i.row+2:i.row+7;NSArray *captions=@[@"项目名称",@"产物名称",@"Package 包标识",@"Version 版本",@"Author 作者",@"Description 描述",@"目标 Bundle ID",@"优化级别",@"Frameworks",@"Libraries",@"头文件目录",@"预处理宏",@"Prefix Header"];
 {cell.textLabel.text=captions[index];cell.textLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];UILabel *summary=Label([self.fields[index].text length]?self.fields[index].text:index==7?[@"跟随全局 · " stringByAppendingString:GlobalOptimization()]:@"未设置",12,NO);summary.textColor=UIColor.secondaryLabelColor;summary.numberOfLines=2;summary.lineBreakMode=NSLineBreakByTruncatingTail;UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[Label(captions[index],11,YES),summary]];cell.textLabel.text=nil;stack.axis=UILayoutConstraintAxisVertical;stack.spacing=7;stack.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:stack];[NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],[stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],[stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12]]];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;}
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index{[table deselectRowAtIndexPath:index animated:YES];if(!(index.section==1&&index.row==5)){NSUInteger field=index.section==0?index.row:index.section==1?index.row+2:index.row+7;if(field==7){StudioOptimizationPicker *picker=[[StudioOptimizationPicker alloc] initWithStyle:UITableViewStyleInsetGrouped];picker.project=YES;picker.selected=self.fields[7].text;__weak typeof(self) weak=self;picker.completion=^(NSString *value){weak.fields[7].text=value;[weak saveChanges];[weak.tableView reloadRowsAtIndexPaths:@[index] withRowAnimation:UITableViewRowAnimationNone];};[self.navigationController pushViewController:picker animated:YES];return;}StudioValueEditor *editor=[StudioValueEditor new];editor.title=@[@"项目名称",@"产物名称",@"Package 包标识",@"Version 版本",@"Author 作者",@"Description 描述",@"目标 Bundle ID",@"优化级别",@"Frameworks",@"Libraries",@"头文件目录",@"预处理宏",@"Prefix Header"][field];editor.value=self.fields[field].text;editor.helpText=@"点完成后校验并自动保存；列表可按行填写，或用英文逗号分隔。";__weak typeof(self) weak=self;editor.completion=^(NSString *value){NSString *clean=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(field==6||(field>=8&&field<=11))clean=[[clean componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@", "];weak.fields[field].text=clean;[weak saveChanges];[weak.tableView reloadRowsAtIndexPaths:@[index] withRowAnimation:UITableViewRowAnimationNone];};UINavigationController *nav=[[TMCNavigationController alloc] initWithRootViewController:editor];nav.modalPresentationStyle=UIModalPresentationPageSheet;nav.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.mediumDetent,UISheetPresentationControllerDetent.largeDetent];nav.sheetPresentationController.prefersGrabberVisible=YES;[self presentViewController:nav animated:YES completion:nil];return;}if(index.section==1&&index.row==5){StudioBuildPreferences *settings=[[StudioBuildPreferences alloc] initWithStyle:UITableViewStyleInsetGrouped];settings.root=self.root;[self.navigationController pushViewController:settings animated:YES];}}
- (BOOL)persistProject{NSString *invalid=ValidateProject(self.root);if(invalid){Message(self,@"请先修正工程配置",invalid);return NO;}TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){Message(self,@"Git 正在处理",@"请稍后保存项目设置。");return NO;}[self.view endEditing:YES];self.packageSwitch.on=[TMCEffectiveBuildOptions(Config(self.root),NSUserDefaults.standardUserDefaults)[@"package"] boolValue];NSMutableArray *values=[NSMutableArray new];for(UITextField *f in self.fields)[values addObject:[f.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]?:@""];
 NSRegularExpression *binary=[NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9_][A-Za-z0-9_.+\\-]{0,63}$" options:0 error:nil];if(!NameOK(values[0])||![binary numberOfMatchesInString:values[1] options:0 range:NSMakeRange(0,[values[1] length])]){Message(self,@"名称格式有误",@"请检查工程名与产物名。");return NO;}
 for(NSString *v in values)if([v rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound){Message(self,@"字段格式有误",@"请移除字段中的换行或控制字符。");return NO;}
 NSArray *(^list)(NSString *)=^NSArray *(NSString *v){NSMutableArray *result=[NSMutableArray new];for(NSString *part in [v componentsSeparatedByString:@","]){NSString *clean=[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if(clean.length)[result addObject:clean];}return result;};
 NSMutableDictionary *c=[Config(self.root) mutableCopy];c[@"name"]=values[0];c[@"productName"]=values[1];if([values[7] length]&&![OptimizationLevels() containsObject:values[7]]){Message(self,@"优化级别有误",@"请从优化级别页面选择。");return NO;}if([values[7] length])c[@"optimization"]=values[7];else[c removeObjectForKey:@"optimization"];for(NSUInteger i=0;i<4;i++)c[@[@"frameworks",@"libraries",@"includeDirectories",@"defines"][i]]=list(values[i+8]);if([values[12] length]){if(!Child(self.root,values[12])){Message(self,@"路径有误",@"Prefix Header 应在工程目录内。");return NO;}c[@"prefixHeader"]=values[12];}else[c removeObjectForKey:@"prefixHeader"];
 NSMutableDictionary<NSString *,NSData *> *writes=[NSMutableDictionary new];NSError *error=nil;writes[@"MobileCompiler.json"]=[NSJSONSerialization dataWithJSONObject:c options:NSJSONWritingPrettyPrinted error:&error];
 BOOL hasControl=[NSFileManager.defaultManager fileExistsAtPath:[self.root stringByAppendingPathComponent:@"control"]];
 if(self.packageSwitch.on||hasControl||self.filterName){if(self.ambiguousFilter){Message(self,@"过滤配置不明确",@"工程根目录有多个 plist，请先在文件列表核对并保留唯一过滤 plist 后保存打包设置。");return NO;}NSRegularExpression *pkg=[NSRegularExpression regularExpressionWithPattern:@"^[a-z0-9][a-z0-9+.-]+$" options:0 error:nil];if(![pkg numberOfMatchesInString:values[2] options:0 range:NSMakeRange(0,[values[2] length])]||![values[3] length]||(self.packageSwitch.on&&!list(values[6]).count)){Message(self,@"包信息未完整",@"请填写有效包标识、版本和目标 Bundle ID。");return NO;}
 if(self.packageSwitch.on||hasControl){NSMutableDictionary *updates=[@{@"Package":values[2],@"Name":values[0],@"Version":values[3],@"Author":values[4],@"Description":values[5]} mutableCopy];NSString *old=[NSString stringWithContentsOfFile:[self.root stringByAppendingPathComponent:@"control"] encoding:NSUTF8StringEncoding error:nil];NSMutableArray *lines=[NSMutableArray new];BOOL replacing=NO;for(NSString *line in [old?:@"" componentsSeparatedByString:@"\n"]){if(([line hasPrefix:@" "]||[line hasPrefix:@"\t"])&&replacing)continue;NSRange colon=[line rangeOfString:@":"];NSString *key=colon.location!=NSNotFound?[line substringToIndex:colon.location]:nil;replacing=key&&updates[key];if(replacing){[lines addObject:[NSString stringWithFormat:@"%@: %@",key,updates[key]]];[updates removeObjectForKey:key];}else if(line.length)[lines addObject:line];}for(NSString *key in updates)[lines addObject:[NSString stringWithFormat:@"%@: %@",key,updates[key]]];if(!old.length){[lines addObject:@"Architecture: iphoneos-arm64"];[lines addObject:[@"Maintainer: " stringByAppendingString:values[4]]];[lines addObject:@"Section: Tweaks"];}writes[@"control"]=[[[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];}
 if(self.packageSwitch.on||self.filterName){NSMutableDictionary *filter=[self.originalFilter mutableCopy]?:[NSMutableDictionary new];id existing=filter[@"Filter"];NSMutableDictionary *body=[existing isKindOfClass:NSDictionary.class]?[existing mutableCopy]:[NSMutableDictionary new];body[@"Bundles"]=list(values[6]);filter[@"Filter"]=body;NSString *filename=self.filterName?:@"filter.plist";writes[filename]=[NSPropertyListSerialization dataWithPropertyList:filter format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];}}
 if(error){Message(self,@"设置保存失败",error.localizedDescription);return NO;}NSMutableDictionary *backup=[NSMutableDictionary new];NSMutableArray *written=[NSMutableArray new];for(NSString *name in writes){NSString *path=[self.root stringByAppendingPathComponent:name];backup[name]=[NSData dataWithContentsOfFile:path]?:NSNull.null;if(![writes[name] writeToFile:path options:NSDataWritingAtomic error:&error])break;[written addObject:name];}if(error){for(NSString *name in written){NSString *path=[self.root stringByAppendingPathComponent:name];if(backup[name]==NSNull.null)[NSFileManager.defaultManager removeItemAtPath:path error:nil];else[backup[name] writeToFile:path atomically:YES];}Message(self,@"设置保存失败",error.localizedDescription);return NO;}MarkSaved(self.root);if(self.completion)self.completion();return YES;}
- (void)saveChanges{NSArray *before=self.acceptedValues;if([self persistProject]){self.acceptedValues=[self.fields valueForKey:@"text"];self.title=ProjectName(self.root);}else if(before.count==self.fields.count){for(NSUInteger i=0;i<before.count;i++)self.fields[i].text=before[i];[self.tableView reloadData];}}
- (void)commit{[self saveChanges];}

@end

// Paint line numbers in the text view itself: text and numbers share one
// scrolling coordinate system and one keyboard/layout animation transaction.
@interface StudioGutter : UIView
@property(weak) UITextView *textView;
@property NSDictionary<NSNumber *,NSString *> *issues;
@property TMCLineIndex *index;
- (void)drawLineNumbers;
@end
@implementation StudioGutter
- (void)setNeedsDisplay{[super setNeedsDisplay];[self.textView setNeedsDisplay];}
- (void)setHidden:(BOOL)hidden{[super setHidden:hidden];[self.textView setNeedsDisplay];}
- (void)drawLineNumbers {
 UITextView *v=self.textView;if(!v)return;
 NSLayoutManager *lm=v.layoutManager;NSTextContainer *tc=v.textContainer;
 CGFloat left=CGRectGetMinX(v.bounds);
 [UIColor.systemBackgroundColor setFill];UIRectFill(CGRectMake(left,CGRectGetMinY(v.bounds),44,CGRectGetHeight(v.bounds)));
 CGRect visible=CGRectMake(0,MAX(0,v.contentOffset.y-v.textContainerInset.top),v.bounds.size.width,v.bounds.size.height);
 NSRange glyphs=[lm glyphRangeForBoundingRect:visible inTextContainer:tc];
 NSString *text=lm.textStorage.string;NSDictionary *attrs=@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightRegular],NSForegroundColorAttributeName:UIColor.secondaryLabelColor};
 __block NSUInteger line=1;
 NSUInteger start=glyphs.length?[lm characterIndexForGlyphAtIndex:glyphs.location]:0;
 if(!text.length){[@"1" drawAtPoint:CGPointMake(left+20,v.textContainerInset.top) withAttributes:attrs];return;}
 line=[self.index lineAt:start];
 [lm enumerateLineFragmentsForGlyphRange:glyphs usingBlock:^(CGRect fragment,CGRect used,NSTextContainer *container,NSRange range,BOOL *stop){
  NSUInteger c=[lm characterIndexForGlyphAtIndex:range.location];
  line=[self.index lineAt:c];
  BOOL first=c==0||(c<=text.length&&[text characterAtIndex:c-1]=='\n');
  if(first){NSString *severity=self.issues[@(line)];if(severity){UIColor *ink=[severity containsString:@"error"]?UIColor.systemRedColor:UIColor.systemOrangeColor;[ink setFill];[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(left+4,fragment.origin.y+v.textContainerInset.top+5,5,5)] fill];}NSString *n=[NSString stringWithFormat:@"%lu",(unsigned long)line];CGFloat width=[n sizeWithAttributes:attrs].width;[n drawAtPoint:CGPointMake(left+34-width,fragment.origin.y+v.textContainerInset.top+2) withAttributes:attrs];}
 }];
 NSRange visibleCharacters=[lm characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
 if(NSMaxRange(visibleCharacters)>=text.length&&[text hasSuffix:@"\n"]){CGRect extra=lm.extraLineFragmentRect;NSUInteger total=self.index.starts.count;NSString *n=[NSString stringWithFormat:@"%lu",(unsigned long)total];[n drawAtPoint:CGPointMake(left+34-[n sizeWithAttributes:attrs].width,extra.origin.y+v.textContainerInset.top+2) withAttributes:attrs];}
 [UIColor.separatorColor setStroke];UIBezierPath *b=[UIBezierPath bezierPath];[b moveToPoint:CGPointMake(left+42,CGRectGetMinY(v.bounds))];[b addLineToPoint:CGPointMake(left+42,CGRectGetMaxY(v.bounds))];b.lineWidth=.5;[b stroke];
}
@end

// Display-only diagnostic highlight: no attributed text edits or glyph reflow.
@interface StudioDiagnosticLayoutManager : NSLayoutManager
@property(nonatomic) NSRange flashRange;
@end
@implementation StudioDiagnosticLayoutManager
- (void)setFlashRange:(NSRange)range{NSRange old=_flashRange;_flashRange=range;NSUInteger length=self.textStorage.length;if(old.length&&NSMaxRange(old)<=length)[self invalidateDisplayForCharacterRange:old];if(range.length&&NSMaxRange(range)<=length)[self invalidateDisplayForCharacterRange:range];}
- (void)drawBackgroundForGlyphRange:(NSRange)glyphs atPoint:(CGPoint)origin{
 if(self.flashRange.length&&NSMaxRange(self.flashRange)<=self.textStorage.length){NSRange marked=[self glyphRangeForCharacterRange:self.flashRange actualCharacterRange:NULL];NSRange visible=NSIntersectionRange(marked,glyphs);if(visible.length){[[UIColor.systemYellowColor colorWithAlphaComponent:.30] setFill];[self enumerateLineFragmentsForGlyphRange:visible usingBlock:^(CGRect fragment,CGRect used,NSTextContainer *container,NSRange line,BOOL *stop){CGRect r=CGRectOffset(fragment,origin.x,origin.y);UIRectFill(r);}];}}
 [super drawBackgroundForGlyphRange:glyphs atPoint:origin];
}
@end

// Explicit TextKit 1 layout matches the geometry used by line numbers and
// diagnostics. Avoid UITextView's lazy switch from TextKit 2 during drawing.
@interface StudioCodeTextView : UITextView
@property StudioGutter *lineNumbers;
@end
@implementation StudioCodeTextView
- (CGSize)intrinsicContentSize{return CGSizeMake(UIViewNoIntrinsicMetric,UIViewNoIntrinsicMetric);}
- (void)drawRect:(CGRect)rect{[super drawRect:rect];if(!self.lineNumbers.hidden)[self.lineNumbers drawLineNumbers];}
- (void)setContentOffset:(CGPoint)offset{[super setContentOffset:offset];[self setNeedsDisplay];}
- (void)layoutSubviews{CGRect previous=self.bounds;[super layoutSubviews];if(!CGRectEqualToRect(previous,self.bounds))[self setNeedsDisplay];}
@end

@interface UIViewController (TFAIWorkspaceActions)
- (void)background;
- (BOOL)save;
@end
@interface TFAIProjectWorkspace : UIViewController
@property UIViewController *chat,*editor,*active;
@property UISegmentedControl *switcher;
@property UIView *content;
- (void)showEditor;
@end
@implementation TFAIProjectWorkspace
- (void)viewDidLoad{[super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;self.switcher=[[UISegmentedControl alloc]initWithItems:@[@"会话",@"编辑器"]];self.switcher.selectedSegmentIndex=0;[self.switcher addTarget:self action:@selector(changePage) forControlEvents:UIControlEventValueChanged];self.switcher.frame=CGRectMake(0,0,164,32);self.navigationItem.titleView=self.switcher;self.content=[UIView new];self.content.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.content];[NSLayoutConstraint activateConstraints:@[[self.content.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[self.content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.content.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];[self changePage];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.active beginAppearanceTransition:NO animated:animated];}
- (BOOL)shouldAutomaticallyForwardAppearanceMethods{return NO;}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.active beginAppearanceTransition:YES animated:animated];self.navigationItem.rightBarButtonItems=self.active.navigationItem.rightBarButtonItems;}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];[self.active endAppearanceTransition];}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];[self.active endAppearanceTransition];}
- (void)showEditor{[self loadViewIfNeeded];self.switcher.selectedSegmentIndex=1;[self changePage];}
- (void)changePage{UIViewController *next=self.switcher.selectedSegmentIndex?self.editor:self.chat;if(next==self.active)return;[self.view endEditing:YES];if(self.active==self.editor&&![self.editor save]){self.switcher.selectedSegmentIndex=1;return;}UIViewController *old=self.active;[old beginAppearanceTransition:NO animated:NO];[old.view removeFromSuperview];[old endAppearanceTransition];if(!next.parentViewController){[self addChildViewController:next];[next didMoveToParentViewController:self];}[next beginAppearanceTransition:YES animated:NO];next.view.frame=self.content.bounds;next.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self.content addSubview:next.view];[next endAppearanceTransition];self.active=next;self.title=@"";self.navigationItem.titleView=self.switcher;self.navigationItem.rightBarButtonItems=next.navigationItem.rightBarButtonItems;self.navigationItem.leftBarButtonItems=nil;self.navigationItem.backButtonTitle=@"AI 会话";}
@end

@interface StudioEditor : UIViewController <UITextViewDelegate>
@property NSString *root;
@property NSString *filename;
@property UITextView *editor;
@property UILabel *saved;
@property UIButton *logButton;
@property UILabel *logTitle;
@property UILabel *logDetail;
@property UIImageView *logIcon;
@property UILabel *language;
@property UILabel *position;
@property UILabel *sdkLabel;
@property StudioGutter *gutter;
@property(copy) void (^initialSyntaxReady)(void);
@property TMCLogTransition *logTransition;
@property BOOL highlighting;
@property NSUInteger syntaxRevision;
@property NSArray *fileDiagnostics;
@property NSArray *cachedDiagnostics;
@property NSString *diagnosticsStamp;
@property NSString *diagnosticSource;
@property NSRange jumpRange;
@property NSDictionary *pendingDiagnostic;
@property NSUInteger jumpRevision;
@property UILabel *diagnosticHint;
@property NSUInteger searchOffset;
@property NSString *searchQuery;
@property NSString *replacement;
@property UISegmentedControl *tabs;
@property UIScrollView *tabScroll;
@property UIStackView *tabRow;
@property NSMutableArray<NSString *> *opened;
@property UIStackView *layout;
@property UIButton *dismissKeyboardItem;
@property UIView *consolePanel;
@property UIView *statusPanel;
@property UIView *metadataPanel;
@property CompilerController *engine;
@property(weak) UINavigationController *aiNavigation;
@property NSTimer *timer;
@property BOOL dirty;
@property NSData *loadedData;
@property NSDictionary *pendingDraft;
@property BOOL conflictPending;
@property NSMutableDictionary *documentPositions;
@property NSProgress *snapshotProgress;
@property UIScrollView *symbolScroll;
@property dispatch_queue_t draftQueue;
@property BOOL followingLog;
@property UIButton *logBottomButton;
@property BOOL busy;
@property BOOL fullLog;
@property BOOL keyboardVisible;
@property BOOL editorVisible;
@property BOOL syntaxDeferred;
@property BOOL logVisible;
@property UIButton *logToggleItem;
@property UIButton *closeAllButton;
@property UITextView *logView;
@property(weak) StudioText *logController;
@property NSString *snapshot;
@end
@implementation StudioEditor
- (void)viewDidLoad { [super viewDidLoad];ApplyTheme(self);self.title=ProjectName(self.root);self.view.backgroundColor=UIColor.systemBackgroundColor;self.engine=[CompilerController new];[self.engine loadViewIfNeeded];self.engine.importedProject=self.root;self.engine.lastBuild=nil;NSString *previousBuild=[NSUserDefaults.standardUserDefaults stringForKey:[@"StudioBuild-" stringByAppendingString:self.root.lastPathComponent]];if(previousBuild)self.engine.lastBuild=[Docs() stringByAppendingPathComponent:previousBuild];self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"house"] style:UIBarButtonItemStylePlain target:self action:@selector(home)];self.navigationItem.rightBarButtonItems=@[[self makeBuildButton],[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"] style:UIBarButtonItemStylePlain target:self action:@selector(files)],[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(menu)]];
 UIStackView *s=Stack(self.view);self.layout=s;s.spacing=0;[NSLayoutConstraint activateConstraints:@[[s.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:0],[s.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:0],[s.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:0],[s.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:0]]];
 self.documentPositions=[NSMutableDictionary new];self.draftQueue=dispatch_queue_create("studio.draft",DISPATCH_QUEUE_SERIAL);self.opened=[NSMutableArray new];self.tabScroll=[UIScrollView new];self.tabScroll.showsHorizontalScrollIndicator=NO;self.tabRow=[[UIStackView alloc] initWithFrame:CGRectZero];self.tabRow.axis=UILayoutConstraintAxisHorizontal;self.tabRow.spacing=0;self.tabRow.translatesAutoresizingMaskIntoConstraints=NO;[self.tabScroll addSubview:self.tabRow];[NSLayoutConstraint activateConstraints:@[[self.tabRow.leadingAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.leadingAnchor],[self.tabRow.trailingAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.trailingAnchor],[self.tabRow.topAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.topAnchor],[self.tabRow.bottomAnchor constraintEqualToAnchor:self.tabScroll.contentLayoutGuide.bottomAnchor],[self.tabRow.heightAnchor constraintEqualToAnchor:self.tabScroll.frameLayoutGuide.heightAnchor],[self.tabScroll.heightAnchor constraintEqualToConstant:44]]];UIView *tabBar=[UIView new];[tabBar.heightAnchor constraintEqualToConstant:44].active=YES;[s addArrangedSubview:tabBar];self.tabScroll.translatesAutoresizingMaskIntoConstraints=NO;[tabBar addSubview:self.tabScroll];self.closeAllButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.closeAllButton setImage:[UIImage systemImageNamed:@"xmark.square"] forState:UIControlStateNormal];self.closeAllButton.accessibilityLabel=@"关闭全部文件标签";self.closeAllButton.tintColor=UIColor.secondaryLabelColor;self.closeAllButton.translatesAutoresizingMaskIntoConstraints=NO;[self.closeAllButton addTarget:self action:@selector(closeAllFiles) forControlEvents:UIControlEventTouchUpInside];[tabBar addSubview:self.closeAllButton];[NSLayoutConstraint activateConstraints:@[[self.tabScroll.leadingAnchor constraintEqualToAnchor:tabBar.leadingAnchor],[self.tabScroll.topAnchor constraintEqualToAnchor:tabBar.topAnchor],[self.tabScroll.bottomAnchor constraintEqualToAnchor:tabBar.bottomAnchor],[self.tabScroll.trailingAnchor constraintEqualToAnchor:self.closeAllButton.leadingAnchor],[self.closeAllButton.trailingAnchor constraintEqualToAnchor:tabBar.trailingAnchor],[self.closeAllButton.topAnchor constraintEqualToAnchor:tabBar.topAnchor],[self.closeAllButton.bottomAnchor constraintEqualToAnchor:tabBar.bottomAnchor],[self.closeAllButton.widthAnchor constraintEqualToConstant:44]]];
 self.tabScroll.backgroundColor=UIColor.secondarySystemBackgroundColor;
 UIView *meta=[UIView new];self.metadataPanel=meta;[meta.heightAnchor constraintEqualToConstant:32].active=YES;[s addArrangedSubview:meta];
 self.language=Label(@"OBJECTIVE-C",9,YES);self.language.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightMedium];self.language.textColor=UIColor.secondaryLabelColor;
 self.saved=Label(@"已保存于本机",10,NO);self.saved.numberOfLines=1;self.saved.textColor=UIColor.secondaryLabelColor;
 for(UIView *v in @[self.language,self.saved]){v.translatesAutoresizingMaskIntoConstraints=NO;[meta addSubview:v];}
 [NSLayoutConstraint activateConstraints:@[[self.language.leadingAnchor constraintEqualToAnchor:meta.leadingAnchor constant:16],[self.language.centerYAnchor constraintEqualToAnchor:meta.centerYAnchor],[self.saved.trailingAnchor constraintEqualToAnchor:meta.trailingAnchor constant:-16],[self.saved.centerYAnchor constraintEqualToAnchor:meta.centerYAnchor],[self.saved.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.language.trailingAnchor constant:12]]];
 UIView *code=[UIView new];[s addArrangedSubview:code];NSLayoutConstraint *codeMinimum=[code.heightAnchor constraintGreaterThanOrEqualToConstant:44];codeMinimum.priority=750;codeMinimum.active=YES;
 NSTextStorage *storage=[NSTextStorage new];NSLayoutManager *manager=[StudioDiagnosticLayoutManager new];manager.allowsNonContiguousLayout=YES;[storage addLayoutManager:manager];
 NSTextContainer *container=[[NSTextContainer alloc] initWithSize:CGSizeMake(0,CGFLOAT_MAX)];container.widthTracksTextView=YES;container.heightTracksTextView=NO;[manager addTextContainer:container];
 self.editor=[[StudioCodeTextView alloc] initWithFrame:CGRectZero textContainer:container];self.editor.scrollEnabled=YES;self.editor.alwaysBounceVertical=YES;self.editor.clipsToBounds=YES;self.editor.font=[UIFont monospacedSystemFontOfSize:[NSUserDefaults.standardUserDefaults integerForKey:@"StudioFont"]?:14 weight:UIFontWeightRegular];self.editor.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;self.editor.backgroundColor=UIColor.clearColor;self.editor.textContainerInset=UIEdgeInsetsMake(12,48,20,12);self.editor.autocorrectionType=UITextAutocorrectionTypeNo;self.editor.autocapitalizationType=UITextAutocapitalizationTypeNone;self.editor.textColor=UIColor.labelColor;self.editor.smartQuotesType=UITextSmartQuotesTypeNo;self.editor.smartDashesType=UITextSmartDashesTypeNo;self.editor.smartInsertDeleteType=UITextSmartInsertDeleteTypeNo;self.editor.delegate=self;self.editor.accessibilityLabel=@"源码编辑器";self.editor.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;self.editor.translatesAutoresizingMaskIntoConstraints=NO;[code addSubview:self.editor];
 [NSLayoutConstraint activateConstraints:@[[self.editor.leadingAnchor constraintEqualToAnchor:code.leadingAnchor],[self.editor.trailingAnchor constraintEqualToAnchor:code.trailingAnchor],[self.editor.topAnchor constraintEqualToAnchor:code.topAnchor],[self.editor.bottomAnchor constraintEqualToAnchor:code.bottomAnchor]]];
 self.diagnosticHint=Label(@"",11,NO);self.diagnosticHint.numberOfLines=2;self.diagnosticHint.backgroundColor=UIColor.secondarySystemBackgroundColor;self.diagnosticHint.textColor=UIColor.systemRedColor;self.diagnosticHint.translatesAutoresizingMaskIntoConstraints=NO;self.diagnosticHint.hidden=YES;[code addSubview:self.diagnosticHint];[NSLayoutConstraint activateConstraints:@[[self.diagnosticHint.leadingAnchor constraintEqualToAnchor:code.leadingAnchor constant:48],[self.diagnosticHint.trailingAnchor constraintEqualToAnchor:code.trailingAnchor constant:-12],[self.diagnosticHint.bottomAnchor constraintEqualToAnchor:code.bottomAnchor constant:-8]]];
 self.gutter=[StudioGutter new];self.gutter.index=[TMCLineIndex new];self.gutter.textView=self.editor;((StudioCodeTextView *)self.editor).lineNumbers=self.gutter;
 UIView *accessory=[UIView new];accessory.translatesAutoresizingMaskIntoConstraints=NO;[accessory.heightAnchor constraintEqualToConstant:48].active=YES;
 self.symbolScroll=[UIScrollView new];self.symbolScroll.showsHorizontalScrollIndicator=NO;self.symbolScroll.translatesAutoresizingMaskIntoConstraints=NO;[accessory addSubview:self.symbolScroll];
 UIStackView *symbols=[UIStackView new];symbols.axis=UILayoutConstraintAxisHorizontal;symbols.translatesAutoresizingMaskIntoConstraints=NO;[self.symbolScroll addSubview:symbols];
 __weak typeof(self) symbolEditor=self;for(NSString *symbol in @[@"⇥",@"{",@"}",@"(",@")",@";",@"\"",@"#"]){UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:symbol forState:UIControlStateNormal];button.accessibilityLabel=[@"插入 " stringByAppendingString:symbol];[button.widthAnchor constraintEqualToConstant:44].active=YES;[button addAction:[UIAction actionWithHandler:^(UIAction *a){[symbolEditor.editor insertText:[symbol isEqual:@"⇥"]?@"    ":symbol];}] forControlEvents:UIControlEventTouchUpInside];[symbols addArrangedSubview:button];}
 // Plain buttons intentionally avoid UIToolbar's automatic iOS 26 glass groups.
 UIStackView *tools=[UIStackView new];tools.axis=UILayoutConstraintAxisHorizontal;tools.distribution=UIStackViewDistributionFillEqually;tools.translatesAutoresizingMaskIntoConstraints=NO;[accessory addSubview:tools];
 NSArray *toolSymbols=@[@"terminal",@"text.badge.plus",@"magnifyingglass",@"keyboard.chevron.compact.up"];
 NSArray *toolLabels=@[@"显示构建日志",@"代码片段与编辑操作",@"查找与替换",@"展开键盘"];
 NSArray *toolActions=@[NSStringFromSelector(@selector(toggleLog)),NSStringFromSelector(@selector(suggestions)),NSStringFromSelector(@selector(search)),NSStringFromSelector(@selector(toggleKeyboard))];
 for(NSUInteger i=0;i<toolSymbols.count;i++){
  UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
  [button setImage:[UIImage systemImageNamed:toolSymbols[i]]?:[UIImage systemImageNamed:@"keyboard"] forState:UIControlStateNormal];
  button.tintColor=UIColor.secondaryLabelColor;button.accessibilityLabel=toolLabels[i];
  [button addTarget:self action:NSSelectorFromString(toolActions[i]) forControlEvents:UIControlEventTouchUpInside];
  [tools addArrangedSubview:button];
  if(i==0)self.logToggleItem=button;if(i==3)self.dismissKeyboardItem=button;
 }
 [NSLayoutConstraint activateConstraints:@[[self.symbolScroll.leadingAnchor constraintEqualToAnchor:accessory.leadingAnchor constant:4],[self.symbolScroll.topAnchor constraintEqualToAnchor:accessory.topAnchor],[self.symbolScroll.bottomAnchor constraintEqualToAnchor:accessory.bottomAnchor],[self.symbolScroll.trailingAnchor constraintEqualToAnchor:tools.leadingAnchor],[tools.trailingAnchor constraintEqualToAnchor:accessory.trailingAnchor],[tools.topAnchor constraintEqualToAnchor:accessory.topAnchor],[tools.bottomAnchor constraintEqualToAnchor:accessory.bottomAnchor],[tools.widthAnchor constraintEqualToConstant:176],[symbols.leadingAnchor constraintEqualToAnchor:self.symbolScroll.contentLayoutGuide.leadingAnchor],[symbols.trailingAnchor constraintEqualToAnchor:self.symbolScroll.contentLayoutGuide.trailingAnchor],[symbols.topAnchor constraintEqualToAnchor:self.symbolScroll.contentLayoutGuide.topAnchor],[symbols.bottomAnchor constraintEqualToAnchor:self.symbolScroll.contentLayoutGuide.bottomAnchor],[symbols.heightAnchor constraintEqualToAnchor:self.symbolScroll.frameLayoutGuide.heightAnchor]]];
 UIView *console=[UIView new];self.consolePanel=console;console.backgroundColor=UIColor.secondarySystemBackgroundColor;[s addArrangedSubview:console];NSLayoutConstraint *consoleHeight=[console.heightAnchor constraintEqualToConstant:66];consoleHeight.priority=999;consoleHeight.active=YES;
 self.logIcon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"terminal"]];self.logIcon.tintColor=Gold();self.logTitle=Label(@"构建日志",13,YES);self.logTitle.numberOfLines=1;self.logDetail=Label(@"准备就绪，编译反馈会出现在这里。",10,NO);self.logDetail.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];self.logDetail.textColor=UIColor.secondaryLabelColor;self.logDetail.numberOfLines=1;self.logDetail.userInteractionEnabled=YES;UILongPressGestureRecognizer *copyError=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(copyBuildError:)];[self.logDetail addGestureRecognizer:copyError];
 UIImageView *expand=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.up"]];expand.tintColor=UIColor.secondaryLabelColor;
 for(UIView *v in @[self.logIcon,self.logTitle,self.logDetail,expand]){v.translatesAutoresizingMaskIntoConstraints=NO;[console addSubview:v];}
 [NSLayoutConstraint activateConstraints:@[[self.logIcon.leadingAnchor constraintEqualToAnchor:console.leadingAnchor constant:16],[self.logIcon.topAnchor constraintEqualToAnchor:console.topAnchor constant:12],[self.logIcon.widthAnchor constraintEqualToConstant:15],[self.logIcon.heightAnchor constraintEqualToConstant:15],[self.logTitle.leadingAnchor constraintEqualToAnchor:self.logIcon.trailingAnchor constant:8],[self.logTitle.centerYAnchor constraintEqualToAnchor:self.logIcon.centerYAnchor],[self.logTitle.trailingAnchor constraintLessThanOrEqualToAnchor:expand.leadingAnchor constant:-8],[expand.trailingAnchor constraintEqualToAnchor:console.trailingAnchor constant:-18],[expand.centerYAnchor constraintEqualToAnchor:self.logIcon.centerYAnchor],[self.logDetail.leadingAnchor constraintEqualToAnchor:console.leadingAnchor constant:16],[self.logDetail.trailingAnchor constraintEqualToAnchor:console.trailingAnchor constant:-16],[self.logDetail.topAnchor constraintEqualToAnchor:self.logTitle.bottomAnchor constant:7]]];
 self.logButton=[UIButton buttonWithType:UIButtonTypeCustom];self.logButton.accessibilityLabel=@"展开构建日志";self.logButton.translatesAutoresizingMaskIntoConstraints=NO;[console addSubview:self.logButton];[NSLayoutConstraint activateConstraints:@[[self.logButton.leadingAnchor constraintEqualToAnchor:console.leadingAnchor],[self.logButton.trailingAnchor constraintEqualToAnchor:console.trailingAnchor],[self.logButton.topAnchor constraintEqualToAnchor:console.topAnchor],[self.logButton.bottomAnchor constraintEqualToAnchor:console.bottomAnchor]]];[self.logButton addTarget:self action:@selector(buildFeedback) forControlEvents:UIControlEventTouchUpInside];[self.logButton addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(copyBuildError:)]];
 [s addArrangedSubview:accessory];
 UIView *status=[UIView new];self.statusPanel=status;NSLayoutConstraint *statusHeight=[status.heightAnchor constraintEqualToConstant:26];statusHeight.priority=999;statusHeight.active=YES;[s addArrangedSubview:status];UILabel *arch=Label(@"",11,NO);self.sdkLabel=arch;arch.textColor=UIColor.secondaryLabelColor;self.position=Label(@"行1·列1",11,NO);self.position.textColor=UIColor.secondaryLabelColor;for(UIView *v in @[arch,self.position]){v.translatesAutoresizingMaskIntoConstraints=NO;[status addSubview:v];}[NSLayoutConstraint activateConstraints:@[[arch.leadingAnchor constraintEqualToAnchor:status.leadingAnchor constant:16],[arch.centerYAnchor constraintEqualToAnchor:status.centerYAnchor],[self.position.trailingAnchor constraintEqualToAnchor:status.trailingAnchor constant:-16],[self.position.centerYAnchor constraintEqualToAnchor:status.centerYAnchor]]];
 NSString *first=nil;NSArray *sources=Config(self.root)[@"sources"];if([sources isKindOfClass:NSArray.class])for(id f in sources)if([f isKindOfClass:NSString.class]&&Child(self.root,f)){first=f;break;}if(!first)for(NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.root error:nil])if([@[@"x",@"m",@"xm",@"mm",@"c",@"cpp"] containsObject:f.pathExtension]){first=f;break;}NSDictionary *draft=TMCReadDraft(self.root);self.pendingDraft=draft;if([draft isKindOfClass:NSDictionary.class]&&[draft[@"file"] isKindOfClass:NSString.class]&&Child(self.root,draft[@"file"]))first=draft[@"file"];NSData *workspaceData=[NSData dataWithContentsOfFile:[self.root stringByAppendingPathComponent:@".studio-workspace.json"]];id workspace=workspaceData?[NSJSONSerialization JSONObjectWithData:workspaceData options:0 error:nil]:nil;
 if([workspace isKindOfClass:NSDictionary.class]&&[workspace[@"opened"] isKindOfClass:NSArray.class]){if([workspace[@"positions"] isKindOfClass:NSDictionary.class])for(NSString *key in workspace[@"positions"]){id v=workspace[@"positions"][key];if([v isKindOfClass:NSDictionary.class]&&[v[@"location"] isKindOfClass:NSNumber.class]&&[v[@"length"] isKindOfClass:NSNumber.class]&&[v[@"y"] isKindOfClass:NSNumber.class])self.documentPositions[key]=v;}for(id name in workspace[@"opened"]){NSString *path=[name isKindOfClass:NSString.class]?Child(self.root,name):nil;NSDictionary *attributes=path?[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil]:nil;if([attributes[NSFileType] isEqual:NSFileTypeRegular]&&[attributes[NSFileSize] unsignedLongLongValue]<=2*1024*1024&&![self.opened containsObject:name])[self.opened addObject:name];}id selected=workspace[@"selected"];first=[selected isKindOfClass:NSString.class]&&[self.opened containsObject:selected]?selected:self.opened.firstObject;}
 if([draft isKindOfClass:NSDictionary.class]&&[draft[@"file"] isKindOfClass:NSString.class]&&Child(self.root,draft[@"file"]))first=draft[@"file"];
 if(first)[self openFile:first];else[self showEmptyEditor];
 [self updateLogVisibility];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(background) name:UIApplicationWillResignActiveNotification object:nil];[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recheckDisk) name:UIApplicationDidBecomeActiveNotification object:nil];if(self.engine.lastBuild)dispatch_async(dispatch_get_main_queue(),^{[self refreshBuild];}); }
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];self.editorVisible=YES;NSDictionary *sdkInfo=TMCSDKBuildSettings(Config(self.root),NSUserDefaults.standardUserDefaults,nil);self.sdkLabel.text=[NSString stringWithFormat:@"%@ · SDK %@ · iOS %@+",Config(self.root)[@"cpuArchitecture"]?:@"arm64",sdkInfo[@"sdkVersion"]?:@"?",sdkInfo[@"deploymentTarget"]?:@"?"];self.navigationController.toolbarHidden=YES;ApplyTheme(self);UIFont *font=[UIFont monospacedSystemFontOfSize:[NSUserDefaults.standardUserDefaults integerForKey:@"StudioFont"]?:14 weight:UIFontWeightRegular];if(![self.editor.font isEqual:font]){self.editor.font=font;[self highlight];}}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];self.editorVisible=NO;self.syntaxRevision++;[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(highlight) object:nil];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];self.editorVisible=YES;[self recheckDisk];self.title=ProjectName(self.root);if(self.syntaxDeferred){self.syntaxDeferred=NO;[self highlight];}}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];BOOL compact=self.keyboardVisible&&self.view.bounds.size.width>self.view.bounds.size.height;if(self.metadataPanel.hidden!=compact)self.metadataPanel.hidden=compact;}
- (void)keyboardChanged:(NSNotification *)note {
 if(!self.isViewLoaded||!self.view.window||(!self.keyboardVisible&&!self.editor.isFirstResponder))return;
 CGRect screenFrame=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
 CGRect frame=[self.view convertRect:screenFrame fromView:nil];
 BOOL visible=![note.name isEqual:UIKeyboardWillHideNotification]&&CGRectGetMaxY(frame)>=CGRectGetHeight(self.view.bounds)-1&&CGRectGetMinY(frame)<CGRectGetHeight(self.view.bounds)-40;
 [self updateKeyboardButton:visible];
 // keyboardLayoutGuide already follows the system keyboard. Do not animate
 // the entire stack a second time or let hidden rows interpolate the viewport.
 [UIView performWithoutAnimation:^{self.keyboardVisible=visible;[self updateLogVisibility];self.statusPanel.hidden=visible;[self.view layoutIfNeeded];[self.editor setNeedsDisplay];}];
}
- (void)background{[self flushDraft];[self save];[self persistWorkspace];}
- (void)recheckDisk{if(!self.filename||self.dirty||self.busy)return;NSData *current=[NSData dataWithContentsOfFile:Child(self.root,self.filename)];if(!current){[self showEmptyEditor];return;}if(current&&![current isEqual:self.loadedData]){NSString *file=self.filename;[self openFile:file];self.saved.text=@"已载入磁盘最新版本";}}

- (void)dealloc{[NSObject cancelPreviousPerformRequestsWithTarget:self];[self.timer invalidate];[[NSNotificationCenter defaultCenter] removeObserver:self];}
- (void)updateKeyboardButton:(BOOL)visible{
 [self.dismissKeyboardItem setImage:[UIImage systemImageNamed:visible?@"keyboard.chevron.compact.down":@"keyboard.chevron.compact.up"]?:[UIImage systemImageNamed:@"keyboard"] forState:UIControlStateNormal];
 self.dismissKeyboardItem.accessibilityLabel=visible?@"收起键盘":@"展开键盘";
 self.dismissKeyboardItem.accessibilityValue=visible?@"已展开":@"已收起";
}
- (void)toggleKeyboard{
 if(self.editor.isFirstResponder){[self endEditing];}
 else if(self.filename){[self.editor becomeFirstResponder];}
 [self updateKeyboardButton:self.editor.isFirstResponder];
}
- (void)endEditing{[self.editor resignFirstResponder];[self save];}
- (void)symbol:(UIBarButtonItem *)b{if(!self.filename)return;[self.editor insertText:[b.title isEqual:@"⇥"]?@"    ":b.title];}
- (void)flushDraft{
 if(!self.dirty||!self.filename)return;
 NSDictionary *draft=@{@"file":self.filename,@"text":self.editor.text?:@"",@"base":self.loadedData?[self.loadedData base64EncodedStringWithOptions:0]:@""};
 NSString *path=[self.root stringByAppendingPathComponent:@".studio-draft.json"];
 dispatch_async(self.draftQueue,^{NSError *error=nil;if(!JSONWrite(draft,path,&error))dispatch_async(dispatch_get_main_queue(),^{if(self.dirty){self.saved.text=@"草稿保存失败，请立即导出源码";self.saved.textColor=UIColor.systemRedColor;}});});
}
- (void)resolveSaveConflict{
 if(self.conflictPending||self.presentedViewController)return;self.conflictPending=YES;
 UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"文件出现外部修改" message:@"当前编辑内容和磁盘版本均已保留。重新载入前会另存当前内容，避免丢失修改。" preferredStyle:UIAlertControllerStyleAlert];
 [sheet addAction:[UIAlertAction actionWithTitle:@"保留我的修改" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){self.conflictPending=NO;NSString *path=Child(self.root,self.filename);NSData *disk=[NSData dataWithContentsOfFile:path];NSString *backup=[self.root stringByAppendingPathComponent:[NSString stringWithFormat:@".studio-conflict-%@.bak",NSUUID.UUID.UUIDString]];NSError *error=nil;if(!disk||![disk writeToFile:backup options:NSDataWritingAtomic error:&error]){Message(self,@"备份失败",error.localizedDescription?:@"磁盘版本已变化，请重新载入");return;}self.loadedData=disk;[self save];}]];
 [sheet addAction:[UIAlertAction actionWithTitle:@"另存当前内容并重新载入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){self.conflictPending=NO;NSString *copy=[NSString stringWithFormat:@"%@-conflict-%@.%@",self.filename.lastPathComponent.stringByDeletingPathExtension,NSUUID.UUID.UUIDString,self.filename.pathExtension];NSError *error=nil;if(![self.editor.text writeToFile:Child(self.root,copy) atomically:YES encoding:NSUTF8StringEncoding error:&error]){Message(self,@"另存失败",error.localizedDescription);return;}self.dirty=NO;NSString *file=self.filename;self.filename=nil;[self openFile:file];self.saved.text=[@"当前编辑已另存：" stringByAppendingString:copy];}]];
 [sheet addAction:[UIAlertAction actionWithTitle:@"继续检查" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){self.conflictPending=NO;}]];[self presentViewController:sheet animated:YES completion:nil];
}
- (BOOL)save {
 if(!self.dirty)return YES;
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushDraft) object:nil];[self flushDraft];
 TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){self.saved.text=@"Git 正在处理，稍后重试保存";[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(save) object:nil];[self performSelector:@selector(save) withObject:nil afterDelay:.8];return NO;}
 NSError *error=nil;NSString *path=Child(self.root,self.filename);
 if(!TMCWriteDocument(path,self.loadedData,self.editor.text,&error)){self.saved.text=error.code==409?@"外部修改冲突 · 当前编辑已保留":@"保存失败，请导出源码或重试";self.saved.textColor=UIColor.systemRedColor;if(error.code==409)[self resolveSaveConflict];return NO;}
 self.loadedData=[self.editor.text dataUsingEncoding:NSUTF8StringEncoding];self.dirty=NO;
 if([self.filename isEqual:@"control"])self.title=ProjectName(self.root);MarkSaved(self.root);self.saved.text=@"已保存于本机";self.saved.textColor=UIColor.secondaryLabelColor;
 NSString *draft=[self.root stringByAppendingPathComponent:@".studio-draft.json"];dispatch_async(self.draftQueue,^{[NSFileManager.defaultManager removeItemAtPath:draft error:nil];});return YES;
}
- (void)textViewDidChange:(UITextView *)textView {
 if(self.highlighting)return;self.pendingDiagnostic=nil;[self clearDiagnosticFlash];[self.gutter.index update:textView.text];[self textViewDidChangeSelection:textView];self.jumpRevision++;self.jumpRange=NSMakeRange(0,0);self.diagnosticHint.hidden=YES;self.syntaxRevision++;
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(highlight) object:nil];[self performSelector:@selector(highlight) withObject:nil afterDelay:.15];self.dirty=YES;self.saved.text=@"正在保存…";
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushDraft) object:nil];[self performSelector:@selector(flushDraft) withObject:nil afterDelay:.3];
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(save) object:nil];[self performSelector:@selector(save) withObject:nil afterDelay:.8];
}
- (void)openFile:(NSString *)f{
 if(![self save])return;
 if(self.filename)self.documentPositions[self.filename]=@{@"location":@(self.editor.selectedRange.location),@"length":@(self.editor.selectedRange.length),@"y":@(self.editor.contentOffset.y)};
 NSString *path=Child(self.root,f);NSDictionary *at=path?[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil]:nil;
 if([at[NSFileSize] unsignedLongLongValue]>2*1024*1024){Message(self,@"文件较大",@"当前编辑器最多打开 2 MB 文本；源码仍完整保留。");return;}
 NSError *error=nil;NSData *bytes=path?[NSData dataWithContentsOfFile:path options:0 error:&error]:nil;NSString *text=bytes?[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding]:nil;
 if(!text){Message(self,@"读取文件出错",error.localizedDescription?:@"请选择 UTF-8 文本文件");return;}
 [self clearDiagnosticFlash];self.pendingDiagnostic=nil;self.syntaxRevision++;self.filename=f;self.loadedData=bytes;self.gutter.hidden=NO;self.editor.editable=YES;self.jumpRevision++;self.jumpRange=NSMakeRange(0,0);self.diagnosticHint.hidden=YES;
 [self.editor.undoManager removeAllActions];self.editor.text=text;[self.editor.undoManager removeAllActions];
 if(![self.opened containsObject:f])[self.opened addObject:f];[self updateTabs];self.saved.text=@"已保存于本机";self.navigationItem.prompt=nil;self.searchOffset=0;
 NSDictionary *draft=self.pendingDraft;
 if([draft[@"file"] isEqual:f]){self.pendingDraft=nil;self.editor.text=draft[@"text"];self.loadedData=[[NSData alloc] initWithBase64EncodedString:draft[@"base"]?:@"" options:0];self.dirty=YES;self.saved.text=@"已恢复草稿 · 等待保存";[self.editor.undoManager removeAllActions];}
 [self.gutter.index update:self.editor.text];NSDictionary *position=self.documentPositions[f];NSUInteger location=MIN([position[@"location"] unsignedIntegerValue],self.editor.text.length),length=MIN([position[@"length"] unsignedIntegerValue],self.editor.text.length-location);self.editor.selectedRange=NSMakeRange(location,length);
 NSUInteger revision=self.syntaxRevision;dispatch_async(dispatch_get_main_queue(),^{if(revision!=self.syntaxRevision)return;[self loadFileDiagnostics];[self highlight];[self.editor.layoutManager ensureLayoutForTextContainer:self.editor.textContainer];[self.editor setContentOffset:CGPointMake(0,MAX(-self.editor.adjustedContentInset.top,MIN([position[@"y"] doubleValue],self.editor.contentSize.height-self.editor.bounds.size.height))) animated:NO];[self persistWorkspace];});
}
- (void)persistWorkspace{if(self.filename)self.documentPositions[self.filename]=@{@"location":@(self.editor.selectedRange.location),@"length":@(self.editor.selectedRange.length),@"y":@(self.editor.contentOffset.y)};JSONWrite(@{@"opened":self.opened?:@[],@"selected":self.filename?:@"",@"positions":self.documentPositions?:@{}},[self.root stringByAppendingPathComponent:@".studio-workspace.json"],nil);}
- (void)showEmptyEditor{self.filename=nil;self.dirty=NO;self.gutter.hidden=YES;[self.editor.undoManager removeAllActions];self.editor.text=@"";[self.editor.undoManager removeAllActions];self.editor.editable=NO;self.syntaxRevision++;self.fileDiagnostics=@[];self.gutter.issues=@{};[self.gutter setNeedsDisplay];self.diagnosticHint.hidden=YES;self.language.text=@"没有打开的文件";self.saved.text=@"点击文件夹选择文件";self.position.text=@"行0·列0";[self updateTabs];}
- (void)closeFile:(NSString *)name{if(![self save])return;NSUInteger index=[self.opened indexOfObject:name];if(index==NSNotFound)return;BOOL current=[self.filename isEqual:name];[self.opened removeObject:name];if(current){NSString *next=self.opened.count?self.opened[MIN(index,self.opened.count-1)]:nil;if(next)[self openFile:next];else[self showEmptyEditor];}else[self updateTabs];[self persistWorkspace];}
- (void)closeAllFiles{if(![self save])return;[self.editor resignFirstResponder];[self.opened removeAllObjects];[self showEmptyEditor];NSString *control=Child(self.root,@"control");NSDictionary *attributes=control?[NSFileManager.defaultManager attributesOfItemAtPath:control error:nil]:nil;if([attributes[NSFileType] isEqual:NSFileTypeRegular])[self openFile:@"control"];else if([NSFileManager.defaultManager fileExistsAtPath:[self.root stringByAppendingPathComponent:@"MobileCompiler.json"]]){[self openFile:@"MobileCompiler.json"];self.saved.text=@"本项目没有 control，已打开项目配置";}[self persistWorkspace];}
- (void)updateTabs {
 __weak typeof(self) weakSelf=self;UIView *selected=nil;
 for(UIView *v in self.tabRow.arrangedSubviews){[self.tabRow removeArrangedSubview:v];[v removeFromSuperview];}
 self.closeAllButton.enabled=self.opened.count>0;UIFont *font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
 for(NSString *name in self.opened){BOOL active=[name isEqual:self.filename];UIView *tab=[UIView new];tab.backgroundColor=active?UIColor.systemBackgroundColor:UIColor.clearColor;
 UIButton *file=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *config=UIButtonConfiguration.plainButtonConfiguration;config.attributedTitle=[[NSAttributedString alloc] initWithString:name.lastPathComponent attributes:@{NSFontAttributeName:font}];config.titleLineBreakMode=NSLineBreakByTruncatingTail;config.baseForegroundColor=active?Gold():UIColor.secondaryLabelColor;config.contentInsets=NSDirectionalEdgeInsetsMake(8,8,8,0);file.configuration=config;file.titleLabel.numberOfLines=1;file.accessibilityLabel=[@"打开文件 " stringByAppendingString:name];file.accessibilityValue=active?@"当前文件":@"";
 [file addAction:[UIAction actionWithHandler:^(UIAction *action){[weakSelf openFile:name];}] forControlEvents:UIControlEventTouchUpInside];
 UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];[close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];close.tintColor=UIColor.secondaryLabelColor;close.accessibilityLabel=[@"关闭文件标签 " stringByAppendingString:name];[close addAction:[UIAction actionWithHandler:^(UIAction *action){[weakSelf closeFile:name];}] forControlEvents:UIControlEventTouchUpInside];
 for(UIView *view in @[file,close]){view.translatesAutoresizingMaskIntoConstraints=NO;[tab addSubview:view];}
 CGFloat natural=ceil([name.lastPathComponent sizeWithAttributes:@{NSFontAttributeName:font}].width)+10;CGFloat width=active?MAX(64,natural):MIN(92,MAX(64,natural));
 [NSLayoutConstraint activateConstraints:@[[file.leadingAnchor constraintEqualToAnchor:tab.leadingAnchor],[file.topAnchor constraintEqualToAnchor:tab.topAnchor],[file.bottomAnchor constraintEqualToAnchor:tab.bottomAnchor],[file.widthAnchor constraintEqualToConstant:width],[close.leadingAnchor constraintEqualToAnchor:file.trailingAnchor],[close.trailingAnchor constraintEqualToAnchor:tab.trailingAnchor],[close.topAnchor constraintEqualToAnchor:tab.topAnchor],[close.bottomAnchor constraintEqualToAnchor:tab.bottomAnchor],[close.widthAnchor constraintEqualToConstant:44]]];
 if(active){selected=tab;UIView *line=[UIView new];line.backgroundColor=Gold();line.translatesAutoresizingMaskIntoConstraints=NO;[tab addSubview:line];[NSLayoutConstraint activateConstraints:@[[line.leadingAnchor constraintEqualToAnchor:tab.leadingAnchor constant:8],[line.trailingAnchor constraintEqualToAnchor:tab.trailingAnchor constant:-8],[line.bottomAnchor constraintEqualToAnchor:tab.bottomAnchor],[line.heightAnchor constraintEqualToConstant:2]]];}[self.tabRow addArrangedSubview:tab];
 }
 [self.view layoutIfNeeded];[self.tabRow layoutIfNeeded];[self.tabScroll layoutIfNeeded];
 if(selected){CGFloat viewport=self.tabScroll.bounds.size.width;CGFloat desired=CGRectGetMidX(selected.frame)-viewport/2;CGFloat maximum=MAX(0,self.tabScroll.contentSize.width-viewport);[self.tabScroll setContentOffset:CGPointMake(MAX(0,MIN(desired,maximum)),0) animated:NO];}
}
- (void)home{if(![self save])return;[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(save) object:nil];if(self.busy){Message(self,@"构建进行中",@"请等待当前构建结束后返回，避免中断产物记录。");return;}[self persistWorkspace];[self.navigationController popToRootViewControllerAnimated:YES];}
- (void)files{[self.editor resignFirstResponder];if(![self save])return;StudioFiles *v=[[StudioFiles alloc] initWithStyle:UITableViewStyleInsetGrouped];v.root=self.root;v.readOnly=self.busy;__weak typeof(self) w=self;v.selection=^(NSString *p){[w openFile:p];};v.changed=^(NSString *old,NSString *replacement){
 StudioEditor *editor=w;if(!editor)return;NSUInteger index=[editor.opened indexOfObject:old];if(index!=NSNotFound){if(replacement)editor.opened[index]=replacement;else[editor.opened removeObjectAtIndex:index];}
 if([editor.filename isEqual:old]){if(replacement){editor.filename=replacement;[editor loadFileDiagnostics];[editor highlight];}else{editor.dirty=NO;[editor showEmptyEditor];NSString *next=editor.opened.firstObject;if(!next&&[NSFileManager.defaultManager fileExistsAtPath:Child(editor.root,@"control")])next=@"control";if(next)[editor openFile:next];}}
 [editor updateTabs];[editor persistWorkspace];editor.title=ProjectName(editor.root);
 };[self.navigationController pushViewController:v animated:YES];}
- (void)sourceControl{if(self.busy){Message(self,@"构建进行中",@"请等待构建结束后再执行 Git 操作。");return;}[self.editor resignFirstResponder];if(![self save])return;__weak typeof(self) weak=self;UIViewController *v=TMCGitController(self.root,^{StudioEditor *editor=weak;if(!editor)return;editor.diagnosticsStamp=nil;editor.cachedDiagnostics=nil;if(editor.editorVisible){if(editor.filename&&![NSFileManager.defaultManager fileExistsAtPath:Child(editor.root,editor.filename)])[editor showEmptyEditor];else[editor recheckDisk];editor.title=ProjectName(editor.root);}});[self.navigationController pushViewController:v animated:YES];}
- (void)aiAssistant {
 [self endEditing];if(![self save])return;NSString *scope=TFAIProjectID(self.root);if(!scope)return;
 __weak typeof(self) weak=self;
 UIViewController *home=TFAISessionHomeController(scope,^NSArray *{return TFAIInternalProjects();},^(NSDictionary *record){OpenAISession(weak.navigationController,record,weak);},^(NSDictionary *record,NSDictionary *project){AssociateAISession(weak.navigationController,record,project);});
 [self.navigationController pushViewController:home animated:YES];
}
- (void)openAIRecord:(NSDictionary *)record {
 [self endEditing];if(![self save])return;
 NSString *projectID=TFAIProjectID(self.root);if(!projectID){Message(self,@"项目正在处理",@"请稍后重试 AI 助手；尚未创建会话。");return;}
 TFAIProjectWorkspace *workspace=[TFAIProjectWorkspace new];workspace.editor=self;__block __weak TFAIProjectWorkspace *weakWorkspace=workspace;
 __weak typeof(self) weak=self;
 id<TFAIRuntime> runtime=TFAICreateRuntime(self.root,projectID,^(NSString *name,NSDictionary *arguments,TFAIResult completion){
  dispatch_async(dispatch_get_main_queue(),^{StudioEditor *e=weak;if(!e){completion(nil,[NSError errorWithDomain:@"AI.Bridge" code:1 userInfo:@{NSLocalizedDescriptionKey:@"项目编辑器已关闭"}]);return;}[e aiTool:name arguments:arguments completion:completion];});
 });
 UIViewController *chat=TFAIChatController(self.root,projectID,runtime,^(NSString *file,NSUInteger line){StudioEditor *e=weak;if(!e||!Child(e.root,file))return;[weakWorkspace showEditor];void (^jump)(void)=^{[e jumpToDiagnostic:@{@"file":file,@"line":@(MAX(1,line)),@"column":@1,@"message":@"AI 引用位置",@"severity":@"note"}];};id<UIViewControllerTransitionCoordinator> transition=e.navigationController.transitionCoordinator;if(transition)[transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> c){jump();}];else jump();});
 TFAISetContextProvider(chat,^(NSString *kind,TFAIResult completion){StudioEditor *e=weak;if(!e){completion(nil,[NSError errorWithDomain:@"AI.Context" code:1 userInfo:@{NSLocalizedDescriptionKey:@"项目已关闭"}]);return;}completion([e aiAttachmentContext:kind],nil);});
 if(self.editor.selectedRange.length){NSRange range=self.editor.selectedRange;NSString *selection=[self.editor.text substringWithRange:range];TFAIAddContext(chat,selection,[NSString stringWithFormat:@"%@:%lu 所选代码",self.filename,(unsigned long)[self.gutter.index lineAt:range.location]]);}
 chat=TFAIConfigureChat(chat,record,NO,^(NSDictionary *project){AssociateAISession(weak.navigationController,record,project);});TFAISetSessionOpener(chat,^(NSDictionary *r){OpenAISession(weak.navigationController,r,weak);});
 TFAISetProjectContext(chat,self,^(NSString *name,NSDictionary *arguments,TFAIResult completion){dispatch_async(dispatch_get_main_queue(),^{StudioEditor *e=weak;if(!e){completion(nil,[NSError errorWithDomain:@"AI.Bridge" code:1 userInfo:@{NSLocalizedDescriptionKey:@"项目编辑器已关闭"}]);return;}[e aiTool:name arguments:arguments completion:completion];});});
 UINavigationController *navigation=self.aiNavigation?:self.navigationController;
 if([chat.parentViewController isKindOfClass:TFAIProjectWorkspace.class]){workspace=(TFAIProjectWorkspace *)chat.parentViewController;weakWorkspace=workspace;workspace.switcher.selectedSegmentIndex=0;[workspace changePage];if([navigation.viewControllers containsObject:workspace]){[navigation popToViewController:workspace animated:YES];return;}}
 workspace.chat=chat;[navigation pushViewController:workspace animated:YES];
}
// Attachment content is separate from the tool's structured build-result response.
- (NSDictionary *)aiAttachmentContext:(NSString *)kind {
 NSString *path=self.engine.lastBuild.length?[self.engine.lastBuild stringByAppendingPathComponent:@"build.log"]:nil;
 if([kind isEqual:@"availability"]){NSDictionary *attrs=path?[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil]:nil;return @{@"build_log":@([attrs[NSFileSize] unsignedLongLongValue]>0),@"diagnostics":@([self diagnosticItems].count>0)};}
 if([kind isEqual:@"build_log"]){NSString *log=path?[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]:nil;return @{@"title":@"当前构建日志",@"text":log?:@"",@"available":@(log.length>0)};}
 if([kind isEqual:@"diagnostics"]){NSArray *items=[self diagnosticItems];NSMutableString *text=[NSMutableString new];NSDictionary *labels=@{@"fatal error":@"致命错误",@"error":@"错误",@"warning":@"警告",@"note":@"说明"};for(NSDictionary *item in items){NSString *severity=item[@"severity"]?:@"note",*file=item[@"file"]?:item[@"path"]?:@"构建阶段";NSUInteger line=[item[@"line"] unsignedIntegerValue],column=[item[@"column"] unsignedIntegerValue];NSString *location=line?[NSString stringWithFormat:@"%@:%lu:%lu",file,(unsigned long)line,(unsigned long)MAX(1,column)]:file;if(text.length)[text appendString:@"\n\n"];[text appendFormat:@"%@ · %@\n%@",location,labels[severity]?:severity,item[@"message"]?:@""];}
 return @{@"title":@"当前构建诊断",@"text":text,@"available":@(items.count>0),@"count":@(items.count)};}
 return @{@"available":@NO,@"text":@""};
}
- (NSDictionary *)aiBuildResult {
 NSString *dir=self.engine.lastBuild;if(!dir.length)return @{@"success":@NO,@"diagnostics":@[],@"artifacts":@[],@"note":@"尚未构建"};
 NSData *bytes=dir?[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"report.json"]]:nil;
 NSDictionary *report=bytes.length<=1024*1024?[NSJSONSerialization JSONObjectWithData:bytes?:NSData.data options:0 error:nil]:nil;
 if(![report isKindOfClass:NSDictionary.class])report=@{};
 NSMutableArray *artifacts=[NSMutableArray new];
 for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil])if([@[@"dylib",@"deb"] containsObject:name.pathExtension]){NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];[artifacts addObject:@{@"name":name,@"bytes":attrs[NSFileSize]?:@0,@"modified":@([attrs[NSFileModificationDate] timeIntervalSince1970])}];}
 NSArray *diagnostics=[self diagnosticItems];if(diagnostics.count>100)diagnostics=[diagnostics subarrayWithRange:NSMakeRange(0,100)];
 return @{@"buildID":dir.lastPathComponent?:@"",@"success":report[@"success"]?:@NO,@"diagnostics":diagnostics?:@[],@"artifacts":artifacts,@"runtimeValidated":@NO,@"note":@"本机编译结果；注入和宿主运行需要真机验证。"};
}
- (void)aiTool:(NSString *)name arguments:(NSDictionary *)arguments completion:(TFAIResult)completion {
 if([name isEqual:@"read_diagnostics"]){completion([self aiBuildResult],nil);return;}
 if([name isEqual:@"list_artifacts"]){NSDictionary *base=[self aiBuildResult];NSString *dir=self.engine.lastBuild;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSMutableArray *items=[NSMutableArray new];NSUInteger total=0;for(NSDictionary *file in base[@"artifacts"]){NSMutableDictionary *item=[file mutableCopy];NSUInteger size=[file[@"bytes"] unsignedIntegerValue];if(items.count<12&&size<=64*1024*1024&&total+size<=128*1024*1024){total+=size;NSError *error=nil;NSString *path=[dir stringByAppendingPathComponent:file[@"name"]];NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:&error];NSDictionary *inspection=[attrs[NSFileType] isEqual:NSFileTypeRegular]?TFAIInspectArtifact([NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error],file[@"name"],&error):nil;if(inspection)item[@"inspection"]=inspection;else item[@"inspectionError"]=error.localizedDescription?:@"产物类型已变化，请重新构建";}else item[@"inspectionError"]=@"本次检查上限为 12 个产物、单个 64 MB、合计 128 MB，可通过附件逐项检查";[items addObject:item];}NSMutableDictionary *result=[base mutableCopy];result[@"artifacts"]=items;dispatch_async(dispatch_get_main_queue(),^{completion(result,nil);});});return;}
 if([name isEqual:@"cancel_build"]){BOOL preparing=self.snapshotProgress!=nil;[self.snapshotProgress cancel];completion(@{@"cancelledPreparation":@(preparing),@"compiling":@(self.busy&&!preparing),@"message":preparing?@"已取消准备快照":@"已停止后续 AI 操作；内嵌编译器当前步骤需自行结束。"},nil);return;}
 if(![name isEqual:@"build_project"]){completion(nil,[NSError errorWithDomain:@"AI.Bridge" code:2 userInfo:@{NSLocalizedDescriptionKey:@"未注册的编辑器操作"}]);return;}
 if(self.busy||[TMCGitLease isBuilding:self.root]){completion(nil,[NSError errorWithDomain:@"AI.Bridge" code:3 userInfo:@{NSLocalizedDescriptionKey:@"已有构建正在进行，请稍后检查结果。"}]);return;}
 [self build];if(!self.busy){completion(nil,[NSError errorWithDomain:@"AI.Bridge" code:4 userInfo:@{NSLocalizedDescriptionKey:@"构建未启动；请检查项目配置和未保存的编辑。"}]);return;}
 __weak typeof(self) weak=self;NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;
 [NSTimer scheduledTimerWithTimeInterval:.4 repeats:YES block:^(NSTimer *timer){StudioEditor *e=weak;if(!e||NSProcessInfo.processInfo.systemUptime-start>600){[timer invalidate];completion(nil,[NSError errorWithDomain:@"AI.Bridge" code:5 userInfo:@{NSLocalizedDescriptionKey:@"等待构建超时；请在构建日志中查看实际状态。"}]);return;}if(e.busy)return;[timer invalidate];completion([e aiBuildResult],nil);}];
}
- (void)menu{[self endEditing];UIAlertController *a=[UIAlertController alertControllerWithTitle:@"工程操作" message:self.filename preferredStyle:UIAlertControllerStyleActionSheet];NSArray *titles=@[@"新建文件",@"重命名当前文件",@"项目设置",@"构建诊断",@"查找与替换",@"分享当前源码",@"分享构建结果",@"AI 开发助手",@"源代码管理 Git"];for(NSUInteger n=0;n<titles.count;n++)[a addAction:[UIAlertAction actionWithTitle:titles[n] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){if(n<2)[self fileDialog:n==1];if(n==2)[self projectSettings];if(n==3)[self diagnostics];if(n==4)[self search];if(n==5)[self shareSource];if(n==6)[self shareBuild];if(n==8)[self sourceControl];if(n==7)[self aiAssistant];}]];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems.lastObject;[self presentViewController:a animated:YES completion:nil];}
- (void)highlight {
 if(!self.filename)return;
 if(!self.editor.font||self.highlighting||self.editor.markedTextRange)return;
 NSString *text=self.editor.text?:@"",*file=self.filename?:@"",*ext=file.pathExtension.lowercaseString;
 NSDictionary *languages=@{@"m":@"objectivec",@"mm":@"objectivec",@"xm":@"objectivec",@"x":@"objectivec",@"h":@"objectivec",@"c":@"c",@"cpp":@"cpp",@"hpp":@"cpp",@"plist":@"xml",@"xml":@"xml",@"json":@"json",@"swift":@"swift",@"js":@"javascript",@"py":@"python"};NSString *language=languages[ext]?:@"plaintext";
 self.language.text=[ext isEqual:@"xm"]?@"LOGOS / OBJECTIVE-C++":[language isEqual:@"objectivec"]?@"OBJECTIVE-C":language.uppercaseString;
 NSUInteger revision=++self.syntaxRevision;__weak typeof(self) w=self;
 SyntaxTokens(text,language,^BOOL{return w&&w.syntaxRevision==revision;},^(NSArray *tokens){StudioEditor *v=w;if(v&&!v.editorVisible){v.syntaxDeferred=YES;return;}if(!v||revision!=v.syntaxRevision||![file isEqual:v.filename]||![text isEqual:v.editor.text]||v.editor.markedTextRange)return;
 v.highlighting=YES;CGPoint offset=v.editor.contentOffset;
 BOOL dark=v.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
 UIColor *(^rgb)(NSInteger,NSInteger)=^UIColor *(NSInteger night,NSInteger day){NSInteger x=dark?night:day;return [UIColor colorWithRed:((x>>16)&255)/255. green:((x>>8)&255)/255. blue:(x&255)/255. alpha:1];};
 NSDictionary *palette=@{@"keyword":rgb(0xC586C0,0xAF00DB),@"type":rgb(0x4EC9B0,0x267F99),@"title":rgb(0xDCDCAA,0x795E26),@"built_in":rgb(0x4FC1FF,0x0070C1),@"string":rgb(0xCE9178,0xA31515),@"comment":rgb(0x6A9955,0x008000),@"number":rgb(0xB5CEA8,0x098658),@"literal":rgb(0x569CD6,0x0000FF),@"attr":rgb(0x9CDCFE,0x0451A5),@"attribute":rgb(0x9CDCFE,0x0451A5),@"property":rgb(0x9CDCFE,0x0451A5),@"variable":rgb(0x9CDCFE,0x001080),@"meta":rgb(0xC586C0,0xAF00DB),@"tag":rgb(0x569CD6,0x800000),@"selector-tag":rgb(0xD7BA7D,0x800000),@"symbol":rgb(0xD7BA7D,0x795E26),@"operator":rgb(0xC586C0,0x7B3FB2),@"punctuation":rgb(0xABB2BF,0x52606D)};
 [v.editor.undoManager disableUndoRegistration];[v.editor.textStorage beginEditing];[v.editor.textStorage setAttributes:@{NSFontAttributeName:v.editor.font,NSForegroundColorAttributeName:UIColor.labelColor} range:NSMakeRange(0,text.length)];
 for(NSArray *token in tokens){if(token.count!=3)continue;NSUInteger start=[token[0] unsignedIntegerValue],length=[token[1] unsignedIntegerValue];if(start>text.length||length>text.length-start)continue;UIColor *ink=nil;for(NSString *scope in [token[2] componentsSeparatedByString:@" "])if([scope hasPrefix:@"hljs-"]&&palette[[scope substringFromIndex:5]])ink=palette[[scope substringFromIndex:5]];if(ink)[v.editor.textStorage addAttribute:NSForegroundColorAttributeName value:ink range:NSMakeRange(start,length)];}
 [v paintDiagnostics];[v.editor.textStorage endEditing];[v.editor.undoManager enableUndoRegistration];
 // Attribute-only changes preserve selection. Reassigning selectedRange asks
 // UITextView to reveal the caret and can cancel a user's swipe/scroll.
 if(!v.editor.dragging&&!v.editor.decelerating&&!v.editor.tracking)[v.editor setContentOffset:offset animated:NO];v.editor.typingAttributes=@{NSFontAttributeName:v.editor.font,NSForegroundColorAttributeName:UIColor.labelColor};v.highlighting=NO;[v.gutter setNeedsDisplay];[v textViewDidChangeSelection:v.editor];if(v.pendingDiagnostic){NSDictionary *diagnostic=v.pendingDiagnostic;v.pendingDiagnostic=nil;if([diagnostic[@"file"] isEqual:v.filename])[v revealDiagnostic:diagnostic];}if(v.initialSyntaxReady){void (^ready)(void)=v.initialSyntaxReady;v.initialSyntaxReady=nil;ready();}
 });
}
- (void)paintDiagnostics {
 NSString *text=self.editor.text;NSMutableDictionary *issues=[NSMutableDictionary new];
 for(NSDictionary *d in self.fileDiagnostics){NSString *original=self.diagnosticSource;if(![original isEqual:text])continue;
 NSUInteger line=1,offset=0,target=[d[@"line"] unsignedIntegerValue];while(offset<text.length&&line<target)if([text characterAtIndex:offset++]=='\n')line++;if(line!=target||offset>=text.length)continue;NSUInteger end=offset;while(end<text.length&&[text characterAtIndex:end]!='\n')end++;
 BOOL error=[d[@"severity"] containsString:@"error"];issues[@(line)]=error?@"error":issues[@(line)]?:@"warning";
 UIColor *ink=error?UIColor.systemRedColor:UIColor.systemOrangeColor;NSUInteger at=DiagnosticOffset(text,target,[d[@"column"] unsignedIntegerValue]);
 NSUInteger length=0;while(at+length<end&&([NSCharacterSet.alphanumericCharacterSet characterIsMember:[text characterAtIndex:at+length]]||[text characterAtIndex:at+length]=='_'))length++;if(!length&&at<text.length)length=1;
 if(end>offset)[self.editor.textStorage addAttribute:NSBackgroundColorAttributeName value:[ink colorWithAlphaComponent:.07] range:NSMakeRange(offset,end-offset)];if(length)[self.editor.textStorage addAttributes:@{NSForegroundColorAttributeName:ink,NSUnderlineStyleAttributeName:@(NSUnderlineStyleSingle|NSUnderlinePatternDot),NSUnderlineColorAttributeName:ink} range:NSMakeRange(at,length)];
 }
 self.gutter.issues=issues;
 
}
- (void)loadFileDiagnostics{NSMutableArray *a=[NSMutableArray new];for(NSDictionary *d in [self diagnosticItems])if([d[@"file"] isEqual:self.filename])[a addObject:d];self.fileDiagnostics=a;self.diagnosticSource=a.count?[NSString stringWithContentsOfFile:a.firstObject[@"path"] encoding:NSUTF8StringEncoding error:nil]:nil;}
- (void)copyBuildError:(UILongPressGestureRecognizer *)gesture{if(gesture.state==UIGestureRecognizerStateBegan){UIPasteboard.generalPasteboard.string=self.logDetail.text?:@"";[[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"已复制构建信息");}}
- (void)buildFeedback {NSDictionary *r=self.engine.lastBuild?[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[self.engine.lastBuild stringByAppendingPathComponent:@"report.json"]]?:[NSData data] options:0 error:nil]:nil;if(!self.busy&&r&&![r[@"success"] boolValue])[self diagnostics];else[self logs];}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView{[self.gutter setNeedsDisplay];}
- (void)textViewDidChangeSelection:(UITextView *)textView {if(!self.filename){self.position.text=@"行0·列0";return;}NSUInteger offset=MIN(textView.selectedRange.location,textView.text.length),line=[self.gutter.index lineAt:offset];NSUInteger start=line<=self.gutter.index.starts.count?[self.gutter.index.starts[line-1] unsignedIntegerValue]:0;self.position.text=[NSString stringWithFormat:@"行%lu·列%lu",(unsigned long)line,(unsigned long)(offset>=start?offset-start+1:1)];}
- (void)traitCollectionDidChange:(UITraitCollection *)previous{[super traitCollectionDidChange:previous];if(self.isViewLoaded&&[self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])[self highlight];}
- (void)suggestions {
 if(!self.filename)return;[self.editor resignFirstResponder];UIAlertController *a=[UIAlertController alertControllerWithTitle:@"代码片段与编辑" message:@"插入常用语法模板；保留选区，可通过撤销恢复。" preferredStyle:UIAlertControllerStyleActionSheet];
 NSDictionary *snippets=@{@"if 条件":@"if (<#condition#>) {\n    <#code#>\n}",@"for 循环":@"for (NSInteger i = 0; i < <#count#>; i++) {\n    <#code#>\n}",@"Objective-C 方法":@"- (void)<#method#> {\n    <#code#>\n}",@"Logos Hook":@"%hook <#ClassName#>\n- (void)<#method#> {\n    %orig;\n}\n%end",@"import":@"#import <Foundation/Foundation.h>"};
 [a addAction:[UIAlertAction actionWithTitle:@"撤销" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self.editor.undoManager undo];[self highlight];[self save];}]];[a addAction:[UIAlertAction actionWithTitle:@"重做" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self.editor.undoManager redo];[self highlight];[self save];}]];
 for(NSString *key in [snippets.allKeys sortedArrayUsingSelector:@selector(compare:)])[a addAction:[UIAlertAction actionWithTitle:key style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self.editor becomeFirstResponder];[self.editor insertText:snippets[key]];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,self.view.bounds.size.height-110,1,1);[self presentViewController:a animated:YES completion:nil];
}
- (void)projectSettings{if(self.busy){Message(self,@"构建进行中",@"构建结束后可调整工程元数据。");return;}[self endEditing];StudioProjectSettings *v=[[StudioProjectSettings alloc] initWithStyle:UITableViewStyleInsetGrouped];v.root=self.root;__weak typeof(self) w=self;v.completion=^{w.diagnosticsStamp=nil;w.cachedDiagnostics=nil;};[self.navigationController pushViewController:v animated:YES];}
- (void)search {
 [self.editor resignFirstResponder];UIAlertController *a=[UIAlertController alertControllerWithTitle:@"查找与替换" message:@"区分大小写、按字面匹配；查找下一个会循环到文件开头。替换操作支持编辑器撤销。" preferredStyle:UIAlertControllerStyleAlert];
 [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"查找";f.text=self.searchQuery;f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;}];
 [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"替换为（可留空）";f.text=self.replacement;f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;}];
 for(NSUInteger mode=0;mode<3;mode++)[a addAction:[UIAlertAction actionWithTitle:@[@"查找下一个",@"替换并查找下一个",@"全部替换"][mode] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){NSString *q=a.textFields[0].text,*replacement=a.textFields[1].text?:@"";if(!q.length)return;self.searchQuery=q;self.replacement=replacement;NSString *text=self.editor.text;
 if(mode==2){NSUInteger count=[[text componentsSeparatedByString:q] count]-1;if(!count){Message(self,@"查找结果",@"没有匹配内容");return;}self.editor.selectedRange=NSMakeRange(0,text.length);[self.editor insertText:[text stringByReplacingOccurrencesOfString:q withString:replacement]];[self save];Message(self,@"替换完成",[NSString stringWithFormat:@"已替换 %lu 处，可在编辑工具中撤销。",(unsigned long)count]);return;}
 NSRange selected=self.editor.selectedRange;if(mode==1&&selected.location!=NSNotFound&&NSMaxRange(selected)<=text.length&&[[text substringWithRange:selected] isEqual:q]){[self.editor insertText:replacement];text=self.editor.text;}
 NSUInteger start=MIN(NSMaxRange(self.editor.selectedRange),text.length);NSRange r=[text rangeOfString:q options:0 range:NSMakeRange(start,text.length-start)];if(r.location==NSNotFound)r=[text rangeOfString:q];if(r.location==NSNotFound)Message(self,@"查找结果",@"没有匹配内容");else{[self.editor becomeFirstResponder];self.editor.selectedRange=r;[self.editor scrollRangeToVisible:r];}
 }]];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
- (NSArray *)diagnosticItems {
 NSString *base=self.engine.lastBuild;if(!base.length)return @[];
 NSMutableArray *fingerprint=[NSMutableArray arrayWithObjects:base,self.snapshot?:@"",nil];for(NSString *name in @[@"build.log",@"report.json"]){NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:[base stringByAppendingPathComponent:name] error:nil];[fingerprint addObject:[NSString stringWithFormat:@"%@:%@",a[NSFileModificationDate],a[NSFileSize]]];}NSString *stamp=[fingerprint componentsJoinedByString:@"|"];if([stamp isEqual:self.diagnosticsStamp]&&self.cachedDiagnostics)return self.cachedDiagnostics;
 NSData *rd=[NSData dataWithContentsOfFile:[base stringByAppendingPathComponent:@"report.json"]];NSDictionary *report=rd?[NSJSONSerialization JSONObjectWithData:rd options:0 error:nil]:nil;
 NSString *log=self.engine.lastBuild?[NSString stringWithContentsOfFile:[self.engine.lastBuild stringByAppendingPathComponent:@"build.log"] encoding:NSUTF8StringEncoding error:nil]:nil;
 NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"^(.+?):([0-9]+):([0-9]+): (fatal error|error|warning|note): (.*)$" options:NSRegularExpressionAnchorsMatchLines error:nil];NSMutableArray *items=[NSMutableArray new];
 for(NSTextCheckingResult *m in [rx matchesInString:log?:@"" options:0 range:NSMakeRange(0,log.length)]){NSString *path=[log substringWithRange:[m rangeAtIndex:1]],*relative=nil;NSString *snapshot=self.snapshot;
 if(!snapshot){for(NSDictionary *cmd in report[@"commands"]){NSString *source=cmd[@"source"];if(source.length&&[path hasSuffix:[@"/" stringByAppendingString:source]]&&Child(self.root,source)){relative=source;break;}}}
 if(snapshot&&[path hasPrefix:[snapshot stringByAppendingString:@"/"]])relative=[path substringFromIndex:snapshot.length+1];if(!relative&&[path hasPrefix:[self.root stringByAppendingString:@"/"]])relative=[path substringFromIndex:self.root.length+1];
 NSMutableDictionary *d=[@{@"path":path,@"line":@([[log substringWithRange:[m rangeAtIndex:2]] integerValue]),@"column":@([[log substringWithRange:[m rangeAtIndex:3]] integerValue]),@"severity":[log substringWithRange:[m rangeAtIndex:4]],@"message":[log substringWithRange:[m rangeAtIndex:5]]} mutableCopy];if(relative&&Child(self.root,relative))d[@"file"]=relative;[items addObject:d];}
 BOOL hasError=NO;for(NSDictionary *d in items)if([d[@"severity"] containsString:@"error"])hasError=YES;
 if(report&&![report[@"success"] boolValue]&&!hasError){NSString *reason=report[@"outputNamingError"]?:report[@"packageError"],*stage=@"构建失败";if(!reason){NSArray *lines=[log componentsSeparatedByString:@"\n"];for(NSUInteger i=0;i<lines.count;i++)if([lines[i] containsString:@"error:"]||[lines[i] containsString:@"Undefined symbols"]||[lines[i] containsString:@"Can't locate"]){reason=lines[i];if(i+1<lines.count)reason=[reason stringByAppendingFormat:@"\n%@",lines[i+1]];break;}}for(NSDictionary *command in report[@"commands"])if([command[@"exit"] intValue]!=0){stage=[NSString stringWithFormat:@"%@ · exit %@",command[@"stage"],command[@"exit"]];break;}if(!reason.length)reason=@"本次构建未生成成功报告，请展开完整日志查看工具链输出。";[items insertObject:@{@"path":stage,@"line":@0,@"column":@0,@"severity":@"error",@"message":reason} atIndex:0];}
 NSString *fixSnapshot=self.snapshot;if(!fixSnapshot)for(NSDictionary *item in items){NSString *file=item[@"file"],*path=item[@"path"];if(file.length&&[path hasSuffix:file]){fixSnapshot=[path substringToIndex:path.length-file.length];while([fixSnapshot hasSuffix:@"/"])fixSnapshot=[fixSnapshot substringToIndex:fixSnapshot.length-1];break;}}for(NSDictionary *fix in TMCParseFixIts(log?:@"",self.root,fixSnapshot)){for(NSUInteger index=0;index<items.count;index++){NSDictionary *item=items[index];if([item[@"path"] isEqual:fix[@"path"]]&&[fix[@"message"] containsString:item[@"message"]]){NSMutableDictionary *copy=[item mutableCopy];NSMutableArray *fixes=[copy[@"fixits"] mutableCopy]?:[NSMutableArray new];[fixes addObject:fix];copy[@"fixits"]=fixes;items[index]=copy;break;}}}self.diagnosticsStamp=stamp;self.cachedDiagnostics=items;return items;
}
- (void)clearDiagnosticFlash{
 ((StudioDiagnosticLayoutManager *)self.editor.layoutManager).flashRange=NSMakeRange(0,0);self.jumpRange=NSMakeRange(0,0);self.diagnosticHint.hidden=YES;
}
- (void)jumpToDiagnostic:(NSDictionary *)diagnostic{
 NSString *file=diagnostic[@"file"];if(!file.length){Message(self,@"诊断位于生成文件或 SDK",diagnostic[@"message"]?:@"请查看完整日志。");return;}
 self.pendingDiagnostic=nil;[self.editor resignFirstResponder];[self clearDiagnosticFlash];[self openFile:file];if(![self.filename isEqual:file])return;
 // openFile queues scroll restoration and syntax layout. Reveal only after
 // that syntax pass completes, when TextKit has final line geometry.
 self.pendingDiagnostic=diagnostic;
}
- (void)revealDiagnostic:(NSDictionary *)diagnostic{
 NSString *source=self.editor.text;NSUInteger offset=DiagnosticOffset(source,[diagnostic[@"line"] unsignedIntegerValue],[diagnostic[@"column"] unsignedIntegerValue]);
 NSUInteger begin=offset;while(begin>0&&[source characterAtIndex:begin-1]!='\n')begin--;NSUInteger end=offset;while(end<source.length&&[source characterAtIndex:end]!='\n')end++;
 self.editor.selectedRange=NSMakeRange(offset,0);[self.view layoutIfNeeded];NSLayoutManager *layout=self.editor.layoutManager;[layout ensureLayoutForTextContainer:self.editor.textContainer];
 NSRange lineRange=NSMakeRange(begin,end-begin);((StudioDiagnosticLayoutManager *)layout).flashRange=lineRange;self.jumpRange=lineRange;
 CGRect caret=[self.editor caretRectForPosition:[self.editor positionFromPosition:self.editor.beginningOfDocument offset:offset]];
 CGFloat target=CGRectGetMidY(caret)-self.editor.bounds.size.height*.4;CGFloat low=-self.editor.adjustedContentInset.top,high=MAX(low,self.editor.contentSize.height-self.editor.bounds.size.height+self.editor.adjustedContentInset.bottom);
 [self.editor setContentOffset:CGPointMake(self.editor.contentOffset.x,MAX(low,MIN(target,high))) animated:NO];[self textViewDidChangeSelection:self.editor];[self.gutter setNeedsDisplay];
 self.diagnosticHint.text=[@"  " stringByAppendingString:diagnostic[@"message"]?:@""];self.diagnosticHint.textColor=[diagnostic[@"severity"] containsString:@"error"]?UIColor.systemRedColor:UIColor.systemOrangeColor;self.diagnosticHint.hidden=NO;
 NSUInteger flash=++self.jumpRevision;[self persistWorkspace];UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,diagnostic[@"message"]);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.jumpRevision==flash){[self clearDiagnosticFlash];}});
}
- (void)diagnostics {
 if(self.busy){Message(self,@"构建进行中",@"请在构建结束后查看和修复诊断。");return;}if(![self save])return;StudioDiagnostics *v=[[StudioDiagnostics alloc] initWithStyle:UITableViewStylePlain];v.root=self.root;__weak typeof(self) repairEditor=self;v.repairCompletion=^{StudioEditor *editor=repairEditor;editor.diagnosticsStamp=nil;editor.cachedDiagnostics=nil;editor.dirty=NO;if(editor.filename)[editor openFile:editor.filename];};v.items=[self diagnosticItems];v.logText=[NSString stringWithContentsOfFile:[self.engine.lastBuild stringByAppendingPathComponent:@"build.log"] encoding:NSUTF8StringEncoding error:nil];__weak typeof(self) w=self;v.selection=^(NSDictionary *d){[w jumpToDiagnostic:d];};[self.navigationController pushViewController:v animated:YES];
}

- (void)fileDialog:(BOOL)rename{if(self.busy){Message(self,@"构建进行中",@"请在构建完成后修改文件结构。");return;}UIAlertController *a=[UIAlertController alertControllerWithTitle:rename?@"重命名文件":@"新建文件" message:@"新建源码会加入编译列表；重命名会同步明确的配置路径。源码内 include 引用请自行检查。" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=rename?self.filename.lastPathComponent:@"Helper.m";f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;}];[a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){Message(self,@"Git 正在处理",@"请稍后修改文件。");return;}NSString *n=a.textFields.firstObject.text;if(!NameOK(n)){Message(self,@"名称有误",@"请使用单个文件名，避免斜线与特殊路径。");return;}NSString *relative=rename?[self.filename.stringByDeletingLastPathComponent stringByAppendingPathComponent:n]:n;NSString *dest=Child(self.root,relative);if(!dest||[NSFileManager.defaultManager fileExistsAtPath:dest]){Message(self,@"文件已存在",@"请选择其他名称。");return;}if(rename && [@[@"MobileCompiler.json",@"control"] containsObject:self.filename]){Message(self,@"固定配置名称",@"编译器依赖此文件名，请保留名称并编辑内容。");return;}NSError *e=nil;NSMutableDictionary *c=[Config(self.root) mutableCopy];NSMutableArray *sources=[c[@"sources"] isKindOfClass:NSArray.class]?[c[@"sources"] mutableCopy]:[NSMutableArray new];if(!c[@"sources"])for(NSString *existing in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.root error:nil])if([@[@"x",@"m",@"mm",@"xm",@"c",@"cpp"] containsObject:existing.pathExtension])[sources addObject:existing];BOOL ok=rename?ChangeProjectFile(self.root,self.filename,relative,&e):[@"" writeToFile:dest atomically:YES encoding:NSUTF8StringEncoding error:&e];if(!ok){Message(self,@"文件操作失败",e.localizedDescription);return;}if(!rename&&[@[@"x",@"m",@"mm",@"xm",@"c",@"cpp"] containsObject:n.pathExtension]){NSMutableDictionary *c=[Config(self.root) mutableCopy];NSMutableArray *sources=[c[@"sources"] mutableCopy]?:[NSMutableArray new];[sources addObject:relative];c[@"sources"]=sources;if(!JSONWrite(c,[self.root stringByAppendingPathComponent:@"MobileCompiler.json"],&e)){[NSFileManager.defaultManager removeItemAtPath:dest error:nil];Message(self,@"配置保存失败",e.localizedDescription);return;}}MarkSaved(self.root);if(rename)[self.opened removeObject:self.filename];[self openFile:relative];}]];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)shareSource{if(![self save])return;NSString *p=Child(self.root,self.filename);if(!p)return;[self shareURLs:@[[NSURL fileURLWithPath:p]] from:self.navigationItem.rightBarButtonItems.lastObject];}
- (void)shareURLs:(NSArray *)urls from:(UIBarButtonItem *)bar{if(!urls.count){Message(self,@"暂无产物",@"请先完成构建。");return;}UIActivityViewController *v=[[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];v.popoverPresentationController.barButtonItem=bar;if(!bar){v.popoverPresentationController.sourceView=self.view;v.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,self.view.bounds.size.height-80,1,1);}[self presentViewController:v animated:YES completion:nil];}
- (void)shareBuild{if(!self.engine.lastBuild){Message(self,@"暂无产物",@"请先完成构建。");return;}NSMutableArray *urls=[NSMutableArray new];NSData *rd=[NSData dataWithContentsOfFile:[self.engine.lastBuild stringByAppendingPathComponent:@"report.json"]];NSDictionary *report=rd?[NSJSONSerialization JSONObjectWithData:rd options:0 error:nil]:nil;NSMutableArray *names=[@[@"report.json",@"build.log",@"symbols.json",@"provenance.json",@"filter.plist",@"control"] mutableCopy];NSArray *named=report[@"namedArtifacts"];if([named isKindOfClass:NSArray.class]&&named.count)[names addObjectsFromArray:named];else[names addObjectsFromArray:@[@"Smoke.dylib",@"MobileTweak.deb"]];for(NSString *f in names){NSString *p=[self.engine.lastBuild stringByAppendingPathComponent:f];if(p&&[NSFileManager.defaultManager fileExistsAtPath:p])[urls addObject:[NSURL fileURLWithPath:p]];}[self shareURLs:urls from:self.navigationItem.rightBarButtonItems.lastObject];}
- (UIBarButtonItem *)makeBuildButton{
 __weak typeof(self) w=self;
 UIAction *build=[UIAction actionWithTitle:@"构建" image:[UIImage systemImageNamed:@"play.fill"] identifier:nil handler:^(UIAction *a){[w build];}];
 UIAction *clean=[UIAction actionWithTitle:@"清理构建缓存" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *a){[w cleanBuildCache];}];
 UIAction *rebuild=[UIAction actionWithTitle:@"清理后重新构建" image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil handler:^(UIAction *a){if([w cleanBuildCache])[w build];}];
 UIAction *view=[UIAction actionWithTitle:@"查看构建结果" image:[UIImage systemImageNamed:@"shippingbox"] identifier:nil handler:^(UIAction *a){[w viewBuildResults];}];
 UIAction *results=[UIAction actionWithTitle:@"分享构建结果" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *a){[w shareBuild];}];
 UIBarButtonItem *button=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"play.fill"] style:UIBarButtonItemStylePlain target:nil action:nil];button.accessibilityLabel=@"构建操作";button.menu=[UIMenu menuWithTitle:@"构建操作" children:@[build,[UIAction actionWithTitle:@"取消准备构建" image:[UIImage systemImageNamed:@"stop.circle"] identifier:nil handler:^(UIAction *a){[w cancelPreparingBuild];}],clean,rebuild,view,results]];return button;
}
- (void)viewBuildResults{StudioBuildResults *v=[[StudioBuildResults alloc] initWithStyle:UITableViewStyleInsetGrouped];v.directory=self.engine.lastBuild;v.projectName=ProjectName(self.root);[self.navigationController pushViewController:v animated:YES];}
- (void)updateLogVisibility{BOOL shown=self.logVisible&&!self.keyboardVisible;self.consolePanel.hidden=!shown;[self.logToggleItem setImage:[UIImage systemImageNamed:shown?@"chevron.down.square.fill":@"terminal"]?:[UIImage systemImageNamed:shown?@"terminal.fill":@"terminal"] forState:UIControlStateNormal];self.logToggleItem.tintColor=shown?Gold():UIColor.secondaryLabelColor;self.logToggleItem.accessibilityLabel=shown?@"隐藏构建日志":@"显示构建日志";self.logToggleItem.accessibilityValue=shown?@"已显示":@"已隐藏";}
- (void)toggleLog{
 self.logVisible=self.consolePanel.hidden;if(self.logVisible)[self endEditing];
 CGPoint offset=self.editor.contentOffset;
 // UIStackView's hidden animation used to interpolate the code area's height
 // while TextKit and the separate gutter redrew in different frames.
 [UIView performWithoutAnimation:^{[self updateLogVisibility];[self.view layoutIfNeeded];[self.editor.layoutManager ensureLayoutForTextContainer:self.editor.textContainer];[self.editor setContentOffset:offset animated:NO];[self.gutter setNeedsDisplay];[self.gutter layoutIfNeeded];}];
 if(!self.consolePanel.hidden&&!UIAccessibilityIsReduceMotionEnabled()){self.consolePanel.alpha=0;[UIView animateWithDuration:.15 animations:^{self.consolePanel.alpha=1;}];}else self.consolePanel.alpha=1;
}
- (NSString *)cacheOwner{NSString *prefix=[Docs() stringByAppendingString:@"/"];return [self.root hasPrefix:prefix]?[self.root substringFromIndex:prefix.length]:self.root;}
- (void)rememberBuildCache{
 NSString *path=[self.root stringByAppendingPathComponent:@".studio-build-cache.json"];id value=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path]?:[NSData data] options:0 error:nil];NSArray *previous=[value isKindOfClass:NSDictionary.class]&&[value[@"owner"] isEqual:[self cacheOwner]]&&[value[@"items"] isKindOfClass:NSArray.class]?value[@"items"]:@[];NSMutableArray *names=[previous mutableCopy];
 for(NSString *item in @[self.snapshot?:@"",self.engine.lastBuild?:@""]){if(![item.stringByDeletingLastPathComponent isEqual:Docs()])continue;NSString *name=item.lastPathComponent;if(![names containsObject:name])[names addObject:name];}
 JSONWrite(@{@"owner":[self cacheOwner],@"items":names},path,nil);
}
- (BOOL)cleanBuildCache{
 if(self.busy){Message(self,@"构建进行中",@"请在当前构建完成后清理。");return NO;}if(![self save])return NO;
 NSString *history=[self.root stringByAppendingPathComponent:@".studio-build-cache.json"];id value=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:history]?:[NSData data] options:0 error:nil];NSMutableSet *names=[NSMutableSet set];if([value isKindOfClass:NSDictionary.class]&&[value[@"owner"] isEqual:[self cacheOwner]]&&[value[@"items"] isKindOfClass:NSArray.class])for(id name in value[@"items"])if([name isKindOfClass:NSString.class])[names addObject:name];
 for(NSString *item in @[self.snapshot?:@"",self.engine.lastBuild?:@""])if([item.stringByDeletingLastPathComponent isEqual:Docs()])[names addObject:item.lastPathComponent];
 NSError *error=nil;for(NSString *name in names){NSString *prefix=[name hasPrefix:@"Build-"]?@"Build-":[name hasPrefix:@"Snapshot-"]?@"Snapshot-":nil;if(!prefix||![[NSUUID alloc] initWithUUIDString:[name substringFromIndex:prefix.length]])continue;NSString *path=Child(Docs(),name);if(path&&[NSFileManager.defaultManager fileExistsAtPath:path]&&![NSFileManager.defaultManager removeItemAtPath:path error:&error])break;}
 if(error){Message(self,@"部分缓存清理失败",error.localizedDescription);return NO;}[NSFileManager.defaultManager removeItemAtPath:history error:nil];[NSUserDefaults.standardUserDefaults removeObjectForKey:[@"StudioBuild-" stringByAppendingString:self.root.lastPathComponent]];
 self.snapshot=nil;self.engine.lastBuild=nil;self.engine.lastPackage=nil;self.engine.importedProject=self.root;self.fileDiagnostics=@[];self.diagnosticSource=nil;self.jumpRevision++;self.jumpRange=NSMakeRange(0,0);self.diagnosticHint.hidden=YES;self.logTitle.text=@"构建日志";self.logDetail.text=@"已清理本项目构建缓存";self.saved.text=@"已清理构建缓存";self.logVisible=NO;[self updateLogVisibility];[self highlight];return YES;
}
- (void)build{
 if(self.busy||![self save])return;
 TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){Message(self,@"Git 正在处理",@"请稍后开始构建。");return;}
 if([self.root hasPrefix:[Projects() stringByAppendingString:@"/"]]&&!Config(self.root)[@"productName"]){NSMutableDictionary *c=[Config(self.root) mutableCopy];c[@"productName"]=@"MobileTweak";NSError *migration=nil;if(!JSONWrite(c,[self.root stringByAppendingPathComponent:@"MobileCompiler.json"],&migration)){Message(self,@"配置保存失败",migration.localizedDescription);return;}}
 NSString *invalid=ValidateProject(self.root);if(invalid){Message(self,@"工程配置有误",invalid);return;}
 [self.editor resignFirstResponder];self.keyboardVisible=NO;self.statusPanel.hidden=NO;[[TMCGitAutomation shared] buildStarted:self.root];self.busy=YES;self.logVisible=YES;self.logTitle.text=@"准备构建";self.logDetail.text=@"正在创建项目快照…";self.logIcon.image=[UIImage systemImageNamed:@"gearshape.2"];self.logIcon.tintColor=Gold();self.logTitle.textColor=UIColor.labelColor;[self updateLogVisibility];[self.view layoutIfNeeded];
 self.snapshotProgress=[NSProgress progressWithTotalUnitCount:1];self.logDetail.text=@"正在扫描构建输入…";
 self.editor.editable=NO;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  TMCGitLease *copyLease __attribute__((objc_precise_lifetime))=[TMCGitLease acquire];
  NSError *error=nil;NSString *snap=[Docs() stringByAppendingPathComponent:[@"Snapshot-" stringByAppendingString:NSUUID.UUID.UUIDString]];
  NSProgress *progress=self.snapshotProgress;
  __block NSTimeInterval last=0;
  BOOL copied=TMCCopyProject(self.root,snap,NO,progress,^(NSProgress *p){NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(now-last<.15&&p.fractionCompleted<1)return;last=now;double fraction=p.fractionCompleted;dispatch_async(dispatch_get_main_queue(),^{self.logDetail.text=[NSString stringWithFormat:@"准备构建输入 %.0f%% · 播放菜单可取消",fraction*100];});},&error);
  if(!copied)[NSFileManager.defaultManager removeItemAtPath:snap error:nil];
  dispatch_async(dispatch_get_main_queue(),^{
   self.editor.editable=YES;self.snapshotProgress=nil;
   if(!copied){self.busy=NO;[[TMCGitAutomation shared] buildFinished:self.root success:NO];self.navigationItem.rightBarButtonItems.firstObject.enabled=YES;self.logTitle.text=progress.cancelled?@"已取消准备构建":@"创建构建快照失败";self.logDetail.text=error.localizedDescription;self.logIcon.image=[UIImage systemImageNamed:@"xmark.circle.fill"];self.logIcon.tintColor=UIColor.systemRedColor;return;}
   self.snapshot=snap;self.engine.importedProject=snap;__weak typeof(self) weakSelf=self;self.engine.buildCompletion=^(BOOL success){StudioEditor *v=weakSelf;if(!v)return;JSONWrite(@{@"project":v.root,@"snapshot":snap},[v.engine.lastBuild stringByAppendingPathComponent:@".studio-cache-owner.json"],nil);[v refreshBuild];NSString *keep=v.engine.lastBuild,*root=v.root;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{TMCPruneBuildCaches(Docs(),root,keep);});};[self.engine runProof];JSONWrite(@{@"project":self.root,@"snapshot":snap},[self.engine.lastBuild stringByAppendingPathComponent:@".studio-cache-owner.json"],nil);[self rememberBuildCache];if(self.busy)self.timer=[NSTimer scheduledTimerWithTimeInterval:.35 repeats:YES block:^(NSTimer *timer){[weakSelf refreshBuild];}];
  });
 });
}
- (void)cancelPreparingBuild{if(self.snapshotProgress)[self.snapshotProgress cancel];else Message(self,@"编译正在执行",@"编译器运行时请等待当前任务完成。准备快照阶段支持取消。");}

- (void)refreshBuild{if(self.busy&&!self.engine.hasBuilt&&self.engine.lastBuild&&![NSFileManager.defaultManager fileExistsAtPath:[self.engine.lastBuild stringByAppendingPathComponent:@"report.json"]]){self.busy=NO;[[TMCGitAutomation shared] buildFinished:self.root success:NO];[self.timer invalidate];self.timer=nil;self.logTitle.text=@"构建未完成";self.logDetail.text=self.engine.console.text?:@"构建报告未保存，请检查剩余存储空间";self.logIcon.image=[UIImage systemImageNamed:@"xmark.circle.fill"];self.logIcon.tintColor=UIColor.systemRedColor;self.navigationItem.rightBarButtonItems.firstObject.enabled=YES;return;}NSString *report=[self.engine.lastBuild stringByAppendingPathComponent:@"report.json"];BOOL done=!self.engine.hasBuilt&&report&&[NSFileManager.defaultManager fileExistsAtPath:report];NSString *status=self.engine.console.text?:@"构建进行中";if(done){NSDictionary *r=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:report] options:0 error:nil];BOOL success=[r[@"success"] boolValue];BOOL finishedBuild=self.busy;if(finishedBuild)[[TMCGitAutomation shared] buildFinished:self.root success:success];self.logTitle.text=success?@"构建成功":@"构建失败 · 查看诊断";self.logIcon.image=[UIImage systemImageNamed:success?@"checkmark.circle.fill":@"xmark.circle.fill"];self.logIcon.tintColor=success?UIColor.systemGreenColor:UIColor.systemRedColor;self.busy=NO;self.logVisible=YES;self.logTitle.textColor=success?UIColor.systemGreenColor:UIColor.systemRedColor;[self updateLogVisibility];[self.timer invalidate];self.timer=nil;self.navigationItem.rightBarButtonItems.firstObject.enabled=YES;[NSUserDefaults.standardUserDefaults setObject:self.engine.lastBuild.lastPathComponent forKey:[@"StudioBuild-" stringByAppendingString:self.root.lastPathComponent]];NSArray *diagnostics=[self diagnosticItems];TMCRecordRebuildDiagnostics(self.root,self.engine.lastBuild,diagnostics);NSDictionary *first=nil;for(NSDictionary *d in diagnostics)if([d[@"severity"] containsString:@"error"]){first=d;break;}self.logDetail.text=success?[NSString stringWithFormat:@"%@ 个源码 · %lu 条诊断 · 运行待验证",r[@"sourceCount"]?:@"—",(unsigned long)diagnostics.count]:first[@"message"]?:@"构建失败，点击查看原因";[self loadFileDiagnostics];[self highlight];}else{self.logTitle.text=@"正在本机编译";self.logIcon.image=[UIImage systemImageNamed:@"gearshape.2"];self.logIcon.tintColor=Gold();NSArray *lines=[status componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];NSString *last=@"正在准备工具链…";for(NSString *line in lines)if(line.length)last=line;self.logDetail.text=last;}if(self.logView){NSString *p=[self.engine.lastBuild stringByAppendingPathComponent:@"build.log"];[self.logController updateLog:[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil]?:status];}}
- (void)logDiagnostics{[self dismissViewControllerAnimated:YES completion:^{[self diagnostics];}];}
- (void)logResults{self.logView=nil;[self dismissViewControllerAnimated:YES completion:^{[self viewBuildResults];}];}
- (void)logShare{NSString *path=[self.engine.lastBuild stringByAppendingPathComponent:@"build.log"];NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;if(!data.length){Message(self.presentedViewController?:self,@"暂无日志",@"请先运行一次构建。");return;}NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];NSString *copy=[dir stringByAppendingPathComponent:@"build.log"];NSError *error=nil;if(![data writeToFile:copy options:NSDataWritingAtomic error:&error]){Message(self.presentedViewController?:self,@"日志导出失败",error.localizedDescription);return;}UIViewController *presenter=self.presentedViewController?:self;UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:copy]] applicationActivities:nil];share.popoverPresentationController.sourceView=presenter.view;share.popoverPresentationController.sourceRect=CGRectMake(presenter.view.bounds.size.width/2,40,1,1);[presenter presentViewController:share animated:YES completion:nil];}
- (void)logs{[self endEditing];StudioText *v=[StudioText new];v.logMode=YES;v.title=self.busy?@"实时构建日志":@"构建日志";NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:[@"StudioBuild-" stringByAppendingString:self.root.lastPathComponent]];if(!self.engine.lastBuild&&saved)self.engine.lastBuild=[Docs() stringByAppendingPathComponent:saved];v.content=(self.engine.lastBuild?[NSString stringWithContentsOfFile:[self.engine.lastBuild stringByAppendingPathComponent:@"build.log"] encoding:NSUTF8StringEncoding error:nil]:nil)?:@"准备就绪。构建后可在这里查看和分享日志。产物请从“查看构建结果”导出。";v.navigationItem.leftBarButtonItems=@[[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.bubble"] style:UIBarButtonItemStylePlain target:self action:@selector(logDiagnostics)],[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"] style:UIBarButtonItemStylePlain target:self action:@selector(logShare)]];UINavigationController *nav=[[TMCNavigationController alloc] initWithRootViewController:v];self.logTransition=[TMCLogTransition new];nav.modalPresentationStyle=UIModalPresentationCustom;nav.transitioningDelegate=self.logTransition;[self presentViewController:nav animated:YES completion:^{self.logView=v.text;self.logController=v;UIBarButtonItem *results=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"shippingbox"] style:UIBarButtonItemStylePlain target:self action:@selector(logResults)];results.accessibilityLabel=@"查看构建结果";v.navigationItem.rightBarButtonItems=@[v.navigationItem.rightBarButtonItem,results];v.text.text=@"";[v updateLog:v.content];if(v.text.text.length)[v.text scrollRangeToVisible:NSMakeRange(v.text.text.length-1,1)];}];}
@end

@interface StudioCreate : UITableViewController
@property NSMutableArray<UITextField *> *fields;
@property UISegmentedControl *kind;
@end
@implementation StudioCreate
- (void)viewDidLoad{[super viewDidLoad];ApplyTheme(self);self.title=@"创建项目";self.fields=[NSMutableArray new];NSArray *values=@[@"HelloPocket",@"com.example.hellopocket",@"Developer",@"1.0.0",@"com.example.target"];NSArray *labels=@[@"项目名称",@"包标识",@"作者",@"版本",@"目标 Bundle ID"];for(NSUInteger i=0;i<values.count;i++){UITextField *f=[UITextField new];f.text=values[i];f.placeholder=labels[i];f.accessibilityLabel=labels[i];f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.font=[UIFont systemFontOfSize:14];[self.fields addObject:f];}self.kind=[[UISegmentedControl alloc] initWithItems:@[@"Objective-C",@"Logos",@"纯动态库"]];self.kind.selectedSegmentIndex=0;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"创建" style:UIBarButtonItemStyleDone target:self action:@selector(createProject)];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?1:5;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return s==0?@"选择项目模板":@"项目与包信息";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==1?@"插件将生成源码、过滤 plist、control 与 MobileCompiler.json。目标 ID 是占位值，请填写实际测试宿主；SDK 与最低系统版本跟随默认构建设置，可在项目中调整。":nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i{UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];UIView *v=nil;if(i.section==0)v=self.kind;else{UILabel *caption=Label(@[@"项目名称",@"包标识",@"作者",@"版本",@"目标 Bundle ID"][i.row],10,NO);caption.textColor=UIColor.secondaryLabelColor;UIStackView *fieldStack=[[UIStackView alloc] initWithArrangedSubviews:@[caption,self.fields[i.row]]];fieldStack.axis=UILayoutConstraintAxisVertical;fieldStack.spacing=6;v=fieldStack;}v.translatesAutoresizingMaskIntoConstraints=NO;[c.contentView addSubview:v];[NSLayoutConstraint activateConstraints:@[[v.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:16],[v.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-16],[v.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:12],[v.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-12],[v.heightAnchor constraintGreaterThanOrEqualToConstant:32]]];return c;}
- (void)createProject{[self.view endEditing:YES];NSString *name=[self.fields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSString *package=self.fields[1].text,*author=self.fields[2].text,*version=self.fields[3].text,*target=self.fields[4].text;if(!NameOK(name)){Message(self,@"项目名有误",@"请输入有效项目名称。");return;}NSRegularExpression *idRegex=[NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$" options:0 error:nil];if(![idRegex numberOfMatchesInString:package options:0 range:NSMakeRange(0,package.length)]||!author.length||!version.length||[version rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound||[author containsString:@"\n"]||![idRegex numberOfMatchesInString:target options:0 range:NSMakeRange(0,target.length)]){Message(self,@"项目信息有误",@"请填写有效包标识、目标 ID、作者及无空白字符的版本号。");return;}NSString *root=[Projects() stringByAppendingPathComponent:name];if([NSFileManager.defaultManager fileExistsAtPath:root]){Message(self,@"同名项目已存在",@"请使用其他名称，已有文件会保留。");return;}NSString *temp=[Projects() stringByAppendingPathComponent:[@".creating-" stringByAppendingString:NSUUID.UUID.UUIDString]];NSError *e=nil;BOOL ok=[NSFileManager.defaultManager createDirectoryAtPath:temp withIntermediateDirectories:YES attributes:nil error:&e];BOOL logos=self.kind.selectedSegmentIndex==1,lib=self.kind.selectedSegmentIndex==2;NSString *source=logos?@"Tweak.xm":@"Tweak.m";
 NSString *code=logos?@"#import <UIKit/UIKit.h>\n\n%hook UIViewController\n- (void)viewDidAppear:(BOOL)animated {\n    %orig;\n    NSLog(@\"Built on iPhone\");\n}\n%end\n":@"#import <Foundation/Foundation.h>\n\n@interface PocketGreeting : NSObject\n+ (NSString *)message;\n@end\n\n@implementation PocketGreeting\n+ (NSString *)message {\n    return @\"Hello from iPhone\";\n}\n@end\n";
 if(ok)ok=[code writeToFile:[temp stringByAppendingPathComponent:source] atomically:YES encoding:NSUTF8StringEncoding error:&e];NSString *product=[package componentsSeparatedByString:@"."].lastObject;
 NSMutableDictionary *config=[@{@"name":name,@"productName":product.length>24?[product substringToIndex:24]:product,@"sources":@[source],@"frameworks":logos?@[@"Foundation",@"UIKit",@"CydiaSubstrate"]:@[@"Foundation",@"UIKit"],@"package":@(!lib),@"optimization":GlobalOptimization()} mutableCopy];if(!lib)[config removeObjectForKey:@"package"];if(ok)ok=JSONWrite(config,[temp stringByAppendingPathComponent:@"MobileCompiler.json"],&e);
 if(ok&&!lib){NSDictionary *filter=@{@"Filter":@{@"Bundles":@[target]}};NSData *data=[NSPropertyListSerialization dataWithPropertyList:filter format:NSPropertyListXMLFormat_v1_0 options:0 error:&e];ok=data&&[data writeToFile:[temp stringByAppendingPathComponent:[name stringByAppendingString:@".plist"]] options:NSDataWritingAtomic error:&e];NSString *control=[NSString stringWithFormat:@"Package: %@\nName: %@\nVersion: %@\nArchitecture: iphoneos-arm64\nDescription: Built with Pocket Studio\nMaintainer: %@\nAuthor: %@\nSection: Tweaks\n",package,name,version,author,author];if(ok)ok=[control writeToFile:[temp stringByAppendingPathComponent:@"control"] atomically:YES encoding:NSUTF8StringEncoding error:&e];}if(ok)ok=[NSFileManager.defaultManager moveItemAtPath:temp toPath:root error:&e];if(!ok){Message(self,@"创建失败",e.localizedDescription?:@"请检查存储空间");return;}MarkSaved(root);StudioEditor *v=[StudioEditor new];v.root=root;NSMutableArray *controllers=[self.navigationController.viewControllers mutableCopy];[controllers removeLastObject];[controllers addObject:v];[self.navigationController setViewControllers:controllers animated:YES];}
@end

@interface StudioHome : UITableViewController <UISearchResultsUpdating,UISearchControllerDelegate>
@property NSUInteger reloadGeneration;
@property NSDictionary *projectFileCounts;
@property NSArray<NSString *> *recent;
@property CompilerController *importer;
@property NSDictionary *saveDates;
@property BOOL allProjects;
@property BOOL trashMode;
@property UISearchController *projectSearch;
@property NSSet<NSString *> *selectedProjects;
@property BOOL selectionMode;
@property NSArray<NSString *> *visibleProjects;
@property NSString *pendingProject;
@property StudioEditor *loadingEditor;
@property BOOL sharingProject;
@end
@implementation StudioHome
- (void)dealloc{[[NSNotificationCenter defaultCenter] removeObserver:self];}
- (void)viewDidLoad {
 [super viewDidLoad];ApplyTheme(self);[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadProjects) name:UIApplicationWillEnterForegroundNotification object:nil];self.tableView.rowHeight=76;self.definesPresentationContext=YES;
 if(self.allProjects||self.trashMode){self.title=self.trashMode?@"项目回收站":@"全部项目";if(!self.trashMode){self.projectSearch=[[UISearchController alloc] initWithSearchResultsController:nil];self.projectSearch.searchResultsUpdater=self;self.projectSearch.delegate=self;self.projectSearch.obscuresBackgroundDuringPresentation=NO;self.projectSearch.searchBar.placeholder=@"搜索项目名称";self.projectSearch.searchBar.autocapitalizationType=UITextAutocapitalizationTypeNone;self.navigationItem.searchController=self.projectSearch;self.navigationItem.hidesSearchBarWhenScrolling=NO;[self updateProjectActions];}return;}
 self.title=@"Dylix";self.navigationItem.backButtonTitle=@"项目";self.tableView.separatorStyle=UITableViewCellSeparatorStyleNone;self.tableView.backgroundColor=UIColor.systemBackgroundColor;
 UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,320,300)];UIStackView *stack=Stack(header);stack.spacing=10;[NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:22],[stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-22],[stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],[stack.bottomAnchor constraintLessThanOrEqualToAnchor:header.bottomAnchor constant:-4]]];UILabel *brand=Label(@"[·]  LOCAL STUDIO",13,YES);brand.textColor=Gold();brand.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightSemibold];[stack addArrangedSubview:brand];[stack addArrangedSubview:Label(@"下一个想法，\n从这里开始。",27,YES)];UILabel *sub=Label(@"代码、工具链和你的项目，都在手边。",12,NO);sub.textColor=UIColor.secondaryLabelColor;[stack addArrangedSubview:sub];[stack addArrangedSubview:Button(@"创建项目",@"plus",self,@selector(createProject),YES)];UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[Button(@"打开项目",@"folder",self,@selector(openProject),NO)]];row.spacing=12;row.distribution=UIStackViewDistributionFillEqually;[stack addArrangedSubview:row];self.tableView.tableHeaderView=header;self.navigationController.navigationBar.prefersLargeTitles=NO;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)search{[self applyProjectFilter];[self updateProjectActions];[self.tableView reloadData];}
- (void)applyProjectFilter{NSString *query=self.projectSearch.searchBar.text?:@"";self.visibleProjects=query.length?[self.recent filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *path,NSDictionary *bindings){return [ProjectName(path) rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound;}]]:self.recent;}
- (void)updateProjectActions{
 if(!self.allProjects||self.trashMode)return;
 self.title=[NSString stringWithFormat:@"全部项目（%lu）",(unsigned long)self.recent.count];
 UIBarButtonItem *select=[[UIBarButtonItem alloc] initWithTitle:self.selectionMode?@"取消":@"多选" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelection)];
 if(self.selectionMode){
  self.navigationItem.rightBarButtonItems=@[select];
  UIBarButtonItem *all=[[UIBarButtonItem alloc] initWithTitle:@"全选" style:UIBarButtonItemStylePlain target:self action:@selector(selectAllProjects)];all.enabled=self.visibleProjects.count>0;
  UIBarButtonItem *space=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
  UIBarButtonItem *remove=[[UIBarButtonItem alloc] initWithTitle:[NSString stringWithFormat:@"删除（%lu）",(unsigned long)self.selectedProjects.count] style:UIBarButtonItemStylePlain target:self action:@selector(deleteSelectedProjects)];remove.enabled=self.selectedProjects.count>0;remove.tintColor=UIColor.systemRedColor;
  self.toolbarItems=@[all,space,remove];
 }else{
  UIBarButtonItem *recycle=[[UIBarButtonItem alloc] initWithTitle:@"回收站" style:UIBarButtonItemStylePlain target:self action:@selector(showTrash)];
  self.navigationItem.rightBarButtonItems=@[select,recycle];self.toolbarItems=@[];
 }
 [self.navigationController setToolbarHidden:!self.selectionMode animated:YES];
}
- (void)toggleSelection{self.selectionMode=!self.selectionMode;self.selectedProjects=[NSSet set];[self updateProjectActions];[self.tableView reloadData];}
- (void)toggleProject:(NSString *)path{NSMutableSet *items=[self.selectedProjects mutableCopy]?:[NSMutableSet new];if([items containsObject:path])[items removeObject:path];else[items addObject:path];self.selectedProjects=items;[self updateProjectActions];[self.tableView reloadData];}
- (void)selectAllProjects{self.selectedProjects=[NSSet setWithArray:self.visibleProjects];[self updateProjectActions];[self.tableView reloadData];}
- (void)deleteSelectedProjects{if(!self.selectionMode||!self.selectedProjects.count)return;NSArray *paths=self.selectedProjects.allObjects;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认删除所选项目？" message:[NSString stringWithFormat:@"将删除所选的 %lu 个项目。",(unsigned long)paths.count] preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(id action){for(NSString *path in paths)[self deleteProjectConfirmed:path];self.selectionMode=NO;self.selectedProjects=[NSSet set];[self reloadProjects];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];ApplyTheme(self);self.navigationController.toolbarHidden=YES;[self reloadProjects];}
- (void)reloadProjects {
 NSUInteger generation=++self.reloadGeneration;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
 NSMutableArray *a=[NSMutableArray new];NSFileManager *fm=NSFileManager.defaultManager;TMCPruneProjectTrash([Docs() stringByAppendingPathComponent:@".StudioTrash"],NSDate.date);
 if(self.trashMode){NSString *trash=[Docs() stringByAppendingPathComponent:@".StudioTrash"];for(NSString *name in [fm contentsOfDirectoryAtPath:trash error:nil]){NSString *p=Child(trash,name);BOOL dir=NO;if(p&&[fm fileExistsAtPath:p isDirectory:&dir]&&dir)[a addObject:p];}}
 else {
 for(NSString *name in [NSUserDefaults.standardUserDefaults arrayForKey:@"StudioRecent"]){if(!NameOK(name))continue;NSString *root=[name hasPrefix:@"Imported-"]?[Docs() stringByAppendingPathComponent:name]:[Projects() stringByAppendingPathComponent:name];BOOL dir=NO;if([fm fileExistsAtPath:root isDirectory:&dir]&&dir&&![a containsObject:root])[a addObject:root];}
 for(NSString *parent in @[Projects(),Docs()])for(NSString *name in [[fm contentsOfDirectoryAtPath:parent error:nil] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]){if([name hasPrefix:@"."]||([parent isEqual:Docs()]&&![name hasPrefix:@"Imported-"]))continue;NSString *root=Child(parent,name);BOOL dir=NO;if(root&&[fm fileExistsAtPath:root isDirectory:&dir]&&dir&&![a containsObject:root])[a addObject:root];}
 }
 NSMutableDictionary *dates=[NSMutableDictionary new],*counts=[NSMutableDictionary new];for(NSString *root in a){NSUInteger count=0;NSDate *date=LastSaved(root,&count);counts[root]=@(count);if(date)dates[root]=date;}[a sortUsingComparator:^NSComparisonResult(NSString *left,NSString *right){NSComparisonResult order=[(dates[right]?:NSDate.distantPast) compare:(dates[left]?:NSDate.distantPast)];return order==NSOrderedSame?[left localizedStandardCompare:right]:order;}];dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.reloadGeneration)return;self.projectFileCounts=counts;self.recent=a;self.saveDates=dates;NSMutableSet *valid=[self.selectedProjects mutableCopy];[valid intersectSet:[NSSet setWithArray:a]];self.selectedProjects=valid?:[NSSet set];[self applyProjectFilter];[self updateProjectActions];[self.tableView reloadData];});});
}
- (void)showAllProjects{StudioHome *v=[[StudioHome alloc] initWithStyle:UITableViewStyleInsetGrouped];v.allProjects=YES;[self.navigationController pushViewController:v animated:YES];}
- (void)showTrash{StudioHome *v=[[StudioHome alloc] initWithStyle:UITableViewStyleInsetGrouped];v.trashMode=YES;[self.navigationController pushViewController:v animated:YES];}
- (void)editProject:(NSString *)root{StudioProjectSettings *v=[[StudioProjectSettings alloc] initWithStyle:UITableViewStyleInsetGrouped];v.root=root;__weak typeof(self) w=self;v.completion=^{[w reloadProjects];};[self.navigationController pushViewController:v animated:YES];}
- (void)renameProject:(NSString *)root {
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"重命名项目" message:@"修改项目显示名，源文件与产物名称保持原值。" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=ProjectName(root);field.accessibilityLabel=@"新项目名称";}];
 [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){Message(self,@"Git 正在处理",@"请稍后重命名项目。");return;}NSString *name=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!NameOK(name)){Message(self,@"名称格式有误",@"请填写有效的项目名称。");return;}NSString *invalid=ValidateProject(root);if(invalid){Message(self,@"请先修正工程配置",invalid);return;}NSMutableDictionary *config=[Config(root) mutableCopy];config[@"name"]=name;NSError *error=nil;
 NSString *manifest=[root stringByAppendingPathComponent:@"MobileCompiler.json"],*control=[root stringByAppendingPathComponent:@"control"];NSData *oldManifest=[NSData dataWithContentsOfFile:manifest];NSString *old=[NSString stringWithContentsOfFile:control encoding:NSUTF8StringEncoding error:nil];
 if(!JSONWrite(config,manifest,&error)){Message(self,@"重命名失败",error.localizedDescription);return;}
 if(old){NSMutableArray *lines=[NSMutableArray new];BOOL found=NO;for(NSString *line in [old componentsSeparatedByString:@"\n"]){if([line hasPrefix:@"Name:"]){[lines addObject:[@"Name: " stringByAppendingString:name]];found=YES;}else [lines addObject:line];}if(!found)[lines insertObject:[@"Name: " stringByAppendingString:name] atIndex:0];if(![[lines componentsJoinedByString:@"\n"] writeToFile:control atomically:YES encoding:NSUTF8StringEncoding error:&error]){if(oldManifest)[oldManifest writeToFile:manifest atomically:YES];else [NSFileManager.defaultManager removeItemAtPath:manifest error:nil];Message(self,@"重命名失败",error.localizedDescription);return;}}
 MarkSaved(root);[self reloadProjects];}]];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
- (void)deleteProject:(NSString *)root {
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认删除项目？" message:[NSString stringWithFormat:@"项目“%@”将移入回收站保留 7 天，过期后永久删除。",ProjectName(root)] preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(id action){[self deleteProjectConfirmed:root];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)deleteProjectConfirmed:(NSString *)root {TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease tryWrite];if(!lease){Message(self,@"Git 正在处理",@"请稍后删除项目。");return;}[[TMCGitAutomation shared] cancelPending:root];
 NSString *parent=root.stringByDeletingLastPathComponent;if(![parent isEqual:Projects()]&&![parent isEqual:Docs()])return;
 NSString *trash=[Docs() stringByAppendingPathComponent:@".StudioTrash"];NSError *e=nil;[NSFileManager.defaultManager createDirectoryAtPath:trash withIntermediateDirectories:YES attributes:nil error:&e];NSString *dest=[trash stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 NSDictionary *entry=@{@"originalName":root.lastPathComponent,@"parent":[parent isEqual:Projects()]?@"Projects":@"Documents",@"deletedAt":@(NSDate.date.timeIntervalSince1970)};
 if(e||!JSONWrite(entry,[root stringByAppendingPathComponent:@".studio-trash.json"],&e)||![NSFileManager.defaultManager moveItemAtPath:root toPath:dest error:&e]){[NSFileManager.defaultManager removeItemAtPath:[root stringByAppendingPathComponent:@".studio-trash.json"] error:nil];Message(self,@"删除未完成",e.localizedDescription);return;}
 NSMutableArray *recent=[[NSUserDefaults.standardUserDefaults arrayForKey:@"StudioRecent"] mutableCopy];[recent removeObject:root.lastPathComponent];[NSUserDefaults.standardUserDefaults setObject:recent?:@[] forKey:@"StudioRecent"];if([[NSUserDefaults.standardUserDefaults stringForKey:@"ImportedProject"] isEqual:root.lastPathComponent])[NSUserDefaults.standardUserDefaults removeObjectForKey:@"ImportedProject"];[self reloadProjects];
}
- (void)restoreProject:(NSString *)root {
 NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".studio-trash.json"]];id entry=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;NSString *name=[entry isKindOfClass:NSDictionary.class]?entry[@"originalName"]:nil;if(![name isKindOfClass:NSString.class]||!NameOK(name)){Message(self,@"恢复信息缺失",@"回收站保留了工程文件，请导出副本后检查。");return;}
 NSString *parent=[entry[@"parent"] isEqual:@"Projects"]?Projects():Docs();NSString *dest=[parent stringByAppendingPathComponent:name];if([NSFileManager.defaultManager fileExistsAtPath:dest])dest=[parent stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-Recovered-%@",[parent isEqual:Docs()]?@"Imported":name,NSUUID.UUID.UUIDString]];
 NSError *e=nil;if(![NSFileManager.defaultManager moveItemAtPath:root toPath:dest error:&e]){Message(self,@"恢复未完成",e.localizedDescription);return;}[NSFileManager.defaultManager removeItemAtPath:[dest stringByAppendingPathComponent:@".studio-trash.json"] error:nil];RecordRecent(dest);[self reloadProjects];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)i {
 NSArray *rows=self.allProjects&&!self.trashMode?self.visibleProjects:self.recent;if(self.selectionMode||i.row>=rows.count)return nil;NSString *root=rows[i.row];__weak typeof(self) w=self;
 if(self.trashMode){UIContextualAction *restore=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"恢复" handler:^(UIContextualAction *a,UIView *v,void(^done)(BOOL)){done(YES);[w restoreProject:root];}];restore.backgroundColor=UIColor.systemGreenColor;return [UISwipeActionsConfiguration configurationWithActions:@[restore]];}
 UIContextualAction *del=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a,UIView *v,void(^done)(BOOL)){done(YES);[w deleteProject:root];}];del.image=[UIImage systemImageNamed:@"trash"];
 UIContextualAction *share=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"分享" handler:^(UIContextualAction *a,UIView *v,void(^done)(BOOL)){done(YES);[w shareProject:root];}];share.image=[UIImage systemImageNamed:@"square.and.arrow.up"];share.backgroundColor=UIColor.systemGreenColor;
 UIContextualAction *edit=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"编辑" handler:^(UIContextualAction *a,UIView *v,void(^done)(BOOL)){done(YES);[w editProject:root];}];UIImage *editIcon=[UIImage systemImageNamed:@"pencil"];editIcon.accessibilityLabel=@"编辑项目设置";edit.image=editIcon;edit.backgroundColor=UIColor.systemYellowColor;
 UISwipeActionsConfiguration *config=[UISwipeActionsConfiguration configurationWithActions:@[del,edit,share]];config.performsFirstActionWithFullSwipe=NO;return config;
}
- (void)shareProject:(NSString *)root{
 UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"分享项目" message:@"分享源码默认排除 Git 历史、本机状态、常见密钥和构建缓存。完整归档包含项目根目录中的所有文件，请确认分享范围。" preferredStyle:UIAlertControllerStyleAlert];
 [sheet addAction:[UIAlertAction actionWithTitle:@"分享源码 ZIP" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self shareProject:root sourceOnly:YES];}]];
 [sheet addAction:[UIAlertAction actionWithTitle:@"完整归档 ZIP" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self shareProject:root sourceOnly:NO];}]];
 [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:sheet animated:YES completion:nil];
}
- (void)shareProject:(NSString *)root sourceOnly:(BOOL)sourceOnly{
 if(self.sharingProject)return;self.sharingProject=YES;
 UIAlertController *progress=[UIAlertController alertControllerWithTitle:@"正在压缩项目" message:@"打包完成后打开系统分享面板。" preferredStyle:UIAlertControllerStyleAlert];
 [self presentViewController:progress animated:YES completion:^{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
   NSFileManager *fm=NSFileManager.defaultManager;NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"ProjectShare-" stringByAppendingString:NSUUID.UUID.UUIDString]];
   NSString *name=ProjectName(root);if(!NameOK(name))name=@"Project";NSURL *output=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"zip"]]];
   NSError *error=nil;[fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error];
   __block NSError *copyError=nil;NSString *shareRoot=root;
   if(sourceOnly){shareRoot=[folder stringByAppendingPathComponent:@"Source"];TMCGitLease *lease __attribute__((objc_precise_lifetime))=[TMCGitLease acquire];if(!TMCCopyProject(root,shareRoot,YES,[NSProgress progressWithTotalUnitCount:1],nil,&error))shareRoot=nil;}
   if(!error){NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];[coordinator coordinateReadingItemAtURL:[NSURL fileURLWithPath:shareRoot] options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL *archive){[fm copyItemAtURL:archive toURL:output error:&copyError];}];}
   NSError *failure=error?:copyError;
   dispatch_async(dispatch_get_main_queue(),^{self.sharingProject=NO;[progress dismissViewControllerAnimated:YES completion:^{
    if(failure){[fm removeItemAtPath:folder error:nil];Message(self,@"项目压缩失败",failure.localizedDescription);return;}
    UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[output] applicationActivities:nil];sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    sheet.completionWithItemsHandler=^(UIActivityType type,BOOL completed,NSArray *items,NSError *shareError){[fm removeItemAtPath:folder error:nil];};[self presentViewController:sheet animated:YES completion:nil];
   }];});
  });
 }];
}
- (void)createProject{[self.navigationController pushViewController:[[StudioCreate alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
- (void)settings{[self.navigationController pushViewController:[[StudioSettings alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return self.allProjects&&!self.trashMode?(self.visibleProjects.count?:1):self.recent.count?(self.trashMode?self.recent.count:MIN(3,self.recent.count)):1;}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];UIView *header=self.tableView.tableHeaderView;if(!header)return;CGFloat width=self.tableView.bounds.size.width;UIStackView *stack=header.subviews.firstObject;CGFloat height=[stack systemLayoutSizeFittingSize:CGSizeMake(MAX(1,width-44),UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height+14;if(fabs(header.bounds.size.height-height)>1||fabs(header.bounds.size.width-width)>1){header.frame=CGRectMake(0,0,width,height);self.tableView.tableHeaderView=header;}}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section{return self.allProjects&&!self.trashMode?CGFLOAT_MIN:38;}
- (UIView *)tableView:(UITableView *)t viewForHeaderInSection:(NSInteger)section {
 if(self.allProjects&&!self.trashMode)return nil;
 UIView *header=[UIView new];UILabel *label=Label(self.trashMode?@"左滑恢复项目":@"最近项目",12,YES);label.textColor=UIColor.secondaryLabelColor;label.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:label];[NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:22],[label.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]]];
 if(!self.allProjects&&!self.trashMode){UIButton *all=[UIButton buttonWithType:UIButtonTypeSystem];[all setTitle:@"全部项目 ›" forState:UIControlStateNormal];all.accessibilityLabel=@"全部项目";all.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];all.tintColor=Gold();all.translatesAutoresizingMaskIntoConstraints=NO;[all addTarget:self action:@selector(showAllProjects) forControlEvents:UIControlEventTouchUpInside];[header addSubview:all];[NSLayoutConstraint activateConstraints:@[[all.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-22],[all.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],[all.heightAnchor constraintEqualToConstant:44],[label.trailingAnchor constraintLessThanOrEqualToAnchor:all.leadingAnchor constant:-12]]];}return header;
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)section{return self.trashMode?@"回收站保留 7 天，到期后在下次打开软件时永久清理。左滑或点按可恢复。":@"左滑项目可分享 ZIP、编辑设置或删除。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i{UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];if(!self.recent.count){c.textLabel.text=self.trashMode?@"回收站为空":@"创建第一个项目，或打开现有工程";c.textLabel.font=[UIFont systemFontOfSize:13];c.textLabel.textColor=UIColor.secondaryLabelColor;return c;}NSArray *rows=self.allProjects&&!self.trashMode?self.visibleProjects:self.recent;if(i.row>=rows.count){c.textLabel.text=self.projectSearch.searchBar.text.length?@"没有匹配的项目":@"本机还没有项目";c.textLabel.textColor=UIColor.secondaryLabelColor;return c;}NSString *p=rows[i.row];c.textLabel.text=ProjectName(p);c.textLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightMedium];NSDate *date=self.saveDates[p];NSString *saved=SavedTimeLabel(date,NSDate.date);NSUInteger files=[self.projectFileCounts[p] unsignedIntegerValue];c.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %lu 个文件 · 最后保存 %@",[Config(p)[@"package"] isEqual:@NO]?@"动态库":@"插件工程",(unsigned long)files,saved];c.detailTextLabel.numberOfLines=2;c.detailTextLabel.font=[UIFont systemFontOfSize:11];if(date){NSDateFormatter *exact=[NSDateFormatter new];exact.dateFormat=@"yyyy-MM-dd HH:mm:ss";c.accessibilityValue=[@"最后保存 " stringByAppendingString:[exact stringFromDate:date]];}c.detailTextLabel.textColor=UIColor.secondaryLabelColor;c.imageView.image=[UIImage systemImageNamed:@"curlybraces.square"];c.imageView.tintColor=Gold();if(self.selectionMode){c.accessoryView=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[self.selectedProjects containsObject:p]?@"checkmark.circle.fill":@"circle"]];((UIImageView *)c.accessoryView).tintColor=Gold();}c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)i{return 76;}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i{[t deselectRowAtIndexPath:i animated:YES];NSArray *rows=self.allProjects&&!self.trashMode?self.visibleProjects:self.recent;if(i.row>=rows.count)return;NSString *path=rows[i.row];if(self.selectionMode){[self toggleProject:path];return;}if(self.trashMode){[self restoreProject:path];return;}if(self.projectSearch.active){self.pendingProject=path;self.projectSearch.active=NO;}else[self openSelectedProject:path];}
- (void)openSelectedProject:(NSString *)path{
 UIView *host=self.navigationController.view;if([host viewWithTag:8048])return;
 MBProgressHUD *hud=[MBProgressHUD showHUDAddedTo:host animated:!UIAccessibilityIsReduceMotionEnabled()];hud.tag=8048;hud.removeFromSuperViewOnHide=YES;hud.mode=MBProgressHUDModeAnnularDeterminate;hud.contentColor=Gold();hud.margin=18;hud.minSize=CGSizeMake(92,92);hud.animationType=MBProgressHUDAnimationFade;hud.backgroundView.style=MBProgressHUDBackgroundStyleSolidColor;hud.backgroundView.color=UIColor.clearColor;hud.bezelView.style=UIAccessibilityIsReduceTransparencyEnabled()?MBProgressHUDBackgroundStyleSolidColor:MBProgressHUDBackgroundStyleBlur;hud.bezelView.color=UIColor.secondarySystemBackgroundColor;
 NSProgress *progress=[NSProgress progressWithTotalUnitCount:3];hud.progressObject=progress;hud.label.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];hud.label.text=@"检查工程";hud.label.numberOfLines=1;hud.isAccessibilityElement=YES;hud.accessibilityLabel=@"打开项目进度";hud.accessibilityValue=@"检查工程";
 self.tableView.userInteractionEnabled=NO;
 // Count completed work, never advance a fake timer toward 100 percent.
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  BOOL directory=NO;BOOL exists=[NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory];
  NSDictionary *config=exists&&directory?Config(path):nil;
  dispatch_async(dispatch_get_main_queue(),^{
   if(!exists||!directory){[hud hideAnimated:NO];self.tableView.userInteractionEnabled=YES;Message(self,@"工程不存在",@"请重新选择工程目录。");return;}
   (void)config;progress.completedUnitCount=1;hud.label.text=@"读取配置";hud.accessibilityValue=hud.label.text;
   dispatch_async(dispatch_get_main_queue(),^{
    StudioEditor *v=[StudioEditor new];v.root=path;self.loadingEditor=v;__weak StudioEditor *weakEditor=v;__weak typeof(self) weakHome=self;
    v.initialSyntaxReady=^{progress.completedUnitCount=3;hud.label.text=@"准备完成";hud.accessibilityValue=hud.label.text;
     // Let the completed state render once, then navigate without a forced delay.
     dispatch_async(dispatch_get_main_queue(),^{StudioHome *home=weakHome;StudioEditor *editor=weakEditor;[hud hideAnimated:NO];home.tableView.userInteractionEnabled=YES;if(home&&editor)[home.navigationController pushViewController:editor animated:YES];home.loadingEditor=nil;});};
    [v loadViewIfNeeded];progress.completedUnitCount=2;hud.label.text=@"打开文件";hud.accessibilityValue=hud.label.text;
    if(v.initialSyntaxReady){void (^ready)(void)=v.initialSyntaxReady;v.initialSyntaxReady=nil;if(ready)ready();}
   });
  });
 });
}
- (void)didDismissSearchController:(UISearchController *)search{if(self.pendingProject){NSString *path=self.pendingProject;self.pendingProject=nil;[self openSelectedProject:path];}}
- (void)openProject{
 if(self.presentedViewController||self.importer.importInProgress)return;
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"打开项目" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
 [a addAction:[UIAlertAction actionWithTitle:@"接收的文件" style:UIAlertActionStyleDefault handler:^(id action){UIViewController *v=TFIncomingHistory();[self.navigationController pushViewController:v animated:YES];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"从文件或压缩包导入" style:UIAlertActionStyleDefault handler:^(id action){[self importLocalProject];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"从 Git 仓库克隆" style:UIAlertActionStyleDefault handler:^(id action){__weak typeof(self) weak=self;UIViewController *v=TMCGitCloneController(Projects(),^(NSString *root){[weak.navigationController popToViewController:weak animated:NO];[weak openSelectedProject:root];});[self.navigationController pushViewController:v animated:YES];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.tableView.tableHeaderView;a.popoverPresentationController.sourceRect=CGRectMake(20,220,180,44);[self presentViewController:a animated:YES completion:nil];
}
- (void)importLocalProject{
 if(self.presentedViewController||self.importer.importInProgress)return;
 self.importer=[CompilerController new];
 self.importer.presentationHost=self;
 __weak typeof(self) weakSelf=self;
 self.importer.importCompletion=^(NSString *path){[weakSelf openSelectedProject:path];};
 [self.importer importSource];
}
@end

NSArray<NSDictionary *> *TFAIInternalProjects(void) {
 NSMutableArray *items=[NSMutableArray new];NSFileManager *fm=NSFileManager.defaultManager;
 // Match the home screen: created projects and legacy imported projects.
 for(NSString *base in @[Projects(),Docs()])for(NSString *name in [fm contentsOfDirectoryAtPath:base error:nil]){
  if([name hasPrefix:@"."]||([base isEqual:Docs()]&&![name hasPrefix:@"Imported-"]))continue;
  NSString *root=Child(base,name);NSDictionary *a=root?[fm attributesOfItemAtPath:root error:nil]:nil;
  if(![a[NSFileType] isEqual:NSFileTypeDirectory])continue;
  NSString *identifier=TFAIProjectID(root);if(!identifier)continue;
  [items addObject:@{@"id":identifier,@"name":ProjectName(root),@"root":root}];
 }
 return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedStandardCompare:b[@"name"]];}];
}
// Conversation-owned project service. Storage remains in its original scope.
static void AIWorkspaceTool(NSMutableDictionary *owner,NSString *tool,NSDictionary *args,TFAIResult completion){
 if([tool isEqual:@"cancel_workspace"]){[(NSProgress *)owner[@"workspaceProgress"] cancel];[(TMCGitService *)owner[@"workspaceGit"] setCancelled:YES];completion(@{},nil);return;}
 if([tool isEqual:@"list_projects"]){NSMutableArray *items=[NSMutableArray new];for(NSDictionary *p in TFAIInternalProjects())[items addObject:@{@"project_id":p[@"id"],@"name":p[@"name"]}];completion(@{@"projects":items},nil);return;}
 if(![@[@"create_project",@"clone_project",@"select_project"] containsObject:tool]){StudioEditor *editor=owner[@"editor"];if(editor)[editor aiTool:tool arguments:args completion:completion];else completion(nil,[NSError errorWithDomain:@"AI.Workspace" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请先创建、克隆或选择项目"}]);return;}
 NSProgress *progress=[NSProgress progressWithTotalUnitCount:1];owner[@"workspaceProgress"]=progress;
 dispatch_async(TMCGitService.queue,^{NSError *error=nil;NSString *root=nil,*name=args[@"name"];
 if([tool isEqual:@"select_project"]){for(NSDictionary *p in TFAIInternalProjects())if([p[@"id"] isEqual:args[@"project_id"]]){root=p[@"root"];name=p[@"name"];}if(!root)error=[NSError errorWithDomain:@"AI.Workspace" code:2 userInfo:@{NSLocalizedDescriptionKey:@"项目已移动或不存在，请重新列出项目"}];}
 else if(!NameOK(name)||name.length>80||[name hasPrefix:@"."]){error=[NSError errorWithDomain:@"AI.Workspace" code:3 userInfo:@{NSLocalizedDescriptionKey:@"请输入有效项目名"}];}
 else {root=[Projects() stringByAppendingPathComponent:name];NSString *temp=[Projects() stringByAppendingPathComponent:[@".creating-" stringByAppendingString:NSUUID.UUID.UUIDString]];
 if([NSFileManager.defaultManager fileExistsAtPath:root])error=[NSError errorWithDomain:@"AI.Workspace" code:4 userInfo:@{NSLocalizedDescriptionKey:@"同名项目已存在，未覆盖"}];
 else {BOOL ok=NO;if([tool isEqual:@"clone_project"]){NSURLComponents *url=[NSURLComponents componentsWithString:args[@"url"]];if([url.scheme.lowercaseString isEqual:@"https"]&&url.host.length&&!url.user&&!url.password&&!url.query&&!url.fragment){TMCGitService *git=[[TMCGitService alloc]initWithRoot:temp];dispatch_sync(dispatch_get_main_queue(),^{owner[@"workspaceGit"]=git;git.cancelled=progress.cancelled;});ok=[git cloneURL:args[@"url"] error:&error];}else error=[NSError errorWithDomain:@"AI.Workspace" code:5 userInfo:@{NSLocalizedDescriptionKey:@"仓库地址须为不含凭据的 HTTPS URL"}];}
 else {NSString *kind=args[@"template"];if([@[@"logos",@"objectivec",@"dylib"] containsObject:kind]){NSString *resource=[kind isEqual:@"logos"]?@"SampleProject":@"SampleObjectiveC";ok=[NSFileManager.defaultManager copyItemAtPath:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:resource] toPath:temp error:&error];if(ok){NSMutableDictionary *config=[Config(temp) mutableCopy]?:[NSMutableDictionary new];config[@"name"]=name;config[@"productName"]=@"DylixTweak";config[@"sources"]=[kind isEqual:@"logos"]?@[@"Tweak.xm"]:@[@"Test.m"];config[@"frameworks"]=[kind isEqual:@"logos"]?@[@"Foundation",@"UIKit",@"CydiaSubstrate"]:@[@"Foundation",@"UIKit"];if([kind isEqual:@"dylib"])config[@"package"]=@NO;ok=JSONWrite(config,[temp stringByAppendingPathComponent:@"MobileCompiler.json"],&error);}}else error=[NSError errorWithDomain:@"AI.Workspace" code:6 userInfo:@{NSLocalizedDescriptionKey:@"请选择有效模板"}];}
 if(progress.cancelled){ok=NO;error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"项目操作已取消"}];}if(ok)ok=[NSFileManager.defaultManager moveItemAtPath:temp toPath:root error:&error];if(!ok){[NSFileManager.defaultManager removeItemAtPath:temp error:nil];if(!error)error=[NSError errorWithDomain:@"AI.Workspace" code:7 userInfo:@{NSLocalizedDescriptionKey:@"项目创建失败"}];}else MarkSaved(root);}}
 dispatch_async(dispatch_get_main_queue(),^{if(owner[@"workspaceProgress"]==progress){[owner removeObjectForKey:@"workspaceGit"];[owner removeObjectForKey:@"workspaceProgress"];}if(error||progress.cancelled){completion(nil,error?:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);return;}StudioEditor *editor=[StudioEditor new];editor.root=root;[editor loadViewIfNeeded];owner[@"editor"]=editor;completion(@{@"root":root,@"projectID":TFAIProjectID(root),@"name":name?:root.lastPathComponent},nil);});
 });
}
static void OpenAISession(UINavigationController *nav,NSDictionary *record,id sourceEditor) {
 if(!nav)return;NSString *scope=record[@"storageProjectID"]?:@"general",*identifier=record[@"id"];TFAIFlushOpenSession(scope,identifier);
 __weak UINavigationController *weakNav=nav;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSMutableDictionary *session=[TFAISessions loadSession:identifier project:scope];dispatch_async(dispatch_get_main_queue(),^{UINavigationController *n=weakNav;if(!n||!session)return;if([record[@"incomingAttachments"] isKindOfClass:NSArray.class]){NSMutableArray *pending=[session[@"pendingAttachments"] mutableCopy]?:[NSMutableArray new];for(NSDictionary *entry in record[@"incomingAttachments"])if(![pending containsObject:entry])[pending addObject:entry];session[@"pendingAttachments"]=pending;[TFAISessions saveMetadata:@{@"pendingAttachments":pending} identifier:identifier project:scope error:nil];}
  if(![scope isEqual:@"general"]){NSDictionary *project=nil;for(NSDictionary *p in TFAIInternalProjects())if([p[@"id"] isEqual:scope]){project=p;break;}if(!project){Message(n.topViewController,@"关联项目已不在本机",@"会话历史仍保留。请从会话列表重新关联可用项目；不会自动使用旧路径。");return;}StudioEditor *editor=nil;if(![editor.root isEqual:project[@"root"]]){editor=[StudioEditor new];editor.root=project[@"root"];[editor loadViewIfNeeded];}editor.aiNavigation=n;session[@"projectName"]=project[@"name"];session[@"projectRoot"]=project[@"root"];[editor openAIRecord:session];return;}
  NSMutableDictionary *owner=[NSMutableDictionary new];NSString *workspaceRoot=@"";for(NSDictionary *p in TFAIInternalProjects())if([p[@"id"] isEqual:session[@"workspaceID"]]){workspaceRoot=p[@"root"];StudioEditor *editor=[StudioEditor new];editor.root=workspaceRoot;[editor loadViewIfNeeded];owner[@"editor"]=editor;session[@"projectName"]=p[@"name"];session[@"projectRoot"]=workspaceRoot;break;}
  void (^bridge)(NSString *,NSDictionary *,TFAIResult)=^(NSString *tool,NSDictionary *arguments,TFAIResult completion){AIWorkspaceTool(owner,tool,arguments,completion);};
  id<TFAIRuntime> runtime=TFAICreateRuntime(workspaceRoot,@"general",bridge);UIViewController *chat=TFAIChatController(workspaceRoot,@"general",runtime,^(NSString *path,NSUInteger line){StudioEditor *editor=owner[@"editor"];if(editor){[weakNav pushViewController:editor animated:YES];}});chat=TFAIConfigureChat(chat,session,!workspaceRoot.length,^(NSDictionary *project){AssociateAISession(weakNav,session,project);});TFAISetProjectContext(chat,owner,bridge);TFAISetSessionOpener(chat,^(NSDictionary *r){OpenAISession(weakNav,r,nil);});if([n.viewControllers containsObject:chat])[n popToViewController:chat animated:YES];else{UINavigationController *old=chat.navigationController;if(old){NSMutableArray *stack=[old.viewControllers mutableCopy];[stack removeObject:chat];[old setViewControllers:stack animated:NO];}[n pushViewController:chat animated:YES];}
 });});
}
static void AssociateAISession(UINavigationController *nav,NSDictionary *record,NSDictionary *project) {
 if(!nav||!project)return;NSDictionary *actual=nil;for(NSDictionary *p in TFAIInternalProjects())if([p[@"id"] isEqual:project[@"id"]])actual=p;if(!actual)return;
 UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"关联项目并新建会话？" message:[NSString stringWithFormat:@"目标：%@\n原会话与操作记录保持不变。新会话只获得该项目范围，参考附件不会自动写入工程。",actual[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
 [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
 [confirm addAction:[UIAlertAction actionWithTitle:@"创建关联会话" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSMutableDictionary *fresh=[TFAISessions create:actual[@"id"] title:record[@"title"]?:@"项目会话"];fresh[@"projectName"]=actual[@"name"];fresh[@"projectRoot"]=actual[@"root"];fresh[@"storageProjectID"]=actual[@"id"];fresh[@"mode"]=@"ask";NSError *error=nil;BOOL ok=[TFAISessions save:fresh project:actual[@"id"] error:&error];dispatch_async(dispatch_get_main_queue(),^{if(!ok){Message(nav.topViewController,@"创建失败",error.localizedDescription);return;}OpenAISession(nav,fresh,nil);});});}]];[nav.topViewController presentViewController:confirm animated:YES completion:nil];
}
@interface TFStudioTabs : UITabBarController
@end
@implementation TFStudioTabs
- (void)viewDidLoad{[super viewDidLoad];self.tabBar.tintColor=Gold();if(@available(iOS 26.0,*)){}else{UITabBarAppearance *a=[UITabBarAppearance new];[a configureWithDefaultBackground];a.backgroundEffect=UIAccessibilityIsReduceTransparencyEnabled()?nil:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];if(UIAccessibilityIsReduceTransparencyEnabled())a.backgroundColor=UIColor.systemBackgroundColor;self.tabBar.standardAppearance=a;self.tabBar.scrollEdgeAppearance=a;}}
@end
UIViewController *TMCStudioRoot(void) {
 TFStudioTabs *tabs=[TFStudioTabs new];TMCNavigationController *projects=[[TMCNavigationController alloc] initWithRootViewController:[[StudioHome alloc] initWithStyle:UITableViewStyleGrouped]];
 __block __weak UINavigationController *weakAI=nil;UIViewController *home=TFAISessionHomeController(nil,^NSArray *{return TFAIInternalProjects();},^(NSDictionary *record){OpenAISession(weakAI,record,nil);},^(NSDictionary *record,NSDictionary *project){AssociateAISession(weakAI,record,project);});
 TMCNavigationController *ai=[[TMCNavigationController alloc] initWithRootViewController:home];weakAI=ai;TMCNavigationController *settings=[[TMCNavigationController alloc] initWithRootViewController:[[StudioSettings alloc] initWithStyle:UITableViewStyleInsetGrouped]];
 [projects.topViewController loadViewIfNeeded];[home loadViewIfNeeded];[settings.topViewController loadViewIfNeeded];projects.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"项目" image:[UIImage systemImageNamed:@"square.stack.3d.up"] tag:0];ai.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"AI 会话" image:[UIImage systemImageNamed:@"bubble.left.and.bubble.right"] tag:1];settings.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"设置" image:[UIImage systemImageNamed:@"slider.horizontal.3"] tag:2];tabs.viewControllers=@[projects,ai,settings];return tabs;
}
void TMCOpenAIConversation(UIViewController *root,NSString *sessionID,NSString *projectID){if(![root isKindOfClass:UITabBarController.class])return;UITabBarController *tabs=(id)root;if(tabs.viewControllers.count<2)return;tabs.selectedIndex=1;UINavigationController *nav=(id)tabs.viewControllers[1];if(![nav isKindOfClass:UINavigationController.class])return;if(sessionID.length)OpenAISession(nav,@{@"id":sessionID,@"storageProjectID":projectID?:@"general"},nil);}
UIViewController *TMCStudioHome(void){return [[StudioHome alloc] initWithStyle:UITableViewStyleGrouped];}
#if TARGET_OS_SIMULATOR
UIViewController *TMCStudioSettingsRegression(void){return [[StudioSettings alloc] initWithStyle:UITableViewStyleInsetGrouped];}
UIViewController *TMCStudioFileActionsRegression(void){
 NSString *root=[Projects() stringByAppendingPathComponent:[@"FileActions-" stringByAppendingString:NSUUID.UUID.UUIDString]];
 [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 NSString *source=@"ThisIsAVeryLongSourceFilenameForTruncationTesting.m";
 [@"int file_action_fixture = 1;\n" writeToFile:[root stringByAppendingPathComponent:source] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 [@"Package: com.example.filefixture\nName: File actions fixture\nVersion: 1.0\n" writeToFile:[root stringByAppendingPathComponent:@"control"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 JSONWrite(@{@"name":@"用于验证标题省略和文件左滑操作的超长项目名称 File Actions Fixture",@"sources":@[source],@"package":@NO},[root stringByAppendingPathComponent:@"MobileCompiler.json"],nil);
 MarkSaved(root);RecordRecent(root);StudioEditor *editor=[StudioEditor new];editor.root=root;__weak StudioEditor *weak=editor;
 editor.initialSyntaxReady=^{dispatch_async(dispatch_get_main_queue(),^{[weak files];});};return editor;
}
UIViewController *TMCStudioRepairRegression(void){
 BOOL gitTest=[NSProcessInfo.processInfo.arguments containsObject:@"--repair-git-checkpoint-test"];NSString *root=[Docs() stringByAppendingPathComponent:gitTest?[@"RepairGitTest-" stringByAppendingString:NSUUID.UUID.UUIDString]:@"RepairSheetTest"];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];NSString *source=@"__weak typeof(self) weakSelf = self;\nstruct task_basic_info info;\n";NSString *path=[root stringByAppendingPathComponent:@"Tweak.xm"];[source writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];if(gitTest){TMCGitService *git=[[TMCGitService alloc] initWithRoot:root];[git initialize:nil];[git stage:@[@".gitignore",@"Tweak.xm"] remove:NO error:nil];[git commit:@"Before test" name:@"Test" email:@"test@example.com" error:nil];}StudioDiagnostics *v=[[StudioDiagnostics alloc] initWithStyle:UITableViewStylePlain];v.root=root;v.items=@[@{@"file":@"Tweak.xm",@"path":path,@"line":@1,@"column":@8,@"severity":@"error",@"message":@"expected unqualified-id"},@{@"file":@"Tweak.xm",@"path":path,@"line":@2,@"column":@1,@"severity":@"error",@"message":@"variable has incomplete type 'struct task_basic_info'"}];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[v repair];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.6*NSEC_PER_SEC),dispatch_get_main_queue(),^{UINavigationController *nav=(id)v.presentedViewController;StudioRepairPreview *preview=(id)nav.topViewController;BOOL ready=[preview isKindOfClass:StudioRepairPreview.class];NSUInteger initial=preview.selected.count;UIButton *button=nil;NSMutableArray *views=[NSMutableArray arrayWithObject:preview.content];while(views.count){UIView *view=views.lastObject;[views removeLastObject];if([view isKindOfClass:UIButton.class]&&((UIButton *)view).tag==0){button=(id)view;break;}[views addObjectsFromArray:view.subviews];}if(button)[preview toggleChange:button];if([NSProcessInfo.processInfo.arguments containsObject:@"--repair-confirm-test"]){[preview apply];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.35*NSEC_PER_SEC),dispatch_get_main_queue(),^{UIAlertController *alert=(id)preview.presentedViewController;BOOL applyPrompt=[alert isKindOfClass:UIAlertController.class]&&[alert.title isEqual:@"确认应用修复？"];BOOL before=[[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:source];[alert dismissViewControllerAnimated:NO completion:^{BOOL canceled=[[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:source];[preview applyConfirmed];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.0*NSEC_PER_SEC),dispatch_get_main_queue(),^{UIViewController *notice=v.presentedViewController;if(notice)[notice dismissViewControllerAnimated:NO completion:nil];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.6*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSString *changed=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];[v undoRepair];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.3*NSEC_PER_SEC),dispatch_get_main_queue(),^{UIAlertController *undo=(id)v.presentedViewController;BOOL undoPrompt=[undo isKindOfClass:UIAlertController.class]&&[undo.title isEqual:@"确认撤回上次修复？"];BOOL pending=[[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:changed];[undo dismissViewControllerAnimated:NO completion:^{BOOL undoCanceled=[[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:changed];[v undoRepairConfirmed];BOOL restored=[[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:source];JSONWrite(@{@"applyPrompt":@(applyPrompt),@"applyPromptNoWrite":@(before),@"applyCancelNoWrite":@(canceled),@"confirmedApplyChanged":@(![changed isEqual:source]),@"undoPrompt":@(undoPrompt),@"undoPromptNoWrite":@(pending),@"undoCancelNoWrite":@(undoCanceled),@"confirmedUndoRestored":@(restored),@"undoIcon":@(v.toolbarItems.firstObject.image!=nil),@"toolbarCount":@(v.toolbarItems.count),@"gitCheckpointRecorded":@(!gitTest||[[[[[TMCGitService alloc] initWithRoot:root] history:nil] valueForKey:@"message"] containsObject:@"Before compatibility repair"])},[Docs() stringByAppendingPathComponent:@"repair-confirm-test.json"],nil);}];});});});}];});return;}UIScrollView *scroll=(id)preview.content.superview;[scroll setContentOffset:CGPointMake(0,-scroll.adjustedContentInset.top) animated:NO];NSArray *chosen=TMCSelectedCompatibilityPlan(preview.plan,preview.selected);NSUInteger selected=0;for(NSDictionary *entry in chosen)selected+=[entry[@"edits"] count];JSONWrite(@{@"previewPresented":@(ready),@"planCount":@(ready?preview.plan.count:0),@"initialSelected":@(initial),@"afterToggle":@(preview.selected.count),@"selectedEdits":@(selected),@"catalogRules":@(TMCCompatibilityRules().count),@"sourceUnchanged":@([[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:source])},[Docs() stringByAppendingPathComponent:@"repair-sheet-test.json"],nil);});});return v;
}

UIViewController *TMCStudioAboutRegression(void){StudioAbout *about=[[StudioAbout alloc] initWithStyle:UITableViewStyleInsetGrouped];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{BOOL licenses=YES;for(NSDictionary *component in ThirdPartyComponents()){NSString *path=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:[@"ThirdPartyNotices" stringByAppendingPathComponent:component[@"file"]]];licenses=licenses&&[[NSData dataWithContentsOfFile:path] length]>100;}JSONWrite(@{@"sections":@([about numberOfSectionsInTableView:about.tableView]),@"components":@(ThirdPartyComponents().count),@"licenseFilesReadable":@(licenses),@"version":NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],@"aboutTitle":about.title},[Docs() stringByAppendingPathComponent:@"about-test.json"],nil);});return about;}
UIViewController *TMCStudioProjectSettingsRegression(void){
 NSString *root=[Docs() stringByAppendingPathComponent:@"ProjectSettingsSheetTest"];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];JSONWrite(@{@"name":@"项目设置测试",@"package":@NO,@"frameworks":@[@"Foundation",@"UIKit",@"AVFoundation",@"CoreGraphics",@"UserNotifications",@"LocalAuthentication",@"SystemConfiguration",@"QuartzCore",@"WebKit"]},[root stringByAppendingPathComponent:@"MobileCompiler.json"],nil);StudioProjectSettings *v=[[StudioProjectSettings alloc] initWithStyle:UITableViewStyleInsetGrouped];v.root=root;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSIndexPath *path=[NSIndexPath indexPathForRow:1 inSection:2];[v.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];[v tableView:v.tableView didSelectRowAtIndexPath:path];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{UINavigationController *nav=(id)v.presentedViewController;StudioValueEditor *editor=(id)nav.topViewController;NSDictionary *result=@{@"sheetPresented":@([editor isKindOfClass:StudioValueEditor.class]),@"detents":@(nav.sheetPresentationController.detents.count),@"editableText":editor.input.text?:@"",@"originalValue":v.fields[8].text?:@""};JSONWrite(result,[Docs() stringByAppendingPathComponent:@"project-settings-sheet-test.json"],nil);});});return v;
}
UIViewController *TMCStudioBuildPreferencesRegression(void){
 StudioBuildPreferences *settings=[[StudioBuildPreferences alloc] initWithStyle:UITableViewStyleInsetGrouped];
 BOOL project=[NSProcessInfo.processInfo.arguments containsObject:@"--project-build-preferences-test"];
 if(project){settings.root=[Docs() stringByAppendingPathComponent:@"BuildSwitchRegression"];[NSFileManager.defaultManager createDirectoryAtPath:settings.root withIntermediateDirectories:YES attributes:nil error:nil];JSONWrite(@{@"name":@"Switch regression",@"package":@YES,@"exportDylib":@YES},[settings.root stringByAppendingPathComponent:@"MobileCompiler.json"],nil);}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  [settings loadViewIfNeeded];settings.exportDylib=YES;settings.exportDeb=YES;[settings refreshChoices];
  NSIndexPath *path=[NSIndexPath indexPathForRow:project?2:1 inSection:1];UITableViewCell *cell=[settings tableView:settings.tableView cellForRowAtIndexPath:path];UISwitch *deb=nil;for(UIView *view in cell.contentView.subviews)if([view isKindOfClass:UISwitch.class])deb=(id)view;
  NSMutableDictionary *result=[NSMutableDictionary new];result[@"actualSwitchFound"]=@(deb!=nil);result[@"project"]=@(project);
  __block NSUInteger completed=0;__block BOOL states=YES,stable=YES;__block NSTimeInterval worst=0;
  for(NSUInteger i=0;i<40;i++)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(i*.05)*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;deb.on=(i%2)!=0;[deb sendActionsForControlEvents:UIControlEventValueChanged];[settings.view layoutIfNeeded];worst=MAX(worst,NSProcessInfo.processInfo.systemUptime-start);states=states&&(settings.exportDeb==deb.on);for(NSUInteger j=0;j<3;j++)states=states&&(settings.schemeSwitches[j].enabled==deb.on)&&(settings.schemeSwitches[j].on==(deb.on&&j==0));stable=stable&&cell==[settings tableView:settings.tableView cellForRowAtIndexPath:path];completed++;});
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2.3*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSDictionary *stored=TMCEffectiveBuildOptions(settings.root?Config(settings.root):@{},NSUserDefaults.standardUserDefaults);result[@"savedWithoutButton"]=@([stored[@"package"] boolValue]==settings.exportDeb&&[stored[@"exportDylib"] boolValue]==settings.exportDylib);StudioBuildPreferences *reopened=[[StudioBuildPreferences alloc] initWithStyle:UITableViewStyleInsetGrouped];reopened.root=settings.root;[reopened loadViewIfNeeded];result[@"reopenPreservesState"]=@(reopened.exportDeb==settings.exportDeb&&reopened.exportDylib==settings.exportDylib);result[@"noSaveButton"]=@(settings.navigationItem.rightBarButtonItem==nil);
  NSString *testRoot=[Docs() stringByAppendingPathComponent:@"AutosaveMetadataFixture"];[NSFileManager.defaultManager createDirectoryAtPath:testRoot withIntermediateDirectories:YES attributes:nil error:nil];JSONWrite(@{@"name":@"Before",@"package":@NO},[testRoot stringByAppendingPathComponent:@"MobileCompiler.json"],nil);StudioProjectSettings *meta=[[StudioProjectSettings alloc] initWithStyle:UITableViewStyleInsetGrouped];meta.root=testRoot;[meta loadViewIfNeeded];meta.fields[0].text=@"After";[meta saveChanges];result[@"metadataAutosaved"]=@([Config(testRoot)[@"name"] isEqual:@"After"]);result[@"metadataNoSaveButton"]=@(meta.navigationItem.rightBarButtonItem==nil);
  settings.patterns[1].text=@"{name}_saved";[settings saveOrRestore];NSDictionary *named=TMCEffectiveBuildOptions(settings.root?Config(settings.root):@{},NSUserDefaults.standardUserDefaults);result[@"namingAutosaved"]=@([named[@"outputPattern-dylib"] isEqual:@"{name}_saved"]);
  result[@"completedToggleEvents"]=@(completed);result[@"statesCorrect"]=@(states);result[@"stableCell"]=@(stable);result[@"mainRunLoopResponsive"]=@YES;result[@"worstEventMs"]=@(worst*1000);result[@"debOnDefaultsRootless"]=@(settings.exportDeb&&settings.schemeSwitches[0].on&&!settings.schemeSwitches[1].on&&!settings.schemeSwitches[2].on);JSONWrite(result,[Docs() stringByAppendingPathComponent:project?@"project-build-preferences-test.json":@"build-preferences-test.json"],nil);});
 });return settings;
}
UIViewController *TMCStudioDiagnosticJumpRegression(void){
 NSString *root=[Docs() stringByAppendingPathComponent:[@"DiagnosticJumpFixture-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];NSMutableString *text=[NSMutableString new];for(NSUInteger i=1;i<=900;i++)[text appendFormat:@"int diagnostic_line_%lu = %lu;\n",(unsigned long)i,(unsigned long)i];[text writeToFile:[root stringByAppendingPathComponent:@"Long.c"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[@"int first;\n" writeToFile:[root stringByAppendingPathComponent:@"First.c"] atomically:YES encoding:NSUTF8StringEncoding error:nil];JSONWrite(@{@"name":@"Jump test",@"sources":@[@"First.c",@"Long.c"],@"package":@NO},[root stringByAppendingPathComponent:@"MobileCompiler.json"],nil);
 StudioEditor *editor=[StudioEditor new];editor.root=root;__weak StudioEditor *weak=editor;
 editor.initialSyntaxReady=^{dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.3*NSEC_PER_SEC),dispatch_get_main_queue(),^{StudioEditor *v=weak;[v diagnostics];StudioDiagnostics *diagnostics=(id)v.navigationController.topViewController;[diagnostics loadViewIfNeeded];NSDictionary *d=@{@"file":@"Long.c",@"path":[root stringByAppendingPathComponent:@"Long.c"],@"line":@700,@"column":@5,@"severity":@"运行风险建议",@"message":@"Fixture suggestion"};diagnostics.items=@[d];NSMutableDictionary *result=[NSMutableDictionary new];result[@"originalTopButtonsRestored"]=@(diagnostics.navigationItem.rightBarButtonItems.count==2);result[@"scanInBottomToolbar"]=@([diagnostics.toolbarItems containsObject:diagnostics.scanButton]);[diagnostics tableView:diagnostics.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.7*NSEC_PER_SEC),dispatch_get_main_queue(),^{NSUInteger at=v.editor.selectedRange.location;result[@"targetFile"]=v.filename?:@"";result[@"targetLine"]=@([v.gutter.index lineAt:at]);CGRect caret=[v.editor caretRectForPosition:[v.editor positionFromPosition:v.editor.beginningOfDocument offset:at]];result[@"targetVisible"]=@(CGRectIntersectsRect(v.editor.bounds,caret));result[@"flashVisible"]=@(NSLocationInRange(at,((StudioDiagnosticLayoutManager *)v.editor.layoutManager).flashRange));[v.editor setContentOffset:CGPointMake(0,400) animated:NO];CGFloat manual=v.editor.contentOffset.y;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{result[@"flashCleared"]=@(((StudioDiagnosticLayoutManager *)v.editor.layoutManager).flashRange.length==0);result[@"manualScrollPreservedAfterExpiry"]=@(fabs(v.editor.contentOffset.y-manual)<1);result[@"offsetAfterExpiry"]=@(v.editor.contentOffset.y);JSONWrite(result,[Docs() stringByAppendingPathComponent:@"diagnostic-jump-test.json"],nil);});});});};return editor;
}
static void AfterStudioNavigation(UINavigationController *nav,void (^next)(void)){id<UIViewControllerTransitionCoordinator> transition=nav.transitionCoordinator;if(transition)[transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){dispatch_async(dispatch_get_main_queue(),next);}];else dispatch_async(dispatch_get_main_queue(),next);}
UIViewController *TMCStudioEditorRegression(void){
 if([NSProcessInfo.processInfo.arguments containsObject:@"--editor-navigation-test"]){
 NSString *root=[Docs() stringByAppendingPathComponent:@"EditorNavigationRegression"];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];NSMutableString *source=[NSMutableString stringWithString:@"int main_value = 1;\n"];if([NSProcessInfo.processInfo.arguments containsObject:@"--large-editor-navigation-test"])for(NSUInteger n=0;n<30000;n++)[source appendFormat:@"int navigation_line_%lu = %lu; // visible gutter regression\n",(unsigned long)n,(unsigned long)n];[source writeToFile:[root stringByAppendingPathComponent:@"main.c"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 NSMutableArray *sources=[NSMutableArray arrayWithObject:@"main.c"];for(NSUInteger i=0;i<2000;i++)[sources addObject:[NSString stringWithFormat:@"Sources/file%lu.m",(unsigned long)i]];
 JSONWrite(@{@"name":@"Navigation test",@"sources":sources},[root stringByAppendingPathComponent:@"MobileCompiler.json"],nil);
 StudioEditor *editor=[StudioEditor new];editor.root=root;__weak StudioEditor *weak=editor;
 editor.initialSyntaxReady=^{dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
 StudioEditor *v=weak;NSMutableDictionary *result=[NSMutableDictionary new];NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;[v projectSettings];result[@"projectSettingsEntryMs"]=@((NSProcessInfo.processInfo.systemUptime-start)*1000);
 AfterStudioNavigation(v.navigationController,^{StudioProjectSettings *settings=(id)v.navigationController.topViewController;result[@"settingsOpened"]=@([settings isKindOfClass:StudioProjectSettings.class]);result[@"fullSourceValidationStillRejectsMissingFiles"]=@(ValidateProject(root)!=nil);result[@"metadataFieldsLoaded"]=@(settings.fields.count==13);[settings tableView:settings.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:5 inSection:1]];
 AfterStudioNavigation(v.navigationController,^{[v.navigationController popViewControllerAnimated:YES];AfterStudioNavigation(v.navigationController,^{result[@"buildSettingsBackToProjectSettings"]=@(v.navigationController.topViewController==settings);[v.navigationController popViewControllerAnimated:YES];AfterStudioNavigation(v.navigationController,^{result[@"projectSettingsBackToEditor"]=@(v.navigationController.topViewController==v);JSONWrite(result,[Docs() stringByAppendingPathComponent:@"editor-navigation-test.json"],nil);});});});});});};return editor;}

 NSString *root=[Docs() stringByAppendingPathComponent:@"EditorLayoutRegression"];
 [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 NSMutableString *text=[NSMutableString new];for(NSUInteger i=0;i<400;i++)[text appendFormat:@"int editor_line_%lu = %lu;\n",(unsigned long)i,(unsigned long)i];
 [text writeToFile:[root stringByAppendingPathComponent:@"Viewport.c"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 JSONWrite(@{@"name":@"Editor viewport",@"sources":@[@"Viewport.c"],@"package":@NO},[root stringByAppendingPathComponent:@"MobileCompiler.json"],nil);
 StudioEditor *v=[StudioEditor new];v.root=root;__weak StudioEditor *weak=v;
 v.initialSyntaxReady=^{dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  StudioEditor *editor=weak;if(!editor)return;[editor.view layoutIfNeeded];
  NSMutableDictionary *result=[NSMutableDictionary new];
  NSString *build=[Docs() stringByAppendingPathComponent:@"EditorDiagnosticBenchmark"];[NSFileManager.defaultManager createDirectoryAtPath:build withIntermediateDirectories:YES attributes:nil error:nil];NSMutableArray *commands=[NSMutableArray new];NSMutableString *log=[NSMutableString new];for(NSUInteger i=0;i<500;i++){[commands addObject:@{@"source":@"Viewport.c",@"command":[@"clang " stringByPaddingToLength:2500 withString:@"x" startingAtIndex:0],@"exit":@0}];[log appendFormat:@"%@/Viewport.c:%lu:1: warning: benchmark\n",root,(unsigned long)i+1];}JSONWrite(@{@"commands":commands,@"success":@YES},[build stringByAppendingPathComponent:@"report.json"],nil);[log writeToFile:[build stringByAppendingPathComponent:@"build.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];editor.engine.lastBuild=build;NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;NSArray *diags=[editor diagnosticItems];result[@"diagnosticColdMs"]=@((NSProcessInfo.processInfo.systemUptime-start)*1000);result[@"diagnosticCount"]=@(diags.count);start=NSProcessInfo.processInfo.systemUptime;for(NSUInteger i=0;i<20;i++)[editor diagnosticItems];result[@"diagnosticWarmMeanMs"]=@((NSProcessInfo.processInfo.systemUptime-start)*50);start=NSProcessInfo.processInfo.systemUptime;for(NSUInteger i=0;i<10;i++)[editor openFile:@"Viewport.c"];result[@"fileOpenMeanMs"]=@((NSProcessInfo.processInfo.systemUptime-start)*100);
  result[@"scrollEnabled"]=@(editor.editor.scrollEnabled);result[@"panEnabled"]=@(editor.editor.panGestureRecognizer.enabled);
  result[@"contentHeight"]=@(editor.editor.contentSize.height);result[@"viewportHeight"]=@(editor.editor.bounds.size.height);
  editor.editor.selectedRange=NSMakeRange([editor.editor.text rangeOfString:@"int editor_line_30"].location,0);
  [editor.editor setContentOffset:CGPointMake(0,450) animated:NO];
  result[@"scrollOffset"]=@(editor.editor.contentOffset.y);result[@"sharedDrawingSurface"]=@([editor.editor isKindOfClass:StudioCodeTextView.class]&&editor.gutter.textView==editor.editor&&editor.gutter.superview==nil);
  [editor.editor becomeFirstResponder];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
   [editor.view layoutIfNeeded];result[@"keyboardVisible"]=@(editor.keyboardVisible);result[@"keyboardViewportHeight"]=@(editor.editor.bounds.size.height);
   CGFloat before=editor.editor.contentOffset.y;editor.logVisible=YES;[editor endEditing];
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.6*NSEC_PER_SEC),dispatch_get_main_queue(),^{
    [editor.view layoutIfNeeded];[editor.editor setContentOffset:CGPointMake(0,700) animated:NO];
    result[@"scrollAfterKeyboard"]=@(editor.editor.contentOffset.y);result[@"offsetDuringKeyboard"]=@(before);result[@"lineNumberViewIsOverlay"]=@(editor.gutter.superview!=nil);
    JSONWrite(result,[Docs() stringByAppendingPathComponent:@"editor-layout-test.json"],nil);
   });
  });
 });};return v;
}
#endif

#include "../tests/MaintenanceRegression.inc"

#if TARGET_OS_SIMULATOR
#include "../tests/AIRuntimeRegression.inc"
#endif

#if TARGET_OS_SIMULATOR
#include "../tests/AIV2IntegrationRegression.inc"
#include "../tests/AIChat122Regression.inc"
#include "../tests/AIWorkspace133Regression.inc"
#include "../tests/AIAudio110Regression.inc"
UIViewController *TFAIAttachments108Regression(void){UIViewController *view=[UIViewController new];view.view.backgroundColor=UIColor.systemBackgroundColor;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{TFAIV2AttachmentsRegression(^(NSDictionary *result){JSONWrite(result,[Docs() stringByAppendingPathComponent:@"ai-attachments108.json"],nil);});});return [[TMCNavigationController alloc]initWithRootViewController:view];}
UIViewController *TFAIRecovery110Regression(void){UIViewController *v=[UIViewController new];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{TFAIRunV2RuntimeRegression(^(NSDictionary *r){JSONWrite(r,[Docs() stringByAppendingPathComponent:@"ai-recovery110.json"],nil);});});return v;}
UIViewController *TFAIV2Regression(void){UITabBarController *tabs=(id)TMCStudioRoot();dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{TFAIV2NavigationRegression(tabs,^(NSDictionary *result){JSONWrite(result,[Docs() stringByAppendingPathComponent:@"ai-v2-navigation.json"],nil);});});return tabs;}
#endif

// External reception reuses the same importer/session runtime as in-app actions.
static UINavigationController *TFReceiveNavigation(UIViewController *host){UIViewController *v=host;while(v.presentingViewController)v=v.presentingViewController;if([v isKindOfClass:UITabBarController.class])v=((UITabBarController *)v).selectedViewController;if([v isKindOfClass:UINavigationController.class])return (id)v;return v.navigationController;}
void TFStudioOpenReceivedProject(UIViewController *host,NSString *root){UINavigationController *nav=TFReceiveNavigation(host);StudioEditor *editor=[StudioEditor new];editor.root=root;[nav pushViewController:editor animated:YES];}
void TFStudioImportReceived(UIViewController *host,NSURL *url,BOOL archive){CompilerController *importer=[CompilerController new];importer.presentationHost=host;objc_setAssociatedObject(host,@selector(TF_receivedImporter),importer,OBJC_ASSOCIATION_RETAIN_NONATOMIC);__weak UIViewController *weak=host;importer.importCompletion=^(NSString *root){TFStudioOpenReceivedProject(weak,root);objc_setAssociatedObject(weak,@selector(TF_receivedImporter),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);};if(archive)[importer importArchiveURL:url];else[importer importURLs:@[url]];}
void TFStudioReceiveAttachments(UIViewController *host,NSArray *entries,NSDictionary *record){if(!entries.count)return;UINavigationController *nav=TFReceiveNavigation(host);NSString *scope=record[@"storageProjectID"]?:@"general";if(record)TFAIFlushOpenSession(scope,record[@"id"]);dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSMutableDictionary *session=record?[TFAISessions loadSession:record[@"id"] project:scope]:[TFAISessions create:scope title:@"新会话"];NSError *error=nil;BOOL ok=NO;if(session){NSMutableArray *pending=[session[@"pendingAttachments"] isKindOfClass:NSArray.class]?[session[@"pendingAttachments"] mutableCopy]:[NSMutableArray new];if(pending.count+entries.count<=80){[pending addObjectsFromArray:entries];ok=[TFAISessions saveMetadata:@{@"pendingAttachments":pending} identifier:session[@"id"] project:scope error:&error];}else error=[NSError errorWithDomain:@"Incoming" code:1 userInfo:@{NSLocalizedDescriptionKey:@"会话待发送附件超过 80 项，请先清理部分附件。"}];}dispatch_async(dispatch_get_main_queue(),^{if(!ok){Message(host,@"会话附件未保存",error.localizedDescription?:@"会话已删除，请重新选择。");return;}UIViewController *presenter=host;while(presenter.parentViewController)presenter=presenter.parentViewController;void(^open)(void)=^{NSMutableDictionary *target=[session mutableCopy];target[@"incomingAttachments"]=entries;OpenAISession(nav,target,nil);};if(presenter.presentingViewController)[presenter dismissViewControllerAnimated:YES completion:open];else open();});});}

#if TARGET_OS_SIMULATOR
#include "../tests/AIShare114Regression.inc"
#endif

UIViewController *TMCStudioSDKRegression(void){
 StudioBuildPreferences *global=[[StudioBuildPreferences alloc] initWithStyle:UITableViewStyleInsetGrouped];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
 NSUserDefaults *u=NSUserDefaults.standardUserDefaults;id oldSDK=[u objectForKey:@"StudioSDKVersion"],oldMin=[u objectForKey:@"StudioDeploymentTarget"];
 [u setObject:@"16.4" forKey:@"StudioSDKVersion"];[u setObject:@"15.0" forKey:@"StudioDeploymentTarget"];
 NSMutableDictionary *r=[NSMutableDictionary new];
 r[@"globalSDKSave"]=@([global saveSDKValue:@"26.0" key:@"sdkVersion"]);
 r[@"globalMinimumSave"]=@([global saveSDKValue:@"18.6" key:@"deploymentTarget"]);
 r[@"globalReopen"]=@([TMCSDKBuildSettings(@{},u,nil)[@"deploymentTarget"] isEqual:@"18.6"]);
 StudioBuildPreferences *project=[[StudioBuildPreferences alloc] initWithStyle:UITableViewStyleInsetGrouped];project.root=[Docs() stringByAppendingPathComponent:[@"SDK118Fixture-" stringByAppendingString:NSUUID.UUID.UUIDString]];
 [NSFileManager.defaultManager createDirectoryAtPath:project.root withIntermediateDirectories:YES attributes:nil error:nil];JSONWrite(@{@"name":@"SDK test",@"package":@NO},[project.root stringByAppendingPathComponent:@"MobileCompiler.json"],nil);[project loadViewIfNeeded];
 r[@"projectMinimumSave"]=@([project saveSDKValue:@"15.0" key:@"deploymentTarget"]);r[@"projectSDKSave"]=@([project saveSDKValue:@"16.4" key:@"sdkVersion"]);
 StudioBuildPreferences *reopened=[[StudioBuildPreferences alloc] initWithStyle:UITableViewStyleInsetGrouped];reopened.root=project.root;[reopened loadViewIfNeeded];
 r[@"projectReopen"]=@([TMCSDKBuildSettings(Config(reopened.root),u,nil)[@"sdkVersion"] isEqual:@"16.4"]);
 r[@"projectInherit"]=@([project saveSDKValue:nil key:@"sdkVersion"]&&[project saveSDKValue:nil key:@"deploymentTarget"]&&[TMCSDKBuildSettings(Config(project.root),u,nil)[@"sdkVersion"] isEqual:@"26.0"]);
 r[@"unrelatedConfigPreserved"]=@([Config(project.root)[@"package"] isEqual:@NO]&&[Config(project.root)[@"name"] isEqual:@"SDK test"]);
 JSONWrite(r,[Docs() stringByAppendingPathComponent:@"sdk118-ui-test.json"],nil);
 if(oldSDK)[u setObject:oldSDK forKey:@"StudioSDKVersion"];else[u removeObjectForKey:@"StudioSDKVersion"];if(oldMin)[u setObject:oldMin forKey:@"StudioDeploymentTarget"];else[u removeObjectForKey:@"StudioDeploymentTarget"];
 [NSFileManager.defaultManager removeItemAtPath:project.root error:nil];
 [global.settingCells removeAllObjects];[global.tableView reloadData];[global.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
 });return global;
}
