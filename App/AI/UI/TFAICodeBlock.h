#import <UIKit/UIKit.h>
UIView *TFAICodeBlock(NSString *source,NSString *language);
void TFAIUpdateCodeBlock(UIView *view,NSString *source,NSString *language);
NSArray *TFAICodeTokens(NSString *source);

void TFAICodeBlockSetInteractionHandler(UIView *view,void(^handler)(BOOL));
