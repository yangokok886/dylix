#import "LinkSupport.h"
#import <objc/runtime.h>
static NSArray<NSTextCheckingResult *> *Links(NSString *text){static NSDataDetector *detector;static dispatch_once_t once;dispatch_once(&once,^{detector=[NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];});return [detector matchesInString:text?:@"" options:0 range:NSMakeRange(0,text.length)];}
static BOOL WebURL(NSURL *url){return [@[@"https",@"http"] containsObject:url.scheme.lowercaseString];}
void TMCEnableTextLinks(UITextView *view){if(view.editable)return;if(!view.selectable)view.selectable=YES;if(view.dataDetectorTypes!=UIDataDetectorTypeLink)view.dataDetectorTypes=UIDataDetectorTypeLink;NSDictionary *attributes=@{NSForegroundColorAttributeName:UIColor.systemBlueColor,NSUnderlineStyleAttributeName:@(NSUnderlineStyleSingle)};if(![view.linkTextAttributes isEqual:attributes])view.linkTextAttributes=attributes;}
@interface TMCLabelLinkTap : UITapGestureRecognizer <UIGestureRecognizerDelegate>
@end
@implementation TMCLabelLinkTap
- (NSURL *)urlAtPoint:(CGPoint)point{
 UILabel *label=(id)self.view;if(![label isKindOfClass:UILabel.class]||!label.attributedText.length)return nil;
 NSMutableAttributedString *text=[label.attributedText mutableCopy];[label.attributedText enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0,text.length) options:0 usingBlock:^(id font,NSRange range,BOOL *stop){if(!font)[text addAttribute:NSFontAttributeName value:label.font range:range];}];
 NSTextStorage *storage=[[NSTextStorage alloc] initWithAttributedString:text];NSLayoutManager *layout=[NSLayoutManager new];NSTextContainer *container=[[NSTextContainer alloc] initWithSize:label.bounds.size];container.lineFragmentPadding=0;container.maximumNumberOfLines=label.numberOfLines;container.lineBreakMode=label.lineBreakMode;[layout addTextContainer:container];[storage addLayoutManager:layout];
 CGRect used=[layout usedRectForTextContainer:container];point.y-=(label.bounds.size.height-used.size.height)/2-used.origin.y;NSUInteger glyph=[layout glyphIndexForPoint:point inTextContainer:container];if(glyph>=layout.numberOfGlyphs)return nil;CGRect rect=[layout boundingRectForGlyphRange:NSMakeRange(glyph,1) inTextContainer:container];if(!CGRectContainsPoint(CGRectInset(rect,-3,-3),point))return nil;
 NSUInteger index=[layout characterIndexForGlyphAtIndex:glyph];for(NSTextCheckingResult *result in Links(text.string))if(NSLocationInRange(index,result.range)&&WebURL(result.URL))return result.URL;return nil;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch{return [self urlAtPoint:[touch locationInView:self.view]]!=nil;}
- (void)open{NSURL *url=[self urlAtPoint:[self locationInView:self.view]];if(url)[UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];}
@end
void TMCEnableLinksInView(UIView *view){if([view isKindOfClass:UITextView.class]){TMCEnableTextLinks((id)view);return;}if([view isKindOfClass:UITextField.class])return;
 if([view isKindOfClass:UILabel.class]){UILabel *label=(id)view;NSString *plain=label.text?:@"";NSString *previous=objc_getAssociatedObject(label,@selector(TMCLabelLinkText));if([previous isEqual:plain])return;objc_setAssociatedObject(label,@selector(TMCLabelLinkText),[plain copy],OBJC_ASSOCIATION_COPY_NONATOMIC);NSMutableAttributedString *text=label.attributedText?[label.attributedText mutableCopy]:[[NSMutableAttributedString alloc] initWithString:label.text?:@""];BOOL found=NO;for(NSTextCheckingResult *link in Links(text.string))if(WebURL(link.URL)){found=YES;[text addAttributes:@{NSForegroundColorAttributeName:UIColor.systemBlueColor,NSUnderlineStyleAttributeName:@(NSUnderlineStyleSingle)} range:link.range];}if(found){if(![label.attributedText isEqualToAttributedString:text])label.attributedText=text;label.userInteractionEnabled=YES;if(!objc_getAssociatedObject(label,@selector(open))){TMCLabelLinkTap *tap=[[TMCLabelLinkTap alloc] init];[tap addTarget:tap action:@selector(open)];tap.delegate=tap;tap.cancelsTouchesInView=YES;[label addGestureRecognizer:tap];objc_setAssociatedObject(label,@selector(open),tap,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}}return;}
 for(UIView *child in view.subviews)TMCEnableLinksInView(child);
}
