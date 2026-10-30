#import "../AIContracts.h"
#import "../../GlassSupport.h"
static inline void AIAlert(UIViewController *host,NSString *title,NSString *message) {
 UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[host presentViewController:a animated:YES completion:nil];
}
static inline UIBarButtonItem *AIBar(NSString *icon,NSString *label,id target,SEL selector) {
 UIBarButtonItem *b=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:icon] style:UIBarButtonItemStylePlain target:target action:selector];b.accessibilityLabel=label;return b;
}
static inline UITableViewCell *AICell(NSString *title,NSString *detail,NSString *icon) {
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.text=title;c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];c.textLabel.adjustsFontForContentSizeCategory=YES;c.detailTextLabel.text=detail;c.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;c.imageView.image=icon?[UIImage systemImageNamed:icon]:nil;c.imageView.tintColor=UIColor.systemIndigoColor;return c;
}
@interface TFAIFieldSheet : UIViewController
@property NSString *value;
@property NSString *hint;
@property BOOL secure;
@property UITextView *text;
@property(copy) void (^save)(NSString *);
@end
