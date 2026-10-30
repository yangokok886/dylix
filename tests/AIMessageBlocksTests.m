#import <Foundation/Foundation.h>
#import "../App/AI/UI/TFAIMessageBlocks.h"
static int checks=0;
static void Check(BOOL ok,NSString *name){checks++;if(!ok){NSLog(@"FAIL %@",name);exit(1);}}
int main(){@autoreleasepool{
NSArray *b=TFAIMessageBlocks(@"二进制基本情况\n\n| 项目 | 内容 |\n| --- | --- |\n| 架构 | **arm64** |\n| 格式 | Mach-O |\n\n分析结束");
Check(b.count==3,@"mixed prose and table");Check([b[1][@"kind"] isEqual:@"table"],@"table recognized");Check([b[1][@"rows"] count]==2,@"all rows retained");Check([b.lastObject[@"text"] containsString:@"分析结束"],@"trailing prose retained");
b=TFAIMessageBlocks(@"| A | B |\n| :--- | ---: |\n| a\\|b | `x|y` |");Check([b[0][@"rows"][0][0] isEqual:@"a|b"],@"escaped pipe");Check([b[0][@"rows"][0][1] isEqual:@"`x|y`"],@"code pipe");
b=TFAIMessageBlocks(@"```text\n| A | B |\n| --- | --- |\n```\nafter");Check(b.count==2&&[b[0][@"kind"] isEqual:@"code"],@"table in fence remains code");Check([b[1][@"text"] isEqual:@"after"],@"text after code");
b=TFAIMessageBlocks(@"````objc\n```\n@end");Check([b[0][@"text"] containsString:@"@end"],@"unfinished four tick fence retains stream");
b=TFAIMessageBlocks(@"| A | B |\n| -- | --- |\n| x | y |");Check([b[0][@"kind"] isEqual:@"text"],@"invalid separator stays prose");
NSString *longText=[[@"正文" stringByPaddingToLength:60000 withString:@"内容\n" startingAtIndex:0] stringByAppendingString:@"最后一行END"];
b=TFAIMessageBlocks(longText);Check([b[0][@"text"] isEqual:longText],@"long reply preserved exactly");
b=TFAIMessageBlocks(@"");Check(b.count==0,@"empty stream");
b=TFAIMessageBlocks(@"```cpp\nreturn 1;");Check([b[0][@"text"] isEqual:@"return 1;"],@"partial code preserved");
NSLog(@"PASS %d message block checks",checks);
}return 0;}
