#import "GitPATGuide.h"
#import "HelpArticle.h"
UIViewController *TMCGitPATGuideController(void){
 NSString *path=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"GitHelp/PATGuide.json"];
 NSData *data=[NSData dataWithContentsOfFile:path];NSDictionary *guide=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
 NSArray *chapters=[guide[@"sections"] isKindOfClass:NSArray.class]?guide[@"sections"]:@[@{@"title":@"教程读取失败",@"text":@"请重新安装完整安装包，或查看 GitHub / Gitee / GitLab 官方 PAT 文档。"}];
 return TMCHelpArticle(@"如何获取 PAT",@"连接你的代码仓库。按步骤选择权限、创建令牌，再回到 Dylix 添加账号。",@"key.horizontal",chapters);
}
