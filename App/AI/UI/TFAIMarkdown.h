#import <UIKit/UIKit.h>
NSMutableAttributedString *TFAIInlineMarkdown(NSString *source,BOOL markdown);
void TFAIAddSourceLinks(NSMutableAttributedString *text);

NSAttributedString *TFAIParsedMarkdown(NSString *source,BOOL markdown);
