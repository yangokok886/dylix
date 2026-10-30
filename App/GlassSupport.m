#import "GlassSupport.h"
#import <objc/message.h>
UIVisualEffect *TMCGlassEffect(BOOL interactive){
 if(UIAccessibilityIsReduceTransparencyEnabled())return nil;
 if(@available(iOS 26.0,*)){
  Class cls=NSClassFromString(@"UIGlassEffect");SEL factory=NSSelectorFromString(@"effectWithStyle:");
  if([cls respondsToSelector:factory]){UIVisualEffect *effect=((id(*)(id,SEL,NSInteger))objc_msgSend)(cls,factory,0);SEL setter=NSSelectorFromString(@"setInteractive:");if([effect respondsToSelector:setter])((void(*)(id,SEL,BOOL))objc_msgSend)(effect,setter,interactive&&!UIAccessibilityIsReduceMotionEnabled());return effect;}
 }
 return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
}
UIButtonConfiguration *TMCButtonConfiguration(BOOL prominent){
 if(@available(iOS 26.0,*))if(!UIAccessibilityIsReduceTransparencyEnabled()){
  SEL factory=NSSelectorFromString(prominent?@"prominentGlassButtonConfiguration":@"glassButtonConfiguration");
  if([UIButtonConfiguration respondsToSelector:factory])return ((id(*)(id,SEL))objc_msgSend)(UIButtonConfiguration.class,factory);
 }
 return prominent?UIButtonConfiguration.filledButtonConfiguration:UIButtonConfiguration.tintedButtonConfiguration;
}
// UINavigationBar owns its glass and scroll-edge rendering. Never insert an
// effect view into the system bar: its internal layering changes across iOS.
static void NavigationTrace(NSString *message){static dispatch_queue_t queue;static dispatch_once_t once;dispatch_once(&once,^{queue=dispatch_queue_create("com.xuegao.tweakforge.navigation.trace",DISPATCH_QUEUE_SERIAL);});NSString *line=[NSString stringWithFormat:@"%.3f %@\n",NSProcessInfo.processInfo.systemUptime,message];dispatch_async(queue,^{NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;NSString *path=[docs stringByAppendingPathComponent:@"navigation-performance.log"];NSFileManager *fm=NSFileManager.defaultManager;if([[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue]>262144)[fm removeItemAtPath:path error:nil];if(![fm fileExistsAtPath:path])[fm createFileAtPath:path contents:nil attributes:nil];NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];@try{[file seekToEndOfFile];[file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];}@catch(NSException *exception){}[file closeFile];});}
@implementation TMCNavigationController
- (void)applyStudioAppearance {NSInteger theme=[NSUserDefaults.standardUserDefaults integerForKey:@"StudioTheme"];UIUserInterfaceStyle style=theme==1?UIUserInterfaceStyleDark:theme==2?UIUserInterfaceStyleLight:UIUserInterfaceStyleUnspecified;if(self.overrideUserInterfaceStyle!=style)self.overrideUserInterfaceStyle=style;if(self.view.window.overrideUserInterfaceStyle!=style)self.view.window.overrideUserInterfaceStyle=style;}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self applyStudioAppearance];}
- (void)appearancePreferenceChanged:(NSNotification *)note{dispatch_async(dispatch_get_main_queue(),^{[self applyStudioAppearance];});}
- (void)dealloc{[[NSNotificationCenter defaultCenter] removeObserver:self];}
- (void)pushViewController:(UIViewController *)controller animated:(BOOL)animated{
 if(self.tabBarController&&self.viewControllers.count>0)controller.hidesBottomBarWhenPushed=YES;
 NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;NSString *name=NSStringFromClass(controller.class);NavigationTrace([NSString stringWithFormat:@"push %@ begin",name]);[super pushViewController:controller animated:animated];NavigationTrace([NSString stringWithFormat:@"push %@ returned %.1fms",name,(NSProcessInfo.processInfo.systemUptime-start)*1000]);dispatch_async(dispatch_get_main_queue(),^{NavigationTrace([NSString stringWithFormat:@"push %@ next-main-turn %.1fms",name,(NSProcessInfo.processInfo.systemUptime-start)*1000]);});id<UIViewControllerTransitionCoordinator> transition=self.transitionCoordinator;if(transition)[transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){NavigationTrace([NSString stringWithFormat:@"push %@ transition-ended %.1fms cancelled=%d",name,(NSProcessInfo.processInfo.systemUptime-start)*1000,context.isCancelled]);}];
}
- (void)viewDidLoad{
 [super viewDidLoad];[self applyStudioAppearance];[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearancePreferenceChanged:) name:NSUserDefaultsDidChangeNotification object:nil];
 // Semantic foreground stays legible in light/dark appearance and sheets.
 self.navigationBar.tintColor=UIColor.labelColor;
}
@end
