#import "TFAIMarkdown.h"
// Cache only Foundation parsing results: no view, font or trait access on the parsing queue.
static NSCache *AIParsedMarkdown(void){static NSCache *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.totalCostLimit=6*1024*1024;cache.countLimit=512;});return cache;}
NSAttributedString *TFAIParsedMarkdown(NSString *source,BOOL markdown){
 source=source?:@"";if(!markdown)return [[NSAttributedString alloc]initWithString:source];
 NSAttributedString *cached=[AIParsedMarkdown() objectForKey:source];if(cached)return cached;
 NSAttributedStringMarkdownParsingOptions *options=[NSAttributedStringMarkdownParsingOptions new];options.interpretedSyntax=NSAttributedStringMarkdownInterpretedSyntaxInlineOnlyPreservingWhitespace;options.allowsExtendedAttributes=NO;options.failurePolicy=NSAttributedStringMarkdownParsingFailureReturnPartiallyParsedIfPossible;
 NSAttributedString *text=[[NSAttributedString alloc]initWithMarkdownString:source options:options baseURL:nil error:nil]?:[[NSAttributedString alloc]initWithString:source];[AIParsedMarkdown() setObject:text forKey:source cost:source.length*2+text.length*4];return text;
}
NSMutableAttributedString *TFAIInlineMarkdown(NSString *source,BOOL markdown){
 UIFont *base=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];NSMutableAttributedString *text=[TFAIParsedMarkdown(source,markdown) mutableCopy];
 if(!text)text=[[NSMutableAttributedString alloc]initWithString:source?:@""];
 NSRange whole=NSMakeRange(0,text.length);[text addAttributes:@{NSFontAttributeName:base,NSForegroundColorAttributeName:UIColor.labelColor} range:whole];
 [text enumerateAttribute:NSInlinePresentationIntentAttributeName inRange:whole options:0 usingBlock:^(NSNumber *value,NSRange range,BOOL *stop){NSInlinePresentationIntent intent=value.unsignedIntegerValue;UIFont *font=base;
 if(intent&NSInlinePresentationIntentCode){font=[UIFont monospacedSystemFontOfSize:base.pointSize-1 weight:UIFontWeightRegular];[text addAttribute:NSBackgroundColorAttributeName value:UIColor.tertiarySystemFillColor range:range];}
 UIFontDescriptorSymbolicTraits traits=0;if(intent&NSInlinePresentationIntentStronglyEmphasized)traits|=UIFontDescriptorTraitBold;if(intent&NSInlinePresentationIntentEmphasized)traits|=UIFontDescriptorTraitItalic;if(traits){UIFontDescriptor *descriptor=[font.fontDescriptor fontDescriptorWithSymbolicTraits:font.fontDescriptor.symbolicTraits|traits];if(descriptor)font=[UIFont fontWithDescriptor:descriptor size:font.pointSize];}
 [text addAttribute:NSFontAttributeName value:font range:range];if(intent&NSInlinePresentationIntentStrikethrough)[text addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
 }];
 // Markdown images remain alt text; they never fetch remote content. Only normal web/email links open externally.
 [text removeAttribute:NSImageURLAttributeName range:whole];[text removeAttribute:NSAttachmentAttributeName range:whole];
 [text enumerateAttribute:NSLinkAttributeName inRange:whole options:0 usingBlock:^(id value,NSRange range,BOOL *stop){if(!value)return;NSURL *url=[value isKindOfClass:NSURL.class]?value:[value isKindOfClass:NSString.class]?[NSURL URLWithString:value]:nil;if(![@[@"https",@"http",@"mailto"] containsObject:url.scheme.lowercaseString])[text removeAttribute:NSLinkAttributeName range:range];}];
 return text;
}
void TFAIAddSourceLinks(NSMutableAttributedString *text){NSRegularExpression *refs=[NSRegularExpression regularExpressionWithPattern:@"(?:[A-Za-z0-9_./-]+\\.(?:m|mm|xm|x|h|hpp|c|cpp|json|plist|swift)):[0-9]+" options:0 error:nil];for(NSTextCheckingResult *match in [refs matchesInString:text.string options:0 range:NSMakeRange(0,text.length)]){NSString *ref=[[text.string substringWithRange:match.range] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];[text addAttribute:NSLinkAttributeName value:[@"tweakforge-ai://file?ref=" stringByAppendingString:ref] range:match.range];}}
