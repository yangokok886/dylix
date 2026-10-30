#import "TFAIUIHelpers.h"
#import "../../GitDiffView.h"
@interface TFAIApprovalView : UITableViewController
@property NSDictionary *plan;
@property NSMutableIndexSet *selected;
@property(copy) void (^decision)(BOOL,NSArray<NSNumber *> *);
@property BOOL decided;
@property NSMutableDictionary<NSNumber *,TFGitDiff *> *diffViews;
@property NSMutableDictionary<NSNumber *,NSNumber *> *diffHeights;
@property NSMutableDictionary<NSNumber *,UITableViewCell *> *diffCells;
@end
@implementation TFAIApprovalView
- (void)viewDidLoad{[super viewDidLoad];self.title=@"审核本次操作";self.diffViews=[NSMutableDictionary new];self.diffHeights=[NSMutableDictionary new];self.diffCells=[NSMutableDictionary new];self.selected=[NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0,[self.plan[@"edits"] count])];self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=180;self.navigationItem.rightBarButtonItem=AIBar(@"checkmark",@"批准所选",self,@selector(accept));self.navigationItem.leftBarButtonItem=AIBar(@"xmark",@"拒绝",self,@selector(reject));self.modalInPresentation=YES;self.navigationController.modalInPresentation=YES;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?1:[self.plan[@"edits"] count]*2;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return s==0?@"批准仅用于下面这次操作":@"逐项选择修改 · 红色删除 / 绿色新增";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==1?@"应用前再次核对文件内容。撤回只恢复本次 AI 修改，后续手工编辑会受到保护。删除和覆盖文件需你在此明确确认。":nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i {
 if(i.section==0){NSDictionary *request=self.plan[@"request"];NSMutableDictionary *details=[request[@"arguments"] mutableCopy]?:[NSMutableDictionary new];for(NSString *key in @[@"edits",@"before",@"after",@"content",@"text"])[details removeObjectForKey:key];NSData *data=[NSJSONSerialization dataWithJSONObject:details options:NSJSONWritingPrettyPrinted error:nil];NSString *args=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];UITableViewCell *c=AICell(self.plan[@"summary"]?:request[@"name"],[NSString stringWithFormat:@"工具：%@\n%@",request[@"name"]?:@"操作",args?:@""],@"hand.raised");c.selectionStyle=UITableViewCellSelectionStyleNone;return c;}
 NSUInteger editIndex=i.row/2;NSDictionary *edit=self.plan[@"edits"][editIndex];
 if(i.row%2){NSNumber *key=@(editIndex);UITableViewCell *cell=self.diffCells[key];if(!cell){cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];cell.selectionStyle=UITableViewCellSelectionStyleNone;TFGitDiff *diff=[TFGitDiff new];diff.compact=YES;diff.title=edit[@"path"]?:@"文件";diff.content=TFReviewPatch(edit[@"before"]?:@"",edit[@"after"]?:@"",edit[@"path"]?:@"file");self.diffViews[key]=diff;[self addChildViewController:diff];[cell.contentView addSubview:diff.view];diff.view.translatesAutoresizingMaskIntoConstraints=NO;[NSLayoutConstraint activateConstraints:@[[diff.view.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],[diff.view.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],[diff.view.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],[diff.view.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor]]];[diff didMoveToParentViewController:self];__weak typeof(self) weak=self;diff.contentHeightChanged=^(CGFloat height){CGFloat h=MAX(100,MIN(520,ceil(height)));if(fabs([weak.diffHeights[key] doubleValue]-h)>1){weak.diffHeights[key]=@(h);[UIView performWithoutAnimation:^{[weak.tableView beginUpdates];[weak.tableView endUpdates];}];}};self.diffCells[key]=cell;}return cell;}
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSString *kind=edit[@"kind"]?:@"source";NSString *label=@{@"source":@"源码修改",@"config":@"项目配置",@"configuration":@"项目配置",@"create":@"新建文件",@"delete":@"删除文件"}[kind]?:kind;c.textLabel.text=[NSString stringWithFormat:@"%@ · %@",edit[@"path"]?:@"文件",label];c.textLabel.numberOfLines=0;c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];c.accessoryType=[self.selected containsIndex:editIndex]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
 c.detailTextLabel.text=edit[@"reason"]?:@"模型提出，待你确认";c.detailTextLabel.numberOfLines=0;c.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];c.detailTextLabel.textColor=UIColor.secondaryLabelColor;return c;
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)indexPath{if(indexPath.section==1&&indexPath.row%2)return [self.diffHeights[@(indexPath.row/2)] doubleValue]?:180;return UITableViewAutomaticDimension;}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i{[t deselectRowAtIndexPath:i animated:YES];if(i.section!=1||i.row%2)return;NSUInteger editIndex=i.row/2;if([self.selected containsIndex:editIndex])[self.selected removeIndex:editIndex];else[self.selected addIndex:editIndex];[t reloadRowsAtIndexPaths:@[i] withRowAnimation:UITableViewRowAnimationNone];self.navigationItem.rightBarButtonItem.enabled=self.selected.count>0;}

- (void)finish:(BOOL)yes{if(self.decided)return;self.decided=YES;NSMutableArray *indexes=[NSMutableArray new];[self.selected enumerateIndexesUsingBlock:^(NSUInteger idx,BOOL *stop){[indexes addObject:@(idx)];}];void(^block)(BOOL,NSArray *)=self.decision;[self dismissViewControllerAnimated:YES completion:^{if(block)block(yes,[self.plan[@"edits"] count]?indexes:nil);}];}
- (void)accept{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认执行所选操作？" message:self.plan[@"summary"]?:@"批准仅作用于当前参数和文件版本。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"再看看" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"执行" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self finish:YES];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)reject{[self finish:NO];}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];if((self.isBeingDismissed||self.navigationController.isBeingDismissed)&&!self.decided){self.decided=YES;if(self.decision)self.decision(NO,nil);}}
@end
UIViewController *TFAIApprovalController(NSDictionary *plan,void(^decision)(BOOL,NSArray *)){TFAIApprovalView *v=[[TFAIApprovalView alloc]initWithStyle:UITableViewStyleInsetGrouped];v.plan=plan;v.decision=decision;return v;}
