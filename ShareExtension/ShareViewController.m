#import <UIKit/UIKit.h>
#import "TFShareLauncher.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "../App/Incoming/TFIncoming.h"
#import "../App/Incoming/TFShareTransfer.h"
#import "../App/Incoming/TFShareGroups.h"
@interface ShareViewController:UIViewController<UIDocumentPickerDelegate>
@property UILabel *status;
@property UIImageView *receiveIcon;
@property UIButton *diagnostic;
@property BOOL appeared;
@property BOOL finishing;
@property NSUInteger presentationGeneration;
@property UIButton *openButton;
@property TFShareLauncher *launcher;
@property NSString *readyJob;
@property UIButton *done;
@property UIButton *exportButton;
@property UIActivityIndicatorView *spinner;
@property NSUInteger files;
@property NSError *failure;
@property unsigned long long bytes;
@property NSURL *temporary;
@property NSArray<NSURL *> *exportURLs;
@end
@implementation ShareViewController
- (void)viewDidLoad{
 [super viewDidLoad];self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;self.title=@"存入 Dylix";
 UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.alignment=UIStackViewAlignmentCenter;stack.spacing=18;stack.translatesAutoresizingMaskIntoConstraints=NO;
 UIImageView *image=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"tray.and.arrow.down"]];self.receiveIcon=image;image.hidden=YES;image.tintColor=UIColor.secondaryLabelColor;[stack addArrangedSubview:image];
 self.spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];[self.spinner startAnimating];[stack addArrangedSubview:self.spinner];
 self.status=[UILabel new];self.status.text=@"正在接收文件…";self.status.hidden=YES;self.status.numberOfLines=0;self.status.textAlignment=NSTextAlignmentCenter;self.status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];[stack addArrangedSubview:self.status];
 self.openButton=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *openConfig=UIButtonConfiguration.filledButtonConfiguration;openConfig.title=@"打开 Dylix";openConfig.image=[UIImage systemImageNamed:@"arrow.up.forward.app"];openConfig.imagePadding=8;self.openButton.configuration=openConfig;[self.openButton addTarget:self action:@selector(openHost) forControlEvents:UIControlEventTouchUpInside];self.openButton.hidden=YES;[stack addArrangedSubview:self.openButton];
 self.exportButton=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *config=UIButtonConfiguration.filledButtonConfiguration;config.title=@"选择保存位置";config.image=[UIImage systemImageNamed:@"folder"];config.imagePadding=8;config.cornerStyle=UIButtonConfigurationCornerStyleMedium;self.exportButton.configuration=config;[self.exportButton addTarget:self action:@selector(exportFiles) forControlEvents:UIControlEventTouchUpInside];self.exportButton.hidden=YES;[stack addArrangedSubview:self.exportButton];
 self.done=[UIButton buttonWithType:UIButtonTypeSystem];[self.done setTitle:@"完成" forState:UIControlStateNormal];[self.done addTarget:self action:@selector(doneShare) forControlEvents:UIControlEventTouchUpInside];self.done.hidden=YES;[stack addArrangedSubview:self.done];UIButton *diagnostic=[UIButton buttonWithType:UIButtonTypeSystem];self.diagnostic=diagnostic;diagnostic.hidden=YES;[diagnostic setTitle:[NSString stringWithFormat:@"接收诊断 · %@",NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]?:@""] forState:UIControlStateNormal];diagnostic.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];[diagnostic addTarget:self action:@selector(showDiagnostics) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:diagnostic];
 [self.view addSubview:stack];[NSLayoutConstraint activateConstraints:@[[stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],[stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],[stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28]]];[self receive];
}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];self.appeared=YES;if(self.readyJob&&!self.launcher)[self openHost];}
- (void)showRecovery{self.receiveIcon.hidden=NO;self.status.hidden=NO;self.diagnostic.hidden=NO;[self.spinner stopAnimating];}
- (void)showDiagnostics{NSMutableDictionary *report=[TFShareContainerDiagnostics() mutableCopy];report[@"launch"]=self.launcher.snapshot?:@{@"state":@"notStarted"};NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];NSString *text=data?[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]:@"诊断读取失败";UIAlertController *a=[UIAlertController alertControllerWithTitle:@"分享接收诊断" message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"复制诊断" style:UIAlertActionStyleDefault handler:^(id x){UIPasteboard.generalPasteboard.string=text;}]];[self presentViewController:a animated:YES completion:nil];}
- (void)openHost{
 if(!self.readyJob||!self.appeared||self.finishing)return;
 if(!self.launcher){self.launcher=[TFShareLauncher new];__weak typeof(self) weak=self;
  self.launcher.primary=^(NSURL *url,void(^completion)(BOOL)){UIResponder *responder=weak;NSUInteger hops=0;NSMutableSet *visited=[NSMutableSet new];while(responder&&hops++<64){NSValue *key=[NSValue valueWithNonretainedObject:responder];if([visited containsObject:key])break;[visited addObject:key];if([responder isKindOfClass:UIApplication.class]){[(UIApplication *)responder openURL:url options:@{} completionHandler:completion];return;}responder=responder.nextResponder;}completion(NO);};
  self.launcher.fallback=^(NSURL *url,void(^completion)(BOOL)){if(!weak.extensionContext){completion(NO);return;}[weak.extensionContext openURL:url completionHandler:completion];};
  self.launcher.updated=^(NSDictionary *snapshot){typeof(self) strong=weak;if(!strong||strong.finishing)return;NSUInteger generation=++strong.presentationGeneration;NSString *state=snapshot[@"state"];BOOL opening=[state isEqual:@"opening"];strong.openButton.enabled=!opening;strong.done.enabled=!opening;if([state isEqual:@"opened"]){[strong doneShare];return;}if(opening){strong.status.hidden=YES;strong.receiveIcon.hidden=YES;strong.diagnostic.hidden=YES;strong.openButton.hidden=YES;strong.done.hidden=YES;[strong.spinner startAnimating];return;}
   // Some systems return NO even while the main app is being opened. Avoid
   // flashing an error during that transition; keep files queued either way.
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{typeof(self) current=weak;if(!current||current.finishing||current.presentationGeneration!=generation||![current.launcher.snapshot[@"state"] isEqual:@"failed"])return;[current showRecovery];current.openButton.hidden=NO;current.done.hidden=NO;current.status.text=@"文件已接收。若尚未进入 Dylix，可点击打开，或稍后从桌面进入。";});
  };
 }
 [self.launcher openIncomingJob:self.readyJob];
}
- (void)doneShare{if(self.finishing)return;self.finishing=YES;self.presentationGeneration++;if(self.temporary)[NSFileManager.defaultManager removeItemAtURL:self.temporary error:nil];[self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];}
- (void)exportFiles{
 if(!self.exportURLs.count||self.presentedViewController)return;
 UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForExportingURLs:self.exportURLs asCopy:YES];picker.delegate=self;picker.shouldShowFileExtensions=YES;picker.modalPresentationStyle=UIModalPresentationFormSheet;
 [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller{self.status.text=@"尚未保存，文件仍在这里。\n\n请选择「我的 iPhone → Dylix」并保存；随后打开 Dylix 自动识别。";}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
 if(!urls.count)return;
 [self showRecovery];self.status.text=@"文件已保存\n\n若保存于「我的 iPhone → Dylix」，打开 App 后会自动识别。\n\n保存到其他位置时，可在 App 中选择导入，或在「文件」中选择“用 Dylix 打开”。";self.exportButton.hidden=YES;[self.done setTitle:@"完成" forState:UIControlStateNormal];
}
- (void)receive{
 NSURL *group=TFShareContainer();
 NSMutableArray *providers=[NSMutableArray new];for(NSExtensionItem *item in self.extensionContext.inputItems)for(NSItemProvider *p in item.attachments)if([p hasItemConformingToTypeIdentifier:UTTypeData.identifier])[providers addObject:p];
 if(!providers.count||providers.count>20){[self showRecovery];self.status.text=@"每次接收 1–20 个文件；请分享文件本身，而非网页链接。";self.done.hidden=NO;return;}
 NSString *job=NSUUID.UUID.UUIDString;
 NSURL *pending=group?[group URLByAppendingPathComponent:@"TweakForgeShare/Pending" isDirectory:YES]:[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
 NSURL *staging=[pending URLByAppendingPathComponent:[@".receiving-" stringByAppendingString:job] isDirectory:YES];
 NSError *error=nil;if(![NSFileManager.defaultManager createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]){
  // Some signers leave an entitlement but no usable group container: use local export.
  group=nil;pending=[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];staging=[pending URLByAppendingPathComponent:[@".receiving-" stringByAppendingString:job] isDirectory:YES];error=nil;
  if(![NSFileManager.defaultManager createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]){[self showRecovery];self.status.text=error.localizedDescription;self.done.hidden=NO;return;}
 }
 BOOL direct=group!=nil;if(!direct)self.temporary=staging;
 dispatch_group_t wait=dispatch_group_create();NSLock *lock=[NSLock new];NSMutableArray *exports=[NSMutableArray new];
 for(NSItemProvider *p in providers){dispatch_group_enter(wait);[p loadFileRepresentationForTypeIdentifier:UTTypeData.identifier completionHandler:^(NSURL *url,NSError *e){
  [lock lock];NSError *failure=e;
  if(url&&!failure){NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:&failure];unsigned long long size=[a[NSFileSize] unsignedLongLongValue];
   if(![a[NSFileType] isEqual:NSFileTypeRegular]||size>4ULL*1024*1024*1024||size>4ULL*1024*1024*1024-self.bytes)failure=[NSError errorWithDomain:@"TweakForge.Share" code:1 userInfo:@{NSLocalizedDescriptionKey:@"只接收普通文件，合计上限 4 GB。"}];
   else{NSString *name=url.lastPathComponent;if([name hasPrefix:@"."]||!name.length)name=@"SharedFile";NSString *identifier=NSUUID.UUID.UUIDString;
    NSString *folder=[staging.path stringByAppendingPathComponent:identifier];NSString *target=[folder stringByAppendingPathComponent:direct?name:TFShareTransferName(name,identifier)];
    if([NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&failure]&&[NSFileManager.defaultManager copyItemAtPath:url.path toPath:target error:&failure]){self.files++;self.bytes+=size;[exports addObject:[NSURL fileURLWithPath:target]];}
   }
  }else if(!failure)failure=[NSError errorWithDomain:@"TweakForge.Share" code:2 userInfo:@{NSLocalizedDescriptionKey:@"来源 App 未返回文件副本。"}];
  if(failure)self.failure=failure;[lock unlock];dispatch_group_leave(wait);
 }];}
 dispatch_group_notify(wait,dispatch_get_main_queue(),^{
  [self.spinner stopAnimating];NSError *e=self.failure;
  if(!e&&direct){NSURL *ready=[pending URLByAppendingPathComponent:job isDirectory:YES];[NSFileManager.defaultManager moveItemAtURL:staging toURL:ready error:&e];}
  if(e){[NSFileManager.defaultManager removeItemAtURL:staging error:nil];[self showRecovery];self.status.text=e.localizedDescription;self.done.hidden=NO;return;}
  if(direct){[self.spinner startAnimating];self.readyJob=job;if(self.appeared)[self openHost];return;}
  else{[self showRecovery];self.exportURLs=exports;self.status.text=[NSString stringWithFormat:@"已准备 %lu 个文件\n\n选择「我的 iPhone → Dylix」保存，再打开 App 自动识别。\n\n此方式适用于普通证书安装，无需共享组权限。",(unsigned long)self.files];self.exportButton.hidden=NO;[self.done setTitle:@"取消接收" forState:UIControlStateNormal];}
  self.done.hidden=NO;
 });
}
@end
