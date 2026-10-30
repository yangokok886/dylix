#import "TFAITestDetail.h"
#import "TFAIUIHelpers.h"
#import "../Providers/TFAIProtocol.h"
static NSString *TFProbeTitle(NSString *key){return @{@"text":@"文本响应",@"stream":@"流式响应",@"image":@"图片理解",@"tools":@"工具调用"}[key]?:@"能力测试";}
static NSString *TFProbeState(NSString *state){return @{@"pass":@"✅ 本次验证通过",@"fail":@"❌ 本次请求失败",@"unknown":@"⚠️ 本次未证实",@"running":@"正在测试",@"pending":@"尚未测试"}[state]?:@"尚未测试";}
NSDictionary *TFAIRecordProbeResult(NSMutableDictionary *connection,NSString *capability,NSDictionary *result,NSError *error){
 BOOL pass=!error&&[result[@"status"] isEqual:@"supported"];NSString *detail=error.localizedDescription?:result[@"detail"]?:@"服务已响应，但本次回答未提供足够的能力证据。";
 NSDictionary *diagnostics=[result[@"diagnostics"] isKindOfClass:NSDictionary.class]?result[@"diagnostics"]:[error.userInfo[@"diagnostics"] isKindOfClass:NSDictionary.class]?error.userInfo[@"diagnostics"]:@{};
 NSString *secret=[TFAIConnections secret:connection[@"id"]?:@""];diagnostics=TFAISanitizeProbeDiagnostics(diagnostics,secret);detail=TFAISanitizeProbeDiagnostics(@{@"reason":detail},secret)[@"reason"]?:@"测试已完成";
 NSMutableDictionary *record=[@{@"state":pass?@"pass":error?@"fail":@"unknown",@"detail":detail,@"diagnostics":diagnostics} mutableCopy];
 NSMutableDictionary *caps=[connection[@"capabilities"] mutableCopy]?:[NSMutableDictionary new];caps[capability]=pass?@"supported":@"unknown";connection[@"capabilities"]=caps;
 NSMutableDictionary *results=[connection[@"testResults"] mutableCopy]?:[NSMutableDictionary new];results[capability]=record;connection[@"testResults"]=results;connection[@"testedAt"]=@(NSDate.date.timeIntervalSince1970);
 NSError *saveError=nil;if(![TFAIConnections save:connection secret:nil error:&saveError])record[@"saveWarning"]=saveError.localizedDescription?:@"测试记录保存失败";
 [NSNotificationCenter.defaultCenter postNotificationName:@"TFAIProbeResultChanged" object:connection[@"id"] userInfo:@{@"capability":capability,@"record":record}];
 return record;
}
static NSString *TFValue(id obj){if([obj isKindOfClass:NSString.class])return obj;if([NSJSONSerialization isValidJSONObject:obj])return [[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:nil] encoding:NSUTF8StringEncoding];return obj?[obj description]:@"未记录";}
NSString *TFAIProbeReport(NSDictionary *record,NSString *capability){
 NSDictionary *d=[record[@"diagnostics"] isKindOfClass:NSDictionary.class]?record[@"diagnostics"]:@{};NSMutableString *report=[NSMutableString stringWithFormat:@"Dylix · %@\n%@\n%@\n",TFProbeTitle(capability),TFProbeState(record[@"state"]),record[@"detail"]?:@"尚无测试记录"];
 NSArray *fields=@[@[@"timestamp",@"测试时间"],@[@"duration",@"耗时（秒）"],@[@"protocol",@"协议"],@[@"model",@"模型"],@[@"endpoint",@"请求地址"],@[@"httpStatus",@"HTTP状态"],@[@"requestSummary",@"测试内容"],@[@"expected",@"预期结果"],@[@"reason",@"判定原因"],@[@"responseText",@"模型实际回答"],@[@"responseBody",@"服务原始响应（截断并脱敏）"]];
 for(NSArray *f in fields)if(d[f[0]])[report appendFormat:@"\n%@\n%@\n",f[1],TFValue(d[f[0]])];
 if(record[@"saveWarning"])[report appendFormat:@"\n保存提示：%@\n",record[@"saveWarning"]];
 [report appendString:@"\n测试仅使用内置样例；未发送项目、会话或用户附件。测试未通过不等于模型永久不支持此能力。\n"];
 return report;
}
@interface TFAITestDetail : UITableViewController
@property NSMutableDictionary *connection;
@property NSString *capability;
@property NSDictionary *record;
@property NSArray<NSArray<NSDictionary *> *> *sections;
@property TFAITransport *transport;
@property BOOL busy,allowRetest;
@end
@implementation TFAITestDetail
- (void)viewDidLoad{[super viewDidLoad];self.title=TFProbeTitle(self.capability);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=90;self.navigationItem.rightBarButtonItems=@[AIBar(@"doc.on.doc",@"复制完整测试结果",self,@selector(copyReport)),AIBar(@"arrow.clockwise",@"重新测试此项",self,@selector(retest))];self.navigationItem.rightBarButtonItems.lastObject.enabled=self.allowRetest;[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(probeChanged:) name:@"TFAIProbeResultChanged" object:nil];[self rebuild];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)probeChanged:(NSNotification *)note{if([note.object isEqual:self.connection[@"id"]]&&[note.userInfo[@"capability"] isEqual:self.capability]){self.record=note.userInfo[@"record"];[self rebuild];}}
- (void)rebuild{
 NSDictionary *d=[self.record[@"diagnostics"] isKindOfClass:NSDictionary.class]?self.record[@"diagnostics"]:@{};
 NSMutableArray *summary=[NSMutableArray arrayWithObject:@{@"title":TFProbeState(self.record[@"state"]),@"text":self.record[@"detail"]?:@"尚未测试。点击右上角重试图标测试此项。"}];
 for(NSArray *f in @[@[@"protocol",@"协议"],@[@"model",@"模型"],@[@"endpoint",@"实际请求地址"],@[@"httpStatus",@"HTTP 状态"],@[@"timestamp",@"测试时间"],@[@"duration",@"耗时"]])if(d[f[0]]){NSString *value=TFValue(d[f[0]]);if([f[0] isEqual:@"timestamp"]&&[d[f[0]] isKindOfClass:NSNumber.class]){NSDateFormatter *format=[NSDateFormatter new];format.dateFormat=@"yyyy/MM/dd HH:mm:ss";value=[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[d[f[0]] doubleValue]]];}if([f[0] isEqual:@"duration"])value=[NSString stringWithFormat:@"%.2f 秒",[d[f[0]] doubleValue]];[summary addObject:@{@"title":f[1],@"text":value}];}
 NSMutableArray *request=[NSMutableArray new];if(d[@"testImage"])[request addObject:@{@"title":@"本次测试图片",@"image":d[@"testImage"]}];[request addObject:@{@"title":@"测试提示词与发送内容",@"text":TFValue(d[@"requestSummary"]?:@"历史版本未记录测试内容，请重新测试此项。"),@"mono":@YES}];if(d[@"expected"])[request addObject:@{@"title":@"预期结果",@"text":TFValue(d[@"expected"])}];
 NSMutableArray *response=[NSMutableArray new];for(NSArray *f in @[@[@"reason",@"判定原因"],@[@"responseText",@"模型实际回答"],@[@"responseBody",@"服务原始响应 · 已截断并脱敏"]])if(d[f[0]])[response addObject:@{@"title":f[1],@"text":TFValue(d[f[0]]),@"mono":@(![f[0] isEqual:@"reason"])}];if(!response.count)[response addObject:@{@"title":@"暂无详细响应",@"text":@"历史版本只保存了结论。重新测试后可查看请求内容、HTTP 状态和模型实际回答。"}];
 self.sections=@[summary,request,response];[self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return self.sections.count;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return self.sections[s].count;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"测试结果",@"内置测试样例",@"响应与判定"][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==2?@"结果只反映本次请求。服务路由、图片格式、提示词和模型实际输出均会影响结论。长按文字可选中复制，也可用右上角复制完整结果。":nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i{
 NSDictionary *row=self.sections[i.section][i.row];UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];c.selectionStyle=UITableViewCellSelectionStyleNone;
 UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=8;stack.translatesAutoresizingMaskIntoConstraints=NO;[c.contentView addSubview:stack];UILabel *title=[UILabel new];title.text=row[@"title"];title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];title.textColor=UIColor.secondaryLabelColor;title.numberOfLines=0;[stack addArrangedSubview:title];
 if(row[@"image"]){NSString *encoded=[row[@"image"] isKindOfClass:NSString.class]?row[@"image"]:nil;if([encoded hasPrefix:@"data:"])encoded=[encoded componentsSeparatedByString:@","].lastObject;NSData *data=[[NSData alloc]initWithBase64EncodedString:encoded?:@"" options:0];UIImageView *image=[[UIImageView alloc]initWithImage:[UIImage imageWithData:data]];image.contentMode=UIViewContentModeScaleAspectFit;[image.heightAnchor constraintEqualToConstant:170].active=YES;image.accessibilityLabel=@"发送给模型的内置测试图片";[stack addArrangedSubview:image];}
 else {UITextView *text=[UITextView new];text.editable=NO;text.scrollEnabled=NO;text.backgroundColor=UIColor.clearColor;text.textContainerInset=UIEdgeInsetsZero;text.textContainer.lineFragmentPadding=0;text.text=row[@"text"];text.font=[row[@"mono"] boolValue]?[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];text.textColor=UIColor.labelColor;[stack addArrangedSubview:text];}
 [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:12],[stack.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-12],[stack.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-16]]];return c;
}
- (void)copyReport{UIPasteboard.generalPasteboard.string=TFAIProbeReport(self.record,self.capability);UIBarButtonItem *copy=self.navigationItem.rightBarButtonItems.firstObject;copy.image=[UIImage systemImageNamed:@"checkmark"];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{copy.image=[UIImage systemImageNamed:@"doc.on.doc"];});}
- (void)retest{if(self.busy||!self.allowRetest)return;if(![self.connection[@"model"] length]){AIAlert(self,@"请选择模型",@"选择模型后再测试此项。");return;}self.busy=YES;self.navigationItem.rightBarButtonItems.lastObject.enabled=NO;self.record=@{@"state":@"running",@"detail":@"正在发送内置测试样例…"};[self rebuild];self.transport=[TFAITransport new];__weak typeof(self) weak=self;[self.transport probe:[self.connection copy] capability:self.capability completion:^(NSDictionary *result,NSError *error){TFAITestDetail *s=weak;if(!s)return;s.busy=NO;s.navigationItem.rightBarButtonItems.lastObject.enabled=YES;s.record=TFAIRecordProbeResult(s.connection,s.capability,result,error);[s rebuild];}];}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];if(self.isMovingFromParentViewController){[self.transport cancel];}}
@end
UIViewController *TFAITestDetailController(NSMutableDictionary *connection,NSString *capability,NSDictionary *record,BOOL allowRetest){TFAITestDetail *v=[[TFAITestDetail alloc]initWithStyle:UITableViewStyleInsetGrouped];v.connection=connection;v.capability=capability;v.record=record?:@{};v.allowRetest=allowRetest;return v;}
